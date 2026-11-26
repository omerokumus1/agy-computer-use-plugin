#!/usr/bin/env node
import { createDriver } from "./drivers/index.mjs";
import { sleep } from "./drivers/common.mjs";

const PROTOCOL_VERSION = "2024-11-05";
const SERVER_INFO = {
  name: "computer-use-desktop",
  version: "0.1.0",
};

const TOOLS = [
  {
    name: "get_system_info",
    description: "Get host OS (darwin/win32), CPU arch, active driver mode, display count, cursor position, and frontmost window.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "check_permissions",
    description: "Check OS permissions required for computer use (Screen Recording & Accessibility on macOS; DPI awareness & elevation/UIPI on Windows).",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_screen_info",
    description: "List all connected displays with logical bounds (x, y, width, height), scale factor, cursor position, and frontmost window.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "screenshot",
    description: "Capture a screenshot of a display, region, or window. Returns an image plus capture_bounds and image_size for exact coordinate mapping.",
    inputSchema: {
      type: "object",
      properties: {
        display_id: { type: "integer", description: "Display index from get_screen_info (defaults to primary display)." },
        region: {
          type: "object",
          description: "Capture a specific logical screen rectangle.",
          properties: {
            x: { type: "number" },
            y: { type: "number" },
            width: { type: "number" },
            height: { type: "number" },
          },
          required: ["x", "y", "width", "height"],
        },
        window_id: { type: "integer", description: "Capture a specific window ID from list_windows." },
        app_name: { type: "string", description: "Capture the frontmost window of a matching application name." },
        include_cursor: { type: "boolean", default: true, description: "Include mouse cursor in the capture when supported." },
        grid: { type: "boolean", default: false, description: "Overlay a 200px logical coordinate grid to assist visual grounding." },
        max_width: { type: "integer", default: 1440, description: "Resize output image width to at most this many pixels (0 = full native width)." },
        format: { type: "string", enum: ["jpeg", "png"], default: "jpeg" },
        quality: { type: "integer", minimum: 10, maximum: 100, default: 82 },
        save_path: { type: "string", description: "Optional local file path to also write the captured image." },
      },
      additionalProperties: false,
    },
  },
  {
    name: "mouse_move",
    description: "Move the mouse cursor to logical screen coordinates (x, y).",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number" },
        y: { type: "number" },
        duration_ms: { type: "integer", default: 0, minimum: 0, maximum: 5000 },
      },
      required: ["x", "y"],
      additionalProperties: false,
    },
  },
  {
    name: "mouse_click",
    description: "Click at logical screen coordinates (x, y) or the current cursor position.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number" },
        y: { type: "number" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
        click_count: { type: "integer", minimum: 1, maximum: 3, default: 1 },
        modifiers: { type: "array", items: { type: "string" }, description: "Optional modifiers: primary, shift, ctrl, alt, cmd, win." },
      },
      additionalProperties: false,
    },
  },
  {
    name: "mouse_down",
    description: "Press and hold a mouse button at (x, y) or current cursor position.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number" },
        y: { type: "number" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "mouse_up",
    description: "Release a mouse button at (x, y) or current cursor position.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number" },
        y: { type: "number" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "mouse_drag",
    description: "Press, drag smoothly from (start_x, start_y) to (end_x, end_y), and release.",
    inputSchema: {
      type: "object",
      properties: {
        start_x: { type: "number" },
        start_y: { type: "number" },
        end_x: { type: "number" },
        end_y: { type: "number" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
        duration_ms: { type: "integer", default: 250, minimum: 20, maximum: 5000 },
        steps: { type: "integer", default: 15, minimum: 2, maximum: 100 },
      },
      required: ["start_x", "start_y", "end_x", "end_y"],
      additionalProperties: false,
    },
  },
  {
    name: "mouse_scroll",
    description: "Scroll vertically and/or horizontally at (x, y) or current cursor position. Positive delta_y scrolls up; negative scrolls down.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number" },
        y: { type: "number" },
        delta_x: { type: "integer", default: 0, description: "Horizontal wheel notches (positive = right, negative = left)." },
        delta_y: { type: "integer", default: -3, description: "Vertical wheel notches (positive = up, negative = down)." },
      },
      additionalProperties: false,
    },
  },
  {
    name: "type_text",
    description: "Type arbitrary Unicode text into the focused control. Set via_clipboard=true for fast multi-line paste.",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string" },
        delay_ms: { type: "integer", default: 0, minimum: 0, maximum: 200 },
        via_clipboard: { type: "boolean", default: false },
      },
      required: ["text"],
      additionalProperties: false,
    },
  },
  {
    name: "press_key",
    description: "Press and release a named key (e.g. enter, tab, escape, backspace, up, down, f1..f12, a..z) with optional modifiers.",
    inputSchema: {
      type: "object",
      properties: {
        key: { type: "string" },
        modifiers: { type: "array", items: { type: "string" } },
        repeat: { type: "integer", default: 1, minimum: 1, maximum: 50 },
      },
      required: ["key"],
      additionalProperties: false,
    },
  },
  {
    name: "hotkey",
    description: "Execute a keyboard shortcut chord (e.g. ['primary', 's'], ['alt', 'tab'], ['cmd', 'space']). 'primary' maps to cmd on macOS and ctrl on Windows.",
    inputSchema: {
      type: "object",
      properties: {
        keys: { type: "array", items: { type: "string" }, minItems: 1 },
      },
      required: ["keys"],
      additionalProperties: false,
    },
  },
  {
    name: "key_down",
    description: "Press and hold a key until key_up is called.",
    inputSchema: {
      type: "object",
      properties: { key: { type: "string" } },
      required: ["key"],
      additionalProperties: false,
    },
  },
  {
    name: "key_up",
    description: "Release a previously held key.",
    inputSchema: {
      type: "object",
      properties: { key: { type: "string" } },
      required: ["key"],
      additionalProperties: false,
    },
  },
  {
    name: "get_ui_tree",
    description: "Inspect the native accessibility / UI Automation tree of the frontmost or specified application, returning roles, titles, values, bounds, and center coordinates (cx, cy).",
    inputSchema: {
      type: "object",
      properties: {
        app_name: { type: "string" },
        pid: { type: "integer" },
        max_depth: { type: "integer", default: 5, minimum: 1, maximum: 12 },
        max_nodes: { type: "integer", default: 200, minimum: 10, maximum: 1000 },
        interactive_only: { type: "boolean", default: false },
      },
      additionalProperties: false,
    },
  },
  {
    name: "find_ui_elements",
    description: "Search the accessibility UI tree for elements matching a text query and/or role.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string", description: "Case-insensitive substring to match title, label, value, or identifier." },
        role: { type: "string", description: "Optional role filter (e.g. button, textfield, menuitem, link, tab)." },
        app_name: { type: "string" },
        pid: { type: "integer" },
        max_depth: { type: "integer", default: 6, minimum: 1, maximum: 12 },
        limit: { type: "integer", default: 25, minimum: 1, maximum: 100 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "click_ui_element",
    description: "Find a matching accessibility UI element and click its center coordinates.",
    inputSchema: {
      type: "object",
      properties: {
        query: { type: "string" },
        role: { type: "string" },
        app_name: { type: "string" },
        pid: { type: "integer" },
        button: { type: "string", enum: ["left", "right", "middle"], default: "left" },
        index: { type: "integer", default: 0, minimum: 0 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "list_windows",
    description: "List visible desktop windows with window_id, title, app_name, pid, focused/minimized state, and bounds.",
    inputSchema: {
      type: "object",
      properties: {
        app_name: { type: "string" },
        include_minimized: { type: "boolean", default: true },
      },
      additionalProperties: false,
    },
  },
  {
    name: "focus_window",
    description: "Bring an application window to the foreground (and unminimize if needed) by window_id, app_name, title_contains, or pid.",
    inputSchema: {
      type: "object",
      properties: {
        window_id: { type: "integer" },
        app_name: { type: "string" },
        title_contains: { type: "string" },
        pid: { type: "integer" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "manage_window",
    description: "Move, resize, set_bounds, minimize, maximize, restore, or close a window.",
    inputSchema: {
      type: "object",
      properties: {
        action: { type: "string", enum: ["move", "resize", "set_bounds", "minimize", "maximize", "restore", "close"] },
        window_id: { type: "integer" },
        app_name: { type: "string" },
        title_contains: { type: "string" },
        x: { type: "number" },
        y: { type: "number" },
        width: { type: "number" },
        height: { type: "number" },
      },
      required: ["action"],
      additionalProperties: false,
    },
  },
  {
    name: "list_running_apps",
    description: "List running GUI applications with PID, name, and bundle/window details.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "launch_app",
    description: "Launch an application by name, path, or bundle ID, or open a URL/file using the OS default handler.",
    inputSchema: {
      type: "object",
      properties: {
        target: { type: "string", description: "App name (e.g. 'Calculator', 'Safari', 'notepad'), file path, or URL." },
        args: { type: "array", items: { type: "string" }, default: [] },
        wait_ms: { type: "integer", default: 500, minimum: 0, maximum: 10000 },
      },
      required: ["target"],
      additionalProperties: false,
    },
  },
  {
    name: "clipboard_read",
    description: "Read current plain-text content from the system clipboard.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "clipboard_write",
    description: "Write plain text to the system clipboard.",
    inputSchema: {
      type: "object",
      properties: { text: { type: "string" } },
      required: ["text"],
      additionalProperties: false,
    },
  },
  {
    name: "wait",
    description: "Wait for a specified number of milliseconds (up to 30000), optionally capturing a screenshot afterward.",
    inputSchema: {
      type: "object",
      properties: {
        ms: { type: "integer", default: 500, minimum: 0, maximum: 30000 },
        capture_screenshot: { type: "boolean", default: false },
      },
      additionalProperties: false,
    },
  },
];

let driver;
function getDriver() {
  if (!driver) driver = createDriver();
  return driver;
}

function sendResponse(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function sendError(id, code, message, data) {
  process.stdout.write(
    JSON.stringify({
      jsonrpc: "2.0",
      id,
      error: { code, message, ...(data !== undefined ? { data } : {}) },
    }) + "\n"
  );
}

async function handleToolCall(name, args = {}) {
  const drv = getDriver();
  switch (name) {
    case "get_system_info":
      return { content: [{ type: "text", text: JSON.stringify(await drv.getSystemInfo(), null, 2) }] };
    case "check_permissions":
      return { content: [{ type: "text", text: JSON.stringify(await drv.checkPermissions(), null, 2) }] };
    case "get_screen_info":
      return { content: [{ type: "text", text: JSON.stringify(await drv.getScreenInfo(), null, 2) }] };
    case "screenshot": {
      const shot = await drv.screenshot(args);
      const { base64, mime_type, ...meta } = shot;
      return {
        content: [
          { type: "image", data: base64, mimeType: mime_type },
          { type: "text", text: JSON.stringify(meta, null, 2) },
        ],
      };
    }
    case "mouse_move":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseMove(args)) }] };
    case "mouse_click":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseClick(args)) }] };
    case "mouse_down":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseDown(args)) }] };
    case "mouse_up":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseUp(args)) }] };
    case "mouse_drag":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseDrag(args)) }] };
    case "mouse_scroll":
      return { content: [{ type: "text", text: JSON.stringify(await drv.mouseScroll(args)) }] };
    case "type_text":
      return { content: [{ type: "text", text: JSON.stringify(await drv.typeText(args)) }] };
    case "press_key":
      return { content: [{ type: "text", text: JSON.stringify(await drv.pressKey(args)) }] };
    case "hotkey":
      return { content: [{ type: "text", text: JSON.stringify(await drv.hotkey(args)) }] };
    case "key_down":
      return { content: [{ type: "text", text: JSON.stringify(await drv.keyDown(args)) }] };
    case "key_up":
      return { content: [{ type: "text", text: JSON.stringify(await drv.keyUp(args)) }] };
    case "get_ui_tree":
      return { content: [{ type: "text", text: JSON.stringify(await drv.getUiTree(args), null, 2) }] };
    case "find_ui_elements":
      return { content: [{ type: "text", text: JSON.stringify(await drv.findUiElements(args), null, 2) }] };
    case "click_ui_element":
      return { content: [{ type: "text", text: JSON.stringify(await drv.clickUiElement(args), null, 2) }] };
    case "list_windows":
      return { content: [{ type: "text", text: JSON.stringify(await drv.listWindows(args), null, 2) }] };
    case "focus_window":
      return { content: [{ type: "text", text: JSON.stringify(await drv.focusWindow(args), null, 2) }] };
    case "manage_window":
      return { content: [{ type: "text", text: JSON.stringify(await drv.manageWindow(args), null, 2) }] };
    case "list_running_apps":
      return { content: [{ type: "text", text: JSON.stringify(await drv.listRunningApps(), null, 2) }] };
    case "launch_app":
      return { content: [{ type: "text", text: JSON.stringify(await drv.launchApp(args), null, 2) }] };
    case "clipboard_read":
      return { content: [{ type: "text", text: JSON.stringify(await drv.clipboardRead(), null, 2) }] };
    case "clipboard_write":
      return { content: [{ type: "text", text: JSON.stringify(await drv.clipboardWrite(args), null, 2) }] };
    case "wait": {
      const ms = Math.min(Math.max(0, Number(args.ms ?? 500)), 30000);
      await sleep(ms);
      if (args.capture_screenshot) {
        const shot = await drv.screenshot({});
        const { base64, mime_type, ...meta } = shot;
        return {
          content: [
            { type: "image", data: base64, mimeType: mime_type },
            { type: "text", text: JSON.stringify({ waited_ms: ms, ...meta }, null, 2) },
          ],
        };
      }
      return { content: [{ type: "text", text: JSON.stringify({ waited_ms: ms }) }] };
    }
    default:
      throw new Error(`Unknown tool: ${name}`);
  }
}

async function handleMessage(msg) {
  const { id, method, params } = msg;
  if (!method) return;

  if (id === undefined || id === null) {
    // Notification
    return;
  }

  try {
    if (method === "initialize") {
      sendResponse(id, {
        protocolVersion: PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: SERVER_INFO,
      });
      return;
    }
    if (method === "ping") {
      sendResponse(id, {});
      return;
    }
    if (method === "tools/list") {
      sendResponse(id, { tools: TOOLS });
      return;
    }
    if (method === "tools/call") {
      try {
        const result = await handleToolCall(params?.name, params?.arguments || {});
        sendResponse(id, result);
      } catch (err) {
        sendResponse(id, {
          isError: true,
          content: [{ type: "text", text: `Error executing ${params?.name}: ${err.message}` }],
        });
      }
      return;
    }
    sendError(id, -32601, `Method not found: ${method}`);
  } catch (err) {
    sendError(id, -32603, err.message);
  }
}

let stdinBuffer = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  stdinBuffer += chunk;
  let nlIdx;
  while ((nlIdx = stdinBuffer.indexOf("\n")) !== -1) {
    const line = stdinBuffer.slice(0, nlIdx).trim();
    stdinBuffer = stdinBuffer.slice(nlIdx + 1);
    if (!line) continue;
    try {
      const msg = JSON.parse(line);
      void handleMessage(msg);
    } catch (err) {
      process.stderr.write(`[mcp-server] Invalid JSON line: ${err.message}\n`);
    }
  }
});

async function shutdown() {
  if (driver?.dispose) {
    await driver.dispose();
  }
  process.exit(0);
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
process.stdin.on("end", shutdown);
