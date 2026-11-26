# Product Requirements Document (PRD): Computer Use Plugin for Antigravity

- **Product Name**: `computer-use` (Display Name: **Computer Use**)
- **Version**: 0.1.0
- **Author / Maintainer**: omerokumus1
- **Platforms**: macOS (13+ Ventura / Sonoma / Sequoia, Apple Silicon & Intel) and Windows (10 / 11, x64 & ARM64)
- **Target Host**: Google Antigravity (Antigravity App, Antigravity IDE, Antigravity CLI)

---

## 1. Executive Summary

The **Computer Use** plugin equips Google Antigravity agents with full, native, cross-platform desktop perception and control across **macOS** and **Windows**. While Antigravity excels at terminal commands, file editing, and web browser automation, many real-world workflows span native desktop applications (IDEs, Finder/Explorer, Figma, Excel, Slack, Outlook, System Settings, DAWs, CAD tools, and multi-app workflows).

This plugin bridges that gap via a **zero-dependency Node.js Model Context Protocol (MCP) server** paired with **native OS automation backends** (Swift + CoreGraphics/AXUIElement with JXA fallback on macOS; persistent PowerShell + Win32/GDI+/UIAutomation worker on Windows), plus Antigravity-native **Skills**, **Rules**, **Custom Agent**, and **Safety Hooks**.

---

## 2. Problem Statement

1. **Desktop Blindness**: Agents currently lack a unified way to see non-browser native desktop windows, dialogs, menus, and system trays.
2. **Cross-Platform Fragmentation**: Existing automation tools often require fragile native C++ npm builds (`node-gyp`), Python virtual environments, or macOS-only / Windows-only tooling that break across OS updates and CPU architectures.
3. **Pixel-Only Fragility**: Pure vision-only clicking wastes tokens and struggles with dense UIs, small icons, and Retina/HiDPI scaling mismatches.
4. **Safety & Control Risks**: Unrestricted OS input without guardrails, permission checks, emergency stop controls, or audit logging poses operational hazards.

---

## 3. Goals & Non-Goals

### 3.1 Goals
- **Full Desktop Autonomy**: Provide complete mouse, keyboard, clipboard, window, application, accessibility tree, and screen capture capabilities.
- **Zero-Install Friction**: Run directly via `node` using OS-native frameworks (`CoreGraphics`, `AppKit`, `ApplicationServices`, `screencapture` on macOS; `.NET`, `user32.dll`, `shcore.dll`, `System.Drawing`, `UIAutomationClient` on Windows) with zero external npm or pip dependencies.
- **Dual Grounding (Vision + Semantic UI)**: Combine compressed, grid-optional multimodal screenshots with structured Accessibility / UI Automation trees (`get_ui_tree`, `find_ui_elements`, `click_ui_element`) for both accuracy and token efficiency.
- **Coordinate Determinism**: Normalize all multi-monitor and HiDPI/Retina coordinates into consistent logical screen coordinates (top-left origin on primary display) so coordinates read from screenshots or UI trees map 1:1 to pointer actions.
- **Cross-Platform Ergonomics**: Abstract OS-specific modifier keys (e.g., `"primary"` resolves to `Command` on macOS and `Control` on Windows) and provide cross-platform app/window management.
- **Safety by Design**: Ship always-on behavioral rules, a `PreToolUse` safety/audit hook with an emergency-stop mechanism, and clear OS permission diagnostics.

### 3.2 Non-Goals (v0.1)
- Linux X11/Wayland support (deferred to `FUTURE_DEVELOPMENT.md`).
- Continuous 30/60 FPS video streaming over WebRTC/ScreenCaptureKit (v0.1 uses on-demand low-latency screenshots).
- Bypassing OS security boundaries (SIP, Gatekeeper, UAC prompts, macOS TCC permissions, or CAPTCHAs).

---

## 4. Target Users & Use Cases

| Persona | Primary Use Cases |
| --- | --- |
| **Software Engineers & QA** | End-to-end testing of native macOS/Windows desktop apps (Electron, SwiftUI, WPF, WinUI), inspecting UI layouts across resolutions. |
| **Power Users & Knowledge Workers** | Automating multi-app workflows across Excel, Outlook, Finder/Explorer, Notion, Slack, and native utilities. |
| **AI Agent Builders** | Running autonomous `computer-operator` subagents for desktop research, data entry, and GUI verification loops. |

---

## 5. System Architecture

```text
Antigravity Agent / Subagent (computer-operator)
        │
        ├── Rules (rules/AGENTS.md)          ── Always-on safety & observe-act-verify loop
        ├── Skills (computer-use, ui-auto)   ── Progressive-disclosure workflows & shortcuts
        ├── Hooks (hooks.json)               ── PreToolUse safety gate & JSONL audit log
        └── MCP Client
                │  stdio (JSON-RPC 2.0)
                ▼
     scripts/mcp-server.mjs (Zero-dep Node.js ESM)
                │
        ┌───────┴───────────────────────┐
        ▼ (darwin)                      ▼ (win32)
scripts/drivers/macos.mjs       scripts/drivers/windows.mjs
  ├── Primary: compiled Swift     └── Persistent PowerShell + C# worker
  │   helper (macos_helper.swift      (win_worker.ps1 via stdin/stdout JSON)
  │   cached in PLUGIN_DATA)          ├── user32.dll (SendInput, EnumWindows)
  └── Fallback: JXA osascript         ├── shcore.dll (Per-Monitor DPI v2)
      + screencapture + sips          ├── System.Drawing (CopyFromScreen)
                                      └── UIAutomationClient (UIA tree)
```

### 5.1 Coordinate System Contract
- **Origin**: `(0, 0)` is the **top-left corner of the primary display** on both macOS and Windows.
- **Units**: **Logical screen points/DIPs** (matching macOS `CoreGraphics` points and Windows DPI-aware logical coordinates when normalized, or physical pixels clearly reported in `get_screen_info` and `screenshot` metadata).
  - Specifically, on macOS, `CGEvent` and `CGWindowBounds` operate in **logical points** regardless of 2x Retina backing scale; screenshots downscaled to `max_width` report `capture_bounds` (`x, y, width, height` in logical space) and `image_size` (`width, height` in pixels) so the agent never miscalculates scaling.
  - On Windows, the worker sets `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2` so `GetSystemMetrics` / `Screen.AllScreens` / `GetWindowRect` / `SendInput` / `CopyFromScreen` all align cleanly in virtual desktop pixel coordinates without OS virtualization blur or offset drift.

---

## 6. Functional Requirements (MCP Tool Suite)

### 6.1 Screen Perception & Diagnostics
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `get_system_info` | OS, arch, driver mode, hostname, user, cursor, displays summary | — |
| `check_permissions` | Verify Screen Recording & Accessibility (macOS) or DPI/elevation (Windows) | — |
| `get_screen_info` | Enumerate all monitors (bounds, scale, work area, primary), cursor pos, frontmost window | — |
| `screenshot` | Capture screen/display/region/window as MCP `image` + coordinate metadata | `display_id`, `region`, `window_id`, `app_name`, `include_cursor`, `grid`, `max_width`, `format`, `quality`, `save_path` |

### 6.2 Mouse Input
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `mouse_move` | Move pointer to absolute coordinates | `x`, `y`, `duration_ms` |
| `mouse_click` | Click (single/double/triple, left/right/middle) with optional modifiers | `x`, `y`, `button`, `click_count`, `modifiers` |
| `mouse_down` | Press and hold mouse button | `x`, `y`, `button` |
| `mouse_up` | Release mouse button | `x`, `y`, `button` |
| `mouse_drag` | Smooth drag from start to end coordinates | `start_x`, `start_y`, `end_x`, `end_y`, `button`, `duration_ms`, `steps` |
| `mouse_scroll` | Vertical and horizontal scrolling at coordinates | `x`, `y`, `delta_x`, `delta_y` |

### 6.3 Keyboard Input
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `type_text` | Type Unicode text directly or via clipboard paste | `text`, `delay_ms`, `via_clipboard` |
| `press_key` | Press/tap a named key with optional modifiers | `key`, `modifiers`, `repeat` |
| `hotkey` | Execute key chord with cross-platform `"primary"` modifier support | `keys` |
| `key_down` / `key_up` | Hold or release a specific key | `key` |

### 6.4 Accessibility / Semantic UI Tree
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `get_ui_tree` | Dump structured UI element hierarchy with roles, names, values, bounds | `app_name`, `pid`, `max_depth`, `max_nodes`, `interactive_only` |
| `find_ui_elements` | Query UI elements by text/title, role, or identifier | `query`, `role`, `app_name`, `pid`, `limit` |
| `click_ui_element` | Locate and activate (invoke or center-click) a UI element | `query`, `role`, `app_name`, `pid`, `button`, `index` |

### 6.5 Window & Application Lifecycle
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `list_windows` | List visible on-screen windows with IDs, titles, owners, PIDs, bounds | `app_name`, `include_minimized` |
| `focus_window` | Bring window/app to front and restore if minimized | `window_id`, `app_name`, `title_contains`, `pid` |
| `manage_window` | Move, resize, minimize, maximize, restore, or close window | `action`, `window_id`, `app_name`, `title_contains`, `x`, `y`, `width`, `height` |
| `list_running_apps` | Enumerate running GUI applications | — |
| `launch_app` | Launch app by name/path/bundle ID or open file/URL with OS handler | `target`, `args`, `wait_ms` |

### 6.6 Clipboard & Timing
| Tool | Purpose | Key Parameters |
| --- | --- | --- |
| `clipboard_read` | Read current clipboard text and type summary | — |
| `clipboard_write` | Write text to system clipboard | `text` |
| `wait` | Sleep for duration (capped) with optional post-wait screenshot | `ms`, `capture_screenshot` |

---

## 7. Non-Functional Requirements

1. **Latency**:
   - Input events (`mouse_click`, `press_key`, `hotkey`): < 100 ms per call once driver is warm.
   - Screenshots (full display, resized to 1280px JPEG/PNG): < 500 ms.
   - UI tree queries (`max_depth=4`): < 400 ms.
2. **Reliability**:
   - Persistent workers automatically respawn on crash or timeout.
   - Graceful degradation on macOS if Xcode CLT (`swiftc`) is absent (automatic JXA fallback).
3. **Token Efficiency**:
   - Screenshots default to `max_width: 1440` and `format: "jpeg"` (quality 82) or `"png"` with coordinate metadata so vision tokens stay bounded while text stays sharp.
   - Core tools marked `eager: true` in `mcp_config.json`; specialized tools lazy-loaded.
4. **Security & Safety**:
   - `PreToolUse` hook logs every computer-use invocation to `${PLUGIN_DATA}/audit.jsonl` (redacting typed text if `COMPUTER_USE_REDACT_LOGS=1` or when password-like fields are active) and enforces an emergency stop flag (`COMPUTER_USE_DISABLED=1` or `${PLUGIN_DATA}/EMERGENCY_STOP` lockfile).
   - Always-on `rules/AGENTS.md` prohibits entering user passwords/2FA codes, solving CAPTCHAs, bypassing payment walls, or performing irreversible destructive GUI actions without explicit user confirmation.
   - No elevated privilege escalation or sandbox bypass.

---

## 8. Acceptance Criteria (v0.1.0)

- [ ] `agy plugin validate --strict .` passes with **0 errors and 0 warnings**.
- [ ] MCP server responds cleanly to `initialize`, `tools/list`, and `tools/call` over stdio JSON-RPC 2.0.
- [ ] All 24 MCP tools have valid JSON Schemas, cross-platform dispatch, and clear error messages.
- [ ] On macOS: real verification of `get_system_info`, `check_permissions`, `get_screen_info`, `screenshot`, `list_windows`, `list_running_apps`, `clipboard_read`/`clipboard_write`, `get_ui_tree`, and input drivers.
- [ ] On Windows: static/syntax validation of `win_worker.ps1` + unit tests for Windows driver JSON protocol & coordinate/key mapping.
- [ ] Repository initialized with Git, `.gitignore`, `README.md`, `PRD.md`, and `FUTURE_DEVELOPMENT.md`.
