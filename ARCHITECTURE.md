# Architecture — Computer Use Plugin for Google Antigravity

This document describes the architecture, runtime components, data flows, coordinate math, and cross-platform driver design of the **Computer Use** plugin (`computer-use` v1.0.0).

---

## 1. High-Level System Architecture

The plugin combines Antigravity's native customization primitives (**Skills**, **Rules**, **Custom Agent**, **Lifecycle Hooks**, and **MCP Server**) with a **zero-dependency Node.js MCP server** that delegates OS operations to persistent native workers on **macOS** and **Windows**.

```mermaid
flowchart TB
    User["User Prompt / Task"] --> Host["Google Antigravity (App / IDE / CLI)"]

    subgraph Bundle["Antigravity Plugin Bundle (computer-use)"]
        Manifest["plugin.json"]
        Rules["rules/AGENTS.md (Always-on Safety & Loop)"]
        Skills["skills/computer-use & skills/ui-automation"]
        Agent["agents/computer-operator.md"]
        Hooks["hooks.json -> scripts/safety-hook.mjs"]
        McpCfg["mcp_config.json -> desktop MCP server"]
    end

    Host --> Rules
    Host --> Skills
    Host --> Agent
    Host -->|"PreToolUse (stdin JSON)"| Hooks
    Hooks -->|"allow / deny + audit.jsonl"| Host
    Host -->|"stdio JSON-RPC 2.0"| McpServer["scripts/mcp-server.mjs (26 tools)"]

    McpServer --> Driver["scripts/drivers/index.mjs + common.mjs"]

    Driver -->|"process.platform === 'darwin'"| MacTransport["scripts/drivers/macos.mjs"]
    Driver -->|"process.platform === 'win32'"| WinTransport["scripts/drivers/windows.mjs"]

    subgraph macOS["macOS Backend"]
        SwiftCheck{"xcode-select -p?"}
        SwiftWorker["Persistent Swift Worker\n(scripts/native/macos_helper.swift)\nCoreGraphics + AXUIElement + AppKit + screencapture"]
        JxaFallback["Fallback Driver\n(scripts/native/macos_jxa.js + screencapture + sips + pbcopy/pbpaste)"]
        SwiftCheck -->|"Yes (compiled & cached in PLUGIN_DATA/bin)"| SwiftWorker
        SwiftCheck -->|"No"| JxaFallback
    end

    subgraph Windows["Windows Backend"]
        PsWorker["Persistent STA PowerShell Worker\n(scripts/native/win_worker.ps1)\nInline C# Add-Type: user32.dll + shcore.dll + GDI+ + UIAutomationClient"]
    end

    MacTransport --> SwiftCheck
    WinTransport --> PsWorker
```

---

## 2. Repository & Bundle Layout

```text
agy-computer-use-plugin/
├── plugin.json                              # Plugin manifest & Marketplace metadata
├── mcp_config.json                          # Registers 'desktop' stdio MCP server + eager tool list
├── hooks.json                               # Registers PreToolUse safety & audit hook
├── rules/
│   └── AGENTS.md                            # Always-on Observe-Ground-Act-Verify & safety guardrails
├── agents/
│   └── computer-operator.md                 # Dedicated desktop operator main/subagent
├── skills/
│   ├── computer-use/
│   │   ├── SKILL.md                         # Cross-platform desktop automation runbook
│   │   └── references/
│   │       └── platform-guide.md            # Modifier mappings, key names, DPI & TCC guide
│   └── ui-automation/
│       └── SKILL.md                         # Accessibility-first UI tree grounding guide
├── scripts/
│   ├── mcp-server.mjs                       # Zero-dep JSON-RPC 2.0 MCP server (26 tools)
│   ├── safety-hook.mjs                      # PreToolUse EMERGENCY_STOP gate + audit.jsonl logger
│   ├── drivers/
│   │   ├── common.mjs                       # Key/modifier normalization, UI filter, path helpers
│   │   ├── index.mjs                        # Unified 26-method driver facade over OS transports
│   │   ├── macos.mjs                        # macOS transport (Swift worker + JXA fallback)
│   │   └── windows.mjs                      # Windows transport (persistent STA PowerShell worker)
│   └── native/
│       ├── macos_helper.swift               # Native Swift worker (CoreGraphics, AXUIElement, AppKit)
│       ├── macos_jxa.js                     # Zero-Xcode JXA fallback script
│       └── win_worker.ps1                   # Persistent PS 5.1+ / C# .NET 4.8 Win32 + UIA worker
├── tests/
│   └── plugin.test.mjs                      # Unit, hook, static Windows PS5.1, & live MCP tests
├── assets/
│   └── logo.svg                             # 128x128 light/dark-compatible SVG icon
├── PRD.md                                   # Product Requirements Document
├── FUTURE_DEVELOPMENT.md                    # Roadmap: Token efficiency, agy-context-plugin, guardrails, perf
└── ARCHITECTURE.md                          # This file
```

---

## 3. End-to-End Execution & Safety Flow

Every desktop tool call flows through the `PreToolUse` safety hook before reaching `scripts/mcp-server.mjs` and the persistent OS worker.

```mermaid
sequenceDiagram
    autonumber
    participant Agent as Antigravity Agent / computer-operator
    participant Hook as safety-hook.mjs (PreToolUse)
    participant MCP as scripts/mcp-server.mjs
    participant Driver as drivers/index.mjs + OS Transport
    participant Worker as Persistent Native Worker (Swift / PowerShell)
    participant OS as macOS / Windows Desktop

    Agent->>Hook: Tool call JSON (stdin)
    Hook->>Hook: Check COMPUTER_USE_DISABLED=1 or PLUGIN_DATA/EMERGENCY_STOP
    alt Emergency Stop Active
        Hook-->>Agent: {"decision": "deny", "reason": "..."}
    else Allowed
        Hook->>Hook: Append sanitized JSONL record to PLUGIN_DATA/audit.jsonl
        Hook-->>Agent: {"decision": "allow"}
        Agent->>MCP: JSON-RPC tools/call (stdio)
        MCP->>Driver: Dispatch normalized action & args
        Driver->>Worker: Write newline-delimited JSON {id, action, params}
        Worker->>OS: Execute CoreGraphics/AXUIElement or Win32/UIA call
        OS-->>Worker: Native result / image buffer / bounds
        Worker-->>Driver: JSON line {id, ok: true, result}
        Driver-->>MCP: Structured result
        MCP-->>Agent: MCP TextContent (+ ImageContent for screenshots)
    end
```

---

## 4. Cross-Platform Driver Selection & Lifecycle

`scripts/drivers/index.mjs` exposes one unified 26-method API (`getSystemInfo`, `screenshot`, `mouseClick`, `hotkey`, `getUiTree`, etc.) backed by thin OS transports.

```mermaid
flowchart LR
    Start(["MCP Server Starts"]) --> CheckOS{"process.platform"}

    CheckOS -->|"darwin"| MacInit["createMacosTransport()"]
    MacInit --> XcodeCheck{"xcode-select -p\nsucceeds?"}
    XcodeCheck -->|"Yes"| HashCheck{"Cached binary exists?\nPLUGIN_DATA/bin/macos-helper-<sha256>"}
    HashCheck -->|"No"| Compile["swiftc -O macos_helper.swift"]
    Compile --> SpawnSwift["Spawn persistent macos-helper\n(stdin/stdout JSON lines)"]
    HashCheck -->|"Yes"| SpawnSwift
    XcodeCheck -->|"No"| JxaMode["On-demand JXA fallback\nosascript -l JavaScript + screencapture + sips"]

    CheckOS -->|"win32"| WinInit["createWindowsTransport()"]
    WinInit --> SpawnPS["Spawn persistent powershell.exe -Sta\nwin_worker.ps1"]
    SpawnPS --> CompileCS["Compile inline C# once (Add-Type)\nInit Per-Monitor DPI Aware v2"]
    CompileCS --> LoopPS["Serve stdin/stdout JSON-line loop"]

    SpawnSwift -.->|"Auto-respawn on exit/crash"| MacInit
    LoopPS -.->|"Auto-respawn on exit/crash"| WinInit
```

### Key Design Choices
- **Zero `npm` dependencies**: Implementing JSON-RPC 2.0 directly in [scripts/mcp-server.mjs](file:///Users/omerokumus/Documents/Projects/agy-computer-use-plugin/scripts/mcp-server.mjs) eliminates `node_modules`, `node-gyp`, and ABI mismatches across Node versions and CPU architectures (`arm64` / `x86_64`).
- **Persistent Workers**: Both `macos_helper.swift` and `win_worker.ps1` stay resident across calls over `stdin`/`stdout` JSON lines, avoiding repeated `swiftc` or PowerShell `Add-Type` startup overhead (~300–500ms paid once at first call, then ~10–50ms per action).
- **Content-Hashed Swift Caching**: `macos.mjs` hashes `macos_helper.swift` (12-char SHA-256 prefix) and caches the compiled binary in `${PLUGIN_DATA}/bin/macos-helper-<hash>`, automatically recompiling when the plugin updates.
- **PowerShell 5.1 + .NET Framework 4.8 Compatibility**: `win_worker.ps1` uses `-Sta` (required by `System.Windows.Forms.Clipboard`) and avoids PowerShell 7+ or .NET Core-only APIs so it works out of the box on stock Windows 10 and 11.

---

## 5. Coordinate Space & HiDPI Scaling

All tools standardize on a **top-left primary-display `(0, 0)` origin** across both operating systems. Secondary displays positioned left or above the primary monitor carry negative `x` or `y` coordinates.

```mermaid
flowchart LR
    subgraph Capture["1. Screen Capture"]
        Raw["Native Display / Region / Window\nLogical Bounds: (x, y, W, H)"] --> Scale["Downscale to max_width (default 1440px)\nImage Size: (Iw, Ih)"]
        Scale --> Grid["Optional 200px logical coordinate grid"]
    end

    subgraph Ground["2. Model Grounding"]
        Grid -->|"Visual pixel (px, py)"| Formula["sx = bounds.x + px * (bounds.width / Iw)\nsy = bounds.y + py * (bounds.height / Ih)"]
        AX["get_ui_tree / find_ui_elements"] -->|"Direct logical center"| Center["(cx, cy)"]
    end

    subgraph Act["3. Pointer Input"]
        Formula --> Input["mouse_click / mouse_move / mouse_drag"]
        Center --> Input
    end
```

### OS-Specific Coordinate Details
- **macOS (`CoreGraphics` vs `AppKit`)**:
  - `CGDisplayBounds`, `CGWindowListCopyWindowInfo`, `CGEvent.location`, `AXPosition`, and `CGEventCreateMouseEvent` all use **top-left logical points** (`3008x1692` on a 2x Retina display).
  - `NSScreen.visibleFrame` uses AppKit's **bottom-left** origin; `macos_helper.swift` and `macos_jxa.js` flip `work_area.y` via `primaryHeight - (vf.origin.y + vf.size.height)` so `work_area` matches CoreGraphics top-left space.
- **Windows (`Per-Monitor DPI Aware v2`)**:
  - `win_worker.ps1` calls `SetProcessDpiAwarenessContext((IntPtr)(-4))` (with `SetProcessDPIAware()` fallback) at startup so `Screen.AllScreens`, `DwmGetWindowAttribute` (`DWMWA_EXTENDED_FRAME_BOUNDS`), `GetCursorPos`, `SetCursorPos`, `SendInput`, `CopyFromScreen`, and `UIAutomationClient` `BoundingRectangle` all share exact unvirtualized virtual-screen coordinates.

---

## 6. Key Normalization & Accessibility Grounding

### Cross-Platform Key & Modifier Mapping (`scripts/drivers/common.mjs`)
- **`"primary"` modifier**: Automatically maps to `"cmd"` on macOS (`darwin`) and `"ctrl"` on Windows (`win32`).
- **Aliases**: Normalized uniformly (`return` → `enter`, `esc` → `escape`, `option` → `alt`, `command` → `cmd`, `control` → `ctrl`, `win`/`super` → `meta`).
- **Unicode typing**:
  - `macos_helper.swift`: Posts `CGEvent` keyboard events with `keyboardSetUnicodeString` (UTF-16) for arbitrary characters regardless of active keyboard layout (with `via_clipboard: true` fallback using `NSPasteboard` + `Cmd+V`).
  - `win_worker.ps1`: Uses `SendInput` with `KEYEVENTF_UNICODE` scan codes (plus `KEYEVENTF_EXTENDEDKEY` for navigation/Win keys, and `Clipboard.SetText` + `Ctrl+V` when `via_clipboard: true`).

### macOS Accessibility Trust Handling
On macOS, when Antigravity spawns `language_server` → `node` → `macos-helper`, `AXIsProcessTrusted()` can return `false` inside a running subprocess due to TCC process-token caching even after Accessibility is granted to Antigravity. To avoid false negatives:
- `macos_helper.swift` calls `probeAccessibility()` (testing `AXIsProcessTrusted()` and live `AXUIElementCopyAttributeValue` queries) in `check_permissions`.
- Action handlers execute directly against `AXUIElement` / `CGEventPost` instead of pre-blocking on `AXIsProcessTrusted()`.

---

## 7. Safety & Guardrail Architecture

```mermaid
flowchart TD
    Call["Incoming MCP Tool Call"] --> Hook["scripts/safety-hook.mjs"]
    Hook --> EnvCheck{"COMPUTER_USE_DISABLED == '1'\nor PLUGIN_DATA/EMERGENCY_STOP exists?"}
    EnvCheck -->|"Yes"| Deny["Return decision: 'deny' (Blocks execution)"]
    EnvCheck -->|"No"| Redact{"COMPUTER_USE_REDACT_LOGS == '1'?"}
    Redact -->|"Yes"| MaskText["Mask args.text length"]
    Redact -->|"No"| KeepArgs["Keep tool args"]
    MaskText --> Audit["Append JSON line to PLUGIN_DATA/audit.jsonl"]
    KeepArgs --> Audit
    Audit --> Allow["Return decision: 'allow'"]
    Allow --> Rules["Behavioral Guardrails (rules/AGENTS.md):\n- No passwords/2FA entry\n- No CAPTCHA/UAC/TCC bypass\n- Confirm destructive GUI actions"]
```

---

## 8. MCP Tool Suite (26 Tools)

`mcp_config.json` marks the 12 most frequent perception, input, UI, and window tools as **`eager: true`** and leaves 14 specialized tools lazy-loaded to minimize baseline context overhead.

| Category | Tools (`*` = eager) | macOS Implementation | Windows Implementation |
| --- | --- | --- | --- |
| **Perception & Diagnostics** | `screenshot`* , `get_screen_info`* , `check_permissions` , `get_system_info` | `screencapture` + `CGContext` / `CGImageDestination`, `CGGetActiveDisplayList`, `AXIsProcessTrusted` + probe | `Graphics.CopyFromScreen`, `Screen.AllScreens`, `shcore.dll` DPI, `WindowsIdentity` |
| **Mouse** | `mouse_click`* , `mouse_drag`* , `mouse_scroll`* , `mouse_move` , `mouse_down` , `mouse_up` | `CGEvent(mouseEventSource:)`, `CGEvent(scrollWheelEvent2Source:)` | `SetCursorPos` + `SendInput` (`INPUT_MOUSE`, `WHEEL`, `HWHEEL`) |
| **Keyboard** | `type_text`* , `press_key`* , `hotkey`* , `key_down` , `key_up` | `CGEvent` + `keyboardSetUnicodeString` / `CGKeyCode` | `SendInput` (`KEYEVENTF_UNICODE`, `VK_*`, `KEYEVENTF_EXTENDEDKEY`) |
| **Accessibility / UI** | `get_ui_tree`* , `click_ui_element`* , `find_ui_elements` | `AXUIElementCreateApplication` + `kAXChildrenAttribute` | `AutomationElement.FromHandle` + `TreeWalker.ControlViewWalker` |
| **Windows & Apps** | `list_windows`* , `focus_window`* , `manage_window` , `list_running_apps` , `launch_app` | `CGWindowListCopyWindowInfo`, `NSRunningApplication`, `AXUIElement`, `/usr/bin/open` | `EnumWindows`, `DwmGetWindowAttribute`, `AttachThreadInput` + `SetForegroundWindow`, `Process.Start` |
| **Clipboard & Timing** | `clipboard_read` , `clipboard_write` , `wait` | `NSPasteboard.general` (`pbpaste`/`pbcopy` fallback), Node timer | `System.Windows.Forms.Clipboard` (STA), Node timer |
