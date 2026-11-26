# Computer Use Plugin for Google Antigravity

A zero-dependency, cross-platform **Computer Use** plugin for **Google Antigravity** (App, IDE, and CLI) that gives agents full native desktop perception and control on both **macOS** and **Windows**.

## Capabilities

- **Screen Perception**: Multi-monitor `get_screen_info`, compressed multimodal `screenshot` (full screen, display, window, or region, with optional coordinate grid and cursor capture), and `check_permissions`.
- **Mouse Control**: `mouse_move`, `mouse_click` (left/right/middle, single/double/triple, modifiers), `mouse_down`, `mouse_up`, `mouse_drag`, and `mouse_scroll`.
- **Keyboard Control**: Full Unicode `type_text` (direct keystrokes or clipboard paste), `press_key`, `key_down`, `key_up`, and cross-platform `hotkey` (`"primary"` maps to `cmd` on macOS and `ctrl` on Windows).
- **Accessibility / Semantic UI**: Native `get_ui_tree`, `find_ui_elements`, and `click_ui_element` powered by macOS `AXUIElement` and Windows `UIAutomationClient`.
- **Window & App Lifecycle**: `list_windows`, `focus_window`, `manage_window` (move, resize, minimize, maximize, restore, close), `list_running_apps`, and `launch_app`.
- **Clipboard & Timing**: `clipboard_read`, `clipboard_write`, and `wait` (with optional post-wait screenshot).
- **Safety & Guardrails**: Always-on `rules/AGENTS.md`, `computer-operator` agent, and `PreToolUse` safety/audit hook (`hooks.json`) with emergency-stop support.

## Architecture

- **MCP Server (`scripts/mcp-server.mjs`)**: Pure Node.js ESM JSON-RPC 2.0 `stdio` server (zero `npm` dependencies).
- **macOS Driver (`scripts/drivers/macos.mjs`)**:
  - **Primary**: Native Swift helper (`scripts/native/macos_helper.swift`, auto-compiled and cached in `${PLUGIN_DATA}` when Xcode / CLT is present) using `CoreGraphics`, `AppKit`, `ApplicationServices` (`AXUIElement`), and `screencapture`/`sips`.
  - **Fallback**: Built-in JXA (`osascript -l JavaScript`) + `screencapture` + `sips` + `pbcopy`/`pbpaste` when `swiftc` is unavailable.
- **Windows Driver (`scripts/drivers/windows.mjs`)**:
  - Persistent `powershell.exe` + inline C# worker (`scripts/native/win_worker.ps1`) using `user32.dll`, `shcore.dll` (Per-Monitor DPI Aware v2), `System.Drawing`, `System.Windows.Forms`, and `UIAutomationClient`.

## Installation

### Requirements
- **Node.js 18+** on macOS or Windows
- **macOS 13+**: Grant **Screen Recording** and **Accessibility** permissions to your terminal / Antigravity app in *System Settings → Privacy & Security*
- **Windows 10 / 11**: Works out of the box (`powershell.exe` + .NET Framework built-in)

### Install with Antigravity CLI

```bash
agy plugin validate --strict .
agy plugin install .
```

## Emergency Stop & Audit Log

The bundled `PreToolUse` safety hook logs tool calls to `${PLUGIN_DATA}/audit.jsonl` (with `COMPUTER_USE_REDACT_LOGS=1` option to redact `type_text` / `clipboard_write` payloads).

To immediately halt all computer-use tool calls:
- Create an empty file named `EMERGENCY_STOP` inside the plugin's `${PLUGIN_DATA}` directory, **or**
- Set environment variable `COMPUTER_USE_DISABLED=1`.

## Documentation

- [Architecture & Diagrams](ARCHITECTURE.md)
- [Product Requirements Document](PRD.md)
- [Future Development & Roadmap](FUTURE_DEVELOPMENT.md)
- [Platform Shortcuts & Coordinate Guide](skills/computer-use/references/platform-guide.md)

## License

MIT
