import { execFile, spawn } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";
import { resolveDataDir, resolvePluginRoot, sleep } from "./common.mjs";

const execFileAsync = promisify(execFile);

export function createMacosTransport() {
  const pluginRoot = resolvePluginRoot();
  const dataDir = resolveDataDir();
  const swiftSrc = path.join(pluginRoot, "scripts", "native", "macos_helper.swift");
  const jxaScript = path.join(pluginRoot, "scripts", "native", "macos_jxa.js");

  let swiftCheckDone = false;
  let swiftBinary = null;
  let proc = null;
  let buffer = "";
  let nextId = 1;
  const pending = new Map();

  async function ensureSwiftHelper() {
    if (swiftCheckDone) return swiftBinary;
    swiftCheckDone = true;

    try {
      await execFileAsync("/usr/bin/xcode-select", ["-p"], { timeout: 3000 });
    } catch {
      return null;
    }

    const srcHash = crypto
      .createHash("sha256")
      .update(fs.readFileSync(swiftSrc))
      .digest("hex")
      .slice(0, 12);

    const binDir = path.join(dataDir, "bin");
    const targetBin = path.join(binDir, `macos-helper-${srcHash}`);

    if (!fs.existsSync(targetBin)) {
      fs.mkdirSync(binDir, { recursive: true });
      await execFileAsync("/usr/bin/swiftc", ["-O", swiftSrc, "-o", targetBin], { timeout: 60000 });
    }
    swiftBinary = targetBin;
    return swiftBinary;
  }

  function rejectAll(err) {
    for (const entry of pending.values()) {
      clearTimeout(entry.timer);
      entry.reject(err);
    }
    pending.clear();
  }

  async function ensureSwiftWorker() {
    const bin = await ensureSwiftHelper();
    if (!bin) return null;

    if (proc && !proc.killed && proc.exitCode === null) {
      return proc;
    }

    proc = spawn(bin, [], { stdio: ["pipe", "pipe", "pipe"] });
    buffer = "";

    proc.stdout.setEncoding("utf8");
    proc.stdout.on("data", (chunk) => {
      buffer += chunk;
      let idx;
      while ((idx = buffer.indexOf("\n")) !== -1) {
        const line = buffer.slice(0, idx).trim();
        buffer = buffer.slice(idx + 1);
        if (!line) continue;
        let msg;
        try {
          msg = JSON.parse(line);
        } catch {
          continue;
        }
        const entry = pending.get(msg.id);
        if (!entry) continue;
        pending.delete(msg.id);
        clearTimeout(entry.timer);
        if (msg.ok) entry.resolve(msg.result);
        else entry.reject(new Error(msg.error || "macOS Swift helper failed."));
      }
    });

    proc.stderr.setEncoding("utf8");
    proc.stderr.on("data", (chunk) => {
      if (chunk.trim()) process.stderr.write(`[macos_helper] ${chunk}`);
    });

    proc.on("exit", (code, signal) => {
      proc = null;
      rejectAll(new Error(`macOS helper exited (code=${code}, signal=${signal})`));
    });

    proc.on("error", (err) => {
      proc = null;
      rejectAll(err);
    });

    return proc;
  }

  async function runJxa(action, params = {}) {
    const { stdout } = await execFileAsync(
      "/usr/bin/osascript",
      ["-l", "JavaScript", jxaScript, JSON.stringify({ action, params })],
      { timeout: 15000 }
    );
    return JSON.parse(stdout.trim());
  }

  async function fallbackScreenshot(p = {}) {
    const info = await runJxa("get_screen_info", {});
    const displays = info.displays || [];
    let bounds = displays[0] || { x: 0, y: 0, width: 1280, height: 800 };
    if (p.region) {
      bounds = p.region;
    } else if (typeof p.display_id === "number" && displays[p.display_id]) {
      bounds = displays[p.display_id];
    }

    const tmpPng = path.join(os.tmpdir(), `cu_fb_${Date.now()}.png`);
    const fmt = (p.format || "jpeg").toLowerCase() === "png" ? "png" : "jpeg";
    const tmpOut = path.join(os.tmpdir(), `cu_fb_out_${Date.now()}.${fmt === "png" ? "png" : "jpg"}`);

    try {
      const scArgs = ["-x"];
      if (p.include_cursor !== false) scArgs.push("-C");
      if (p.window_id) {
        scArgs.push("-l", String(p.window_id), "-o", tmpPng);
      } else {
        scArgs.push("-R", `${Math.round(bounds.x)},${Math.round(bounds.y)},${Math.round(bounds.width)},${Math.round(bounds.height)}`, tmpPng);
      }
      await execFileAsync("/usr/sbin/screencapture", scArgs);

      const maxW = p.max_width ?? 1440;
      const sipsArgs = ["-s", "format", fmt === "png" ? "png" : "jpeg"];
      if (maxW > 0) sipsArgs.push("--resampleWidth", String(maxW));
      sipsArgs.push(tmpPng, "--out", tmpOut);
      await execFileAsync("/usr/bin/sips", sipsArgs);

      const buf = fs.readFileSync(tmpOut);
      if (p.save_path) fs.writeFileSync(p.save_path, buf);

      const { stdout: dimOut } = await execFileAsync("/usr/bin/sips", ["-g", "pixelWidth", "-g", "pixelHeight", tmpOut]);
      const wMatch = dimOut.match(/pixelWidth:\s*(\d+)/);
      const hMatch = dimOut.match(/pixelHeight:\s*(\d+)/);

      return {
        base64: buf.toString("base64"),
        mime_type: fmt === "png" ? "image/png" : "image/jpeg",
        capture_bounds: {
          x: Math.round(bounds.x),
          y: Math.round(bounds.y),
          width: Math.round(bounds.width),
          height: Math.round(bounds.height),
        },
        image_size: {
          width: wMatch ? Number(wMatch[1]) : Math.round(bounds.width),
          height: hMatch ? Number(hMatch[1]) : Math.round(bounds.height),
        },
      };
    } finally {
      for (const f of [tmpPng, tmpOut]) {
        if (fs.existsSync(f)) fs.unlinkSync(f);
      }
    }
  }

  async function invokeFallback(action, params = {}) {
    if (action === "screenshot") return fallbackScreenshot(params);
    if (action === "clipboard_read") {
      const { stdout } = await execFileAsync("/usr/bin/pbpaste", []);
      return { has_text: stdout.length > 0, text: stdout };
    }
    if (action === "clipboard_write") {
      await new Promise((resolve, reject) => {
        const p = spawn("/usr/bin/pbcopy", []);
        p.on("error", reject);
        p.on("close", (c) => (c === 0 ? resolve() : reject(new Error("pbcopy failed"))));
        p.stdin.end(String(params.text || ""));
      });
      return { ok: true, length: String(params.text || "").length };
    }
    if (action === "launch_app") {
      const target = String(params.target || "");
      const args = target.startsWith("http") || fs.existsSync(target) ? [target] : ["-a", target];
      await execFileAsync("/usr/bin/open", args);
      return { launched: true, target };
    }
    if (action === "type_text") {
      await invokeFallback("clipboard_write", { text: params.text });
      await sleep(30);
      return runJxa("hotkey", { modifiers: ["cmd"], key: "v" });
    }
    if (action === "get_ui_tree") {
      throw new Error("Accessibility tree inspection requires Xcode Command Line Tools (`xcode-select --install`) for the Swift helper on macOS.");
    }
    return runJxa(action, params);
  }

  return {
    async invoke(action, params = {}, timeoutMs = 20000) {
      const child = await ensureSwiftWorker();
      if (!child) return invokeFallback(action, params);

      const id = nextId++;
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          pending.delete(id);
          reject(new Error(`macOS helper timed out on "${action}" after ${timeoutMs}ms`));
        }, timeoutMs);
        pending.set(id, { resolve, reject, timer });
        child.stdin.write(JSON.stringify({ id, action, params }) + "\n");
      });
    },
    async dispose() {
      if (proc && !proc.killed) {
        proc.kill();
        proc = null;
      }
    },
  };
}
