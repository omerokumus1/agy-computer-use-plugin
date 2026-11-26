import {
  filterUiElements,
  normalizeHotkey,
  normalizeKeyName,
  normalizeModifiers,
  sleep,
} from "./common.mjs";
import { createMacosTransport } from "./macos.mjs";
import { createWindowsTransport } from "./windows.mjs";

export function createDriver(platform = process.platform) {
  let transport;
  if (platform === "darwin") {
    transport = createMacosTransport();
  } else if (platform === "win32") {
    transport = createWindowsTransport();
  } else {
    throw new Error(
      `Unsupported platform "${platform}". This plugin supports macOS (darwin) and Windows (win32).`
    );
  }

  const invoke = (action, params, timeoutMs) => transport.invoke(action, params, timeoutMs);

  return {
    platform,
    async getSystemInfo() {
      return invoke("get_system_info");
    },
    async checkPermissions() {
      return invoke("check_permissions");
    },
    async getScreenInfo() {
      return invoke("get_screen_info");
    },
    async screenshot(params = {}) {
      return invoke("screenshot", params, 30000);
    },
    async mouseMove({ x, y, duration_ms = 0 }) {
      return invoke("mouse_move", { x, y, duration_ms });
    },
    async mouseClick({ x, y, button = "left", click_count = 1, modifiers = [] }) {
      return invoke("mouse_click", {
        x,
        y,
        button,
        click_count,
        modifiers: normalizeModifiers(modifiers, platform),
      });
    },
    async mouseDown({ x, y, button = "left" }) {
      return invoke("mouse_down", { x, y, button });
    },
    async mouseUp({ x, y, button = "left" }) {
      return invoke("mouse_up", { x, y, button });
    },
    async mouseDrag({ start_x, start_y, end_x, end_y, button = "left", duration_ms = 250, steps = 15 }) {
      return invoke("mouse_drag", { start_x, start_y, end_x, end_y, button, duration_ms, steps });
    },
    async mouseScroll({ x, y, delta_x = 0, delta_y = 0 }) {
      return invoke("mouse_scroll", { x, y, delta_x, delta_y });
    },
    async typeText({ text, delay_ms = 0, via_clipboard = false }) {
      if (via_clipboard) {
        await invoke("clipboard_write", { text });
        await sleep(30);
        const pasteMod = platform === "darwin" ? ["cmd"] : ["ctrl"];
        return invoke("hotkey", { modifiers: pasteMod, key: "v" });
      }
      return invoke("type_text", { text, delay_ms }, Math.max(20000, text.length * (delay_ms + 15)));
    },
    async pressKey({ key, modifiers = [], repeat = 1 }) {
      return invoke("press_key", {
        key: normalizeKeyName(key),
        modifiers: normalizeModifiers(modifiers, platform),
        repeat,
      });
    },
    async hotkey({ keys }) {
      return invoke("hotkey", normalizeHotkey(keys, platform));
    },
    async keyDown({ key }) {
      return invoke("key_down", { key: normalizeKeyName(key) });
    },
    async keyUp({ key }) {
      return invoke("key_up", { key: normalizeKeyName(key) });
    },
    async getUiTree({ app_name, pid, max_depth = 5, max_nodes = 200, interactive_only = false } = {}) {
      return invoke("get_ui_tree", { app_name, pid, max_depth, max_nodes, interactive_only }, 25000);
    },
    async findUiElements({ query, role, app_name, pid, max_depth = 6, limit = 25 } = {}) {
      const tree = await invoke(
        "get_ui_tree",
        { app_name, pid, max_depth, max_nodes: 400, interactive_only: false },
        25000
      );
      const matches = filterUiElements(tree.elements || [], { query, role, limit });
      return {
        target: tree.target,
        total_scanned: (tree.elements || []).length,
        matches,
      };
    },
    async clickUiElement({ query, role, app_name, pid, button = "left", index = 0 } = {}) {
      const found = await this.findUiElements({ query, role, app_name, pid, max_depth: 6, limit: index + 10 });
      const el = found.matches[index];
      if (!el) {
        throw new Error(`No UI element matched query="${query || ""}" role="${role || ""}" at index=${index}`);
      }
      if (typeof el.cx !== "number" || typeof el.cy !== "number") {
        throw new Error(`Matched element "${el.title || el.role}" has no screen coordinates.`);
      }
      await this.mouseClick({ x: el.cx, y: el.cy, button, click_count: 1 });
      return { clicked: el };
    },
    async listWindows({ app_name, include_minimized = true } = {}) {
      return invoke("list_windows", { app_name, include_minimized });
    },
    async focusWindow({ window_id, app_name, title_contains, pid } = {}) {
      return invoke("focus_window", { window_id, app_name, title_contains, pid });
    },
    async manageWindow(params) {
      return invoke("manage_window", params);
    },
    async listRunningApps() {
      return invoke("list_running_apps");
    },
    async launchApp({ target, args = [], wait_ms = 500 }) {
      const res = await invoke("launch_app", { target, args });
      if (wait_ms > 0) await sleep(Math.min(wait_ms, 10000));
      return res;
    },
    async clipboardRead() {
      return invoke("clipboard_read");
    },
    async clipboardWrite({ text }) {
      return invoke("clipboard_write", { text });
    },
    async dispose() {
      if (transport.dispose) await transport.dispose();
    },
  };
}
