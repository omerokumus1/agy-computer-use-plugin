import assert from "node:assert/strict";
import { execFile, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { promisify } from "node:util";
import {
  filterUiElements,
  normalizeHotkey,
  normalizeKeyName,
  normalizeModifiers,
} from "../scripts/drivers/common.mjs";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..");

test("normalizeKeyName and normalizeModifiers resolve primary across macOS and Windows", () => {
  assert.equal(normalizeKeyName("Return"), "enter");
  assert.equal(normalizeKeyName("ESC"), "escape");
  assert.deepEqual(normalizeModifiers(["primary", "Shift"], "darwin"), ["cmd", "shift"]);
  assert.deepEqual(normalizeModifiers(["primary", "Shift"], "win32"), ["ctrl", "shift"]);
  assert.deepEqual(normalizeModifiers(["option", "super"], "win32"), ["alt", "win"]);
});

test("normalizeHotkey separates modifiers and main key", () => {
  assert.deepEqual(normalizeHotkey(["primary", "shift", "S"], "darwin"), {
    modifiers: ["cmd", "shift"],
    key: "s",
    extraKeys: [],
  });
  assert.deepEqual(normalizeHotkey(["primary", "c"], "win32"), {
    modifiers: ["ctrl"],
    key: "c",
    extraKeys: [],
  });
});

test("filterUiElements matches query and role case-insensitively", () => {
  const sample = [
    { role: "AXButton", title: "Save Changes", cx: 100, cy: 200 },
    { role: "AXTextField", title: "Search", value: "hello", cx: 50, cy: 50 },
    { role: "AXButton", title: "Cancel", cx: 200, cy: 200 },
  ];
  const res = filterUiElements(sample, { query: "save", role: "button" });
  assert.equal(res.length, 1);
  assert.equal(res[0].title, "Save Changes");
});

test("safety-hook allows normal calls, logs audit, and honors EMERGENCY_STOP", async () => {
  const tmpData = fs.mkdtempSync(path.join(os.tmpdir(), "cu-hook-test-"));
  try {
    const runHook = (envExtras = {}) =>
      new Promise((resolve, reject) => {
        const p = spawn(process.execPath, [path.join(ROOT, "scripts", "safety-hook.mjs")], {
          env: { ...process.env, PLUGIN_DATA: tmpData, ...envExtras },
        });
        let out = "";
        p.stdout.on("data", (d) => (out += d));
        p.on("error", reject);
        p.on("close", (code) => resolve({ code, out: JSON.parse(out) }));
        p.stdin.end(
          JSON.stringify({
            conversationId: "test-conv",
            toolCall: { name: "mcp_computer-use_desktop_type_text", args: { text: "secret123" } },
          })
        );
      });

    const allowRes = await runHook({ COMPUTER_USE_REDACT_LOGS: "1" });
    assert.equal(allowRes.code, 0);
    assert.equal(allowRes.out.decision, "allow");

    const audit = fs.readFileSync(path.join(tmpData, "audit.jsonl"), "utf8");
    assert.match(audit, /\[REDACTED 9 chars\]/);
    assert.doesNotMatch(audit, /secret123/);

    fs.writeFileSync(path.join(tmpData, "EMERGENCY_STOP"), "");
    const denyRes = await runHook();
    assert.equal(denyRes.code, 0);
    assert.equal(denyRes.out.decision, "deny");
  } finally {
    fs.rmSync(tmpData, { recursive: true, force: true });
  }
});

test("MCP server initializes, lists 26 tools, and executes live host read-only tools", async () => {
  const tmpData = fs.mkdtempSync(path.join(os.tmpdir(), "cu-mcp-test-"));
  const server = spawn(process.execPath, [path.join(ROOT, "scripts", "mcp-server.mjs")], {
    env: { ...process.env, PLUGIN_ROOT: ROOT, PLUGIN_DATA: tmpData },
    stdio: ["pipe", "pipe", "pipe"],
  });

  let buf = "";
  const pending = new Map();
  let stderr = "";
  server.stderr.on("data", (d) => (stderr += d));
  server.stdout.setEncoding("utf8");
  server.stdout.on("data", (chunk) => {
    buf += chunk;
    let idx;
    while ((idx = buf.indexOf("\n")) !== -1) {
      const line = buf.slice(0, idx).trim();
      buf = buf.slice(idx + 1);
      if (!line) continue;
      const msg = JSON.parse(line);
      if (pending.has(msg.id)) {
        pending.get(msg.id)(msg);
        pending.delete(msg.id);
      }
    }
  });

  const rpc = (id, method, params = {}) =>
    new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error(`Timeout on ${method}. stderr=${stderr}`)), 45000);
      pending.set(id, (msg) => {
        clearTimeout(t);
        resolve(msg);
      });
      server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
    });

  try {
    const init = await rpc(1, "initialize", { protocolVersion: "2024-11-05", capabilities: {} });
    assert.equal(init.result.serverInfo.name, "computer-use-desktop");

    const list = await rpc(2, "tools/list");
    assert.equal(list.result.tools.length, 26);

    const sys = await rpc(3, "tools/call", { name: "get_system_info", arguments: {} });
    assert.ok(!sys.result.isError, sys.result.content[0].text);
    const sysJson = JSON.parse(sys.result.content[0].text);
    assert.ok(["macos", "windows"].includes(sysJson.os));

    const perms = await rpc(4, "tools/call", { name: "check_permissions", arguments: {} });
    assert.ok(!perms.result.isError);

    const screen = await rpc(5, "tools/call", { name: "get_screen_info", arguments: {} });
    assert.ok(!screen.result.isError);
    const screenJson = JSON.parse(screen.result.content[0].text);
    assert.ok(Array.isArray(screenJson.displays) && screenJson.displays.length >= 1);

    const wins = await rpc(6, "tools/call", { name: "list_windows", arguments: {} });
    assert.ok(!wins.result.isError);
    const winsJson = JSON.parse(wins.result.content[0].text);
    assert.ok(Array.isArray(winsJson) && winsJson.length >= 1);
    for (const w of winsJson) {
      assert.ok(w.bounds.width > 60 || w.bounds.height > 60, `Unexpected tiny window: ${JSON.stringify(w)}`);
    }

    const apps = await rpc(7, "tools/call", { name: "list_running_apps", arguments: {} });
    assert.ok(!apps.result.isError);
    assert.ok(JSON.parse(apps.result.content[0].text).length >= 1);

    // Clipboard roundtrip (preserve original text)
    const prevClip = await rpc(8, "tools/call", { name: "clipboard_read", arguments: {} });
    const prevClipJson = JSON.parse(prevClip.result.content[0].text);
    const sentinel = `cu-test-${Date.now()}`;
    const clipWrite = await rpc(9, "tools/call", { name: "clipboard_write", arguments: { text: sentinel } });
    assert.ok(!clipWrite.result.isError);
    const clipRead = await rpc(10, "tools/call", { name: "clipboard_read", arguments: {} });
    assert.equal(JSON.parse(clipRead.result.content[0].text).text, sentinel);
    if (prevClipJson.has_text) {
      await rpc(11, "tools/call", { name: "clipboard_write", arguments: { text: prevClipJson.text } });
    }

    // Screenshots: JPEG + grid, PNG + region + save_path, secondary display, app window
    const shotPath = path.join(tmpData, "test-region.png");
    const shot = await rpc(12, "tools/call", {
      name: "screenshot",
      arguments: { max_width: 640, format: "jpeg", grid: true },
    });
    if (!shot.result.isError) {
      assert.equal(shot.result.content[0].type, "image");
      assert.equal(shot.result.content[0].mimeType, "image/jpeg");
      assert.ok(shot.result.content[0].data.length > 500);
      const meta = JSON.parse(shot.result.content[1].text);
      assert.ok(meta.image_size.width <= 640);

      const regionShot = await rpc(13, "tools/call", {
        name: "screenshot",
        arguments: { region: { x: 0, y: 0, width: 400, height: 300 }, format: "png", max_width: 0, save_path: shotPath },
      });
      assert.ok(!regionShot.result.isError, regionShot.result.content[0].text);
      assert.equal(regionShot.result.content[0].mimeType, "image/png");
      assert.ok(fs.existsSync(shotPath) && fs.statSync(shotPath).size > 500);

      if (screenJson.displays.length > 1) {
        const disp2Shot = await rpc(14, "tools/call", {
          name: "screenshot",
          arguments: { display_id: 1, max_width: 480, format: "jpeg" },
        });
        assert.ok(!disp2Shot.result.isError, disp2Shot.result.content[0].text);
      }
    } else {
      assert.match(shot.result.content[0].text, /Screen Recording|screencapture/i);
    }

    // Wait tool (+ optional screenshot)
    const waitRes = await rpc(15, "tools/call", { name: "wait", arguments: { ms: 50, capture_screenshot: false } });
    assert.ok(!waitRes.result.isError);
    assert.equal(JSON.parse(waitRes.result.content[0].text).waited_ms, 50);

    // Accessibility & input checks (live if granted, explicit error if not)
    const permsJson = JSON.parse(perms.result.content[0].text);
    const uiRes = await rpc(16, "tools/call", { name: "get_ui_tree", arguments: { max_depth: 3, max_nodes: 25, interactive_only: true } });
    if (permsJson.accessibility) {
      assert.ok(!uiRes.result.isError, uiRes.result.content[0].text);
      const uiJson = JSON.parse(uiRes.result.content[0].text);
      assert.ok(Array.isArray(uiJson.elements));

      const beforeCur = screenJson.cursor;
      const targetX = Math.max(10, beforeCur.x + 12);
      const targetY = Math.max(10, beforeCur.y + 12);
      const mv = await rpc(17, "tools/call", { name: "mouse_move", arguments: { x: targetX, y: targetY } });
      assert.ok(!mv.result.isError);
      const afterScreen = JSON.parse((await rpc(18, "tools/call", { name: "get_screen_info", arguments: {} })).result.content[0].text);
      assert.ok(Math.abs(afterScreen.cursor.x - targetX) <= 3 && Math.abs(afterScreen.cursor.y - targetY) <= 3);
      await rpc(19, "tools/call", { name: "mouse_move", arguments: { x: beforeCur.x, y: beforeCur.y } });
    } else {
      assert.equal(uiRes.result.isError, true);
      assert.match(uiRes.result.content[0].text, /Accessibility/i);
    }

    // Unknown tool returns isError=true cleanly
    const unknown = await rpc(20, "tools/call", { name: "nonexistent_tool", arguments: {} });
    assert.equal(unknown.result.isError, true);
  } finally {
    server.kill();
    fs.rmSync(tmpData, { recursive: true, force: true });
  }
});

test("win_worker.ps1 stays compatible with Windows PowerShell 5.1 and .NET Framework 4.8", () => {
  const ps = fs.readFileSync(path.join(ROOT, "scripts", "native", "win_worker.ps1"), "utf8");
  const psScriptBody = ps.split("\n'@\n").slice(1).join("\n");
  assert.ok(psScriptBody.length > 0, "Expected PowerShell body after C# here-string");
  assert.doesNotMatch(psScriptBody, /\?\?/, "Avoid PowerShell 7-only ?? null-coalescing operator in PS body");
  assert.doesNotMatch(ps, /Math\.Clamp/, "Avoid .NET Core-only Math.Clamp in C# Add-Type");
  assert.doesNotMatch(ps, /RuntimeInformation/, "Avoid .NET Core-only RuntimeInformation dependency");
});

if (process.platform === "darwin") {
  test("macos_jxa.js fallback executes get_screen_info and list_windows cleanly", async () => {
    const execFileAsync = promisify(execFile);
    const jxaPath = path.join(ROOT, "scripts", "native", "macos_jxa.js");
    const { stdout: screenOut } = await execFileAsync("/usr/bin/osascript", [
      "-l",
      "JavaScript",
      jxaPath,
      JSON.stringify({ action: "get_screen_info", params: {} }),
    ]);
    const screen = JSON.parse(screenOut);
    assert.ok(Array.isArray(screen.displays) && screen.displays.length >= 1);

    const { stdout: winOut } = await execFileAsync("/usr/bin/osascript", [
      "-l",
      "JavaScript",
      jxaPath,
      JSON.stringify({ action: "list_windows", params: {} }),
    ]);
    assert.ok(Array.isArray(JSON.parse(winOut)));
  });
}
