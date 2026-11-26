# Future Development & Roadmap Suggestions

This document outlines prioritized engineering improvements for future versions of the **Computer Use** plugin (`computer-use`), focusing on four core pillars requested for the next release cycle: **Token Efficiency**, **Integration with `agy-context-plugin`**, **Guardrails**, and **Runtime Performance** — followed by longer-term ecosystem milestones.

---

## Next Version Priorities (v0.2.0 – v0.3.0)

### 1. Token Efficiency

Visual desktop loops can consume tens of thousands of multimodal and JSON tokens if every step sends full-screen images and unpruned accessibility trees.

1. **Adaptive Screenshot Resolution, Quality & Auto-Cropping**
   - Default routine verification captures to `max_width: 960` and JPEG `quality: 68`–`75`, reserving `1440+` or PNG for dense text/UI grounding.
   - Automatically scope `screenshot` to the focused/target window (`window_id`) when `app_name` is active instead of capturing the entire multi-monitor desktop.

2. **Region-Diff & Changed-Bounding-Box Screenshots**
   - Retain a lightweight downscaled hash/buffer of the previous screenshot inside the native Swift/C# worker.
   - When `diff_only: true` is enabled:
     - If nothing changed on screen, return `{ "unchanged": true }` with **zero image bytes**.
     - If `< 35%` of the frame changed, crop strictly to the dirty bounding box (`diff_bounds` in logical screen coordinates) and return only that region (~60–85% vision token reduction during typing, terminal watching, and form filling).

3. **Compact Accessibility Tree Serialization & Structural Pruning**
   - Add a `compact: true` output mode for `get_ui_tree` that strips decorative/empty container nodes (`AXGroup`, `AXRulerMarker`, `Pane`, empty `AXRow`s) and formats elements as compact records (`[id] role "title" val="..." @(cx,cy)`), cutting JSON structural overhead by 50–75%.

4. **Set-of-Mark (SoM) Visual Grounding (`annotate_ui: true`)**
   - Overlay numbered tags (`[1]`, `[2]`, …) onto interactive UI elements directly inside Swift (`CGContext`) and Windows C# (`System.Drawing.Graphics`), returning a tiny `{ id, role, title, cx, cy }` legend so the model picks an element ID instead of parsing deep trees or guessing pixels.

5. **Composite `act_and_verify` / `batch_actions` Tool**
   - Execute short deterministic sequences (e.g., `focus_window` → `mouse_click` → `type_text` → `press_key` → `wait` → `screenshot`) in a single MCP round-trip, avoiding multiple LLM turns and repeated conversation context prefixes.

---

### 2. Integration with `agy-context-plugin`

Combining `computer-use` with [`agy-context-plugin`](https://github.com/omerokumus1/agy-context-plugin) turns passive token monitoring into **context-aware desktop automation**:

6. **Live Context-Pressure Adaptation**
   - Read active session token usage, context ceiling, and prompt cache hit rate from Antigravity's local Language Server Connect-RPC / SQLite conversation store (using the same zero-token telemetry pipeline as `agy-context-plugin`'s `lib/rpc.mjs`, `lib/sqlite-fallback.mjs`, and `lib/telemetry.mjs`):
     - **`< 60%` Context Used**: Full-detail mode (`max_width: 1440`, `max_depth: 5` UI trees).
     - **`60%–80%` Context Used**: Automatically step down `screenshot` defaults (`max_width: 960`, active-window crop) and set `interactive_only: true` + `compact: true` on `get_ui_tree`.
     - **`> 80%` Context Used**: Prefer `find_ui_elements` / `diff_only` captures and emit a `context_pressure: "high"` advisory recommending `/compact` or delegating remaining GUI steps to a fresh `computer-operator` subagent.

7. **Prompt Cache Preservation & Frame Offloading**
   - Keep `rules/AGENTS.md` and MCP tool definitions deterministic so prompt prefixes stay cacheable (maximizing `agy-context-plugin`'s **Cache Hit %**).
   - Optionally return a file reference or downscaled thumbnail for historical frames and persist full-resolution captures in `${PLUGIN_DATA}/frames/` so old screenshots don't pollute long-running trajectories.

8. **Vision & UI-Tree Spike Attribution in `agy-context-plugin`**
   - Emit structured metadata (`image_bytes`, `image_size`, `ui_nodes_count`, `estimated_tokens`) in tool results and `${PLUGIN_DATA}/audit.jsonl` so `agy-context-plugin`'s **Top 5 Context Spikes** and **Turn Timeline** can break down GUI vision spikes vs code-reading spikes.

9. **Unified Sidecar Telemetry Surface**
   - Expose a lightweight local status endpoint / shared state file (`${PLUGIN_DATA}/live_state.json`) so either:
     - `agy-context-plugin` can display a **Computer Use Cost & Action** badge inside its `AUX_PANE` / `SIDEBAR`, or
     - `computer-use` ships an optional companion `sidecars/` pane (built with `sidecar_sdk`, matching `agy-context-plugin`) displaying the last captured frame with click markers, live context budget impact, audit ledger, and a one-click **Emergency Stop** toggle.

---

### 3. Guardrails & Safety Hardening

10. **Deterministic Policy Profiles (`${PLUGIN_DATA}/policy.json`)**
    - Upgrade `scripts/safety-hook.mjs` (`PreToolUse`) with configurable enforcement profiles:
      - `observe-only`: Allows `screenshot`, `get_screen_info`, `list_windows`, `get_ui_tree`, `find_ui_elements`, `check_permissions`; denies all input/window mutation tools.
      - `app-scoped`: Restricts clicks, typing, and `focus_window` to an explicit allowlist of applications/window titles (e.g., `["TextEdit", "Xcode", "Figma"]`).
      - `full-control`: Full desktop access with sensitive-action gates.

11. **Automatic Sensitive UI & Pixel Redaction**
    - Detect password inputs (`AXSecureTextField` on macOS, `IsPassword` in Windows UIA) and sensitive windows (1Password, Bitwarden, Keychain Access, Windows Credential Manager) to:
      - Blur/mask those bounding boxes in-memory before encoding `screenshot` images.
      - Redact `value` fields in `get_ui_tree` / `find_ui_elements` and auto-enable log redaction in `safety-hook.mjs`.

12. **Destructive Action & Risky Hotkey Gates**
    - Intercept high-risk GUI actions in `safety-hook.mjs` and return `"decision": "ask"` (prompting user approval) when:
      - Clicking controls labeled `Delete`, `Empty Trash`, `Erase`, `Format`, `Purchase`, `Pay`, `Send`, or `Quit` on protected apps.
      - Executing destructive system hotkeys or shell-launch chords (e.g., `Cmd+Option+Esc`, `Alt+F4` on Antigravity itself, or `launch_app` on unknown executables).

13. **Runaway Loop & Rate-Limit Circuit Breakers**
    - Track recent tool calls in `${PLUGIN_DATA}/hook_state.json` inside `safety-hook.mjs`:
      - Block or pause after `N` consecutive identical clicks/keystrokes at unchanged coordinates.
      - Enforce configurable actions-per-minute and per-turn GUI step budgets (`max_actions_per_turn`).

14. **Global Physical Emergency Stop Hotkey**
    - Register an OS-level abort shortcut (e.g., `Cmd+Option+Shift+Escape` on macOS, `Ctrl+Alt+Shift+Escape` on Windows) that immediately writes `${PLUGIN_DATA}/EMERGENCY_STOP`, halting any ongoing `computer-operator` loop on the very next `PreToolUse` check.

---

### 4. Performance Optimization

15. **macOS `ScreenCaptureKit` In-Memory Pipeline (macOS 14+)**
    - Replace `/usr/sbin/screencapture` subprocess calls and temporary PNG disk files in `macos_helper.swift` with `ScreenCaptureKit` (`SCShareableContent` + `SCScreenshotManager`).
    - Cuts single-frame capture latency from ~120–200ms down to `< 40–60ms`, eliminates disk I/O, and supports capturing specific windows cleanly even when partially occluded.

16. **Windows DXGI Desktop Duplication (`IDXGIOutputDuplication`)**
    - Add a GPU-accelerated capture path alongside GDI+ `CopyFromScreen` in `win_worker.ps1` for sub-30ms multi-monitor captures and hardware-provided dirty-rect regions.

17. **Pre-Built / Signed Native Helper Distribution**
    - Distribute pre-compiled, signed universal binaries for macOS (`arm64` + `x86_64`) and an optional ahead-of-time compiled `.NET` helper DLL/executable on Windows to eliminate cold startup compilation (`swiftc` ~4s once; PowerShell `Add-Type` ~300–500ms per worker start) and make macOS TCC permissions consistent across plugin updates.

18. **UI Tree Caching, Subtree Scoping & Wait-for-Condition Primitives**
    - Cache short-lived (250–500ms) `AXUIElement` / UIA snapshots keyed by `(pid, window_id)` and support scoped root queries (`window_id` / `element_id`) instead of always walking the full app tree.
    - Replace blind `wait(ms)` polling loops with native condition waiters inside the persistent workers:
      - `until_ui_element`: Resolve immediately once a matching button/label appears.
      - `until_screen_settles`: Return as soon as consecutive frame hashes stabilize.

---

### 5. UI/UX & Human-in-the-Loop Control (Overlay, `Esc` State Machine & Visual Feedback)

19. **Gemini-Style Edge Glow Overlay (`Active` / `Dimmed` / `Off`)**
    - Render a lightweight, click-through, always-on-top transparent border overlay around the active monitor(s) whenever Antigravity is driving the computer (macOS `NSWindow` with `ignoresMouseEvents = true` + CoreAnimation/Metal shader; Windows `WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOPMOST` overlay):
      - **Active**: Flowing Gemini-inspired luminous edge animation along the screen perimeter so the user always knows at a glance that autonomous desktop control is active.
      - **Paused / Waiting**: Smoothly dims the edge animation when control is yielded to the user.
      - **Stopped**: Fades out completely when computer use ends or is hard-stopped.
    - Exclude the overlay window itself from `screenshot` captures (`kCGWindowSharingNone` / `WDA_EXCLUDEFROMCAPTURE`) so the glow never obscures visual grounding or wastes vision tokens.

20. **Three-Tier `Esc` Interrupt & Yield State Machine**
    - Intercept global `Esc` key presses via a low-overhead OS input listener (`CGEventTap` listen-only on macOS; `WH_KEYBOARD_LL` on Windows) without blocking normal `Esc` usage inside apps:
      1. **Single `Esc` (Smart Pause & Idle-Triggered Resume Countdown)**:
         - Immediately pauses Antigravity's next desktop action and dims the edge glow animation.
         - Monitors user mouse/keyboard activity and waits until the user finishes interacting and remains idle for a couple of seconds (e.g., `2–3s`).
         - Once idle, shows a compact floating confirmation dialog/pill with a short countdown (e.g., `3–5s`):
           - **Confirm** or **countdown expires**: Antigravity restores full edge glow and resumes control.
           - **Reject**: Antigravity stays paused and keeps waiting (no forced takeover).
      2. **Double `Esc` (Manual Hold — No Countdown)**:
         - Pressing `Esc` twice enters **Manual Hold** mode: Antigravity pauses indefinitely and does **not** start any auto-resume countdown.
         - The user remains in full control until they explicitly tell Antigravity to continue (via a **Resume** button on the floating HUD or a chat instruction).
      3. **Long-Press `Esc` (Hard Stop)**:
         - Holding `Esc` (e.g., `>= 800ms`) triggers a **Hard Stop** (`EMERGENCY_STOP`), dismissing the edge glow and terminating the active computer-use run completely.
         - Antigravity does not resume on its own; the user must submit a new prompt to start again.

    ```mermaid
    stateDiagram-v2
        [*] --> Active: Start Computer Use (Edge Glow ON)
        Active --> SmartPause: Single Esc (Edge Glow DIMMED)
        SmartPause --> IdleWait: User active -> wait for 2-3s idle
        IdleWait --> CountdownToast: User idle -> show confirm dialog (3-5s)
        CountdownToast --> Active: Confirm or countdown finishes
        CountdownToast --> SmartPause: User rejects (keep waiting)
        Active --> ManualHold: Double Esc (Edge Glow DIMMED, no countdown)
        SmartPause --> ManualHold: Second Esc
        ManualHold --> Active: User explicitly resumes
        Active --> HardStopped: Long-press Esc (Edge Glow OFF)
        SmartPause --> HardStopped: Long-press Esc
        ManualHold --> HardStopped: Long-press Esc
        HardStopped --> [*]: Requires new user prompt
    ```

21. **Floating Action HUD & Click/Target Micro-Feedback**
    - **Compact Floating HUD Pill**: A translucent corner pill (draggable, minimized footprint) showing the live step label (e.g., `"Clicking 'Export' in Figma"`), current `Esc` mode badge, and one-click **Pause / Resume / Stop** controls.
    - **Pre-Click Target Ripple & Drag Trail**: Briefly animate a subtle translucent ring at `(x, y)` (~150ms) right before clicking or along drag paths so the user can visually track intent before impact.
    - **Active Window Spotlight**: Optionally outline the specific `window_id` Antigravity is currently controlling across multi-monitor setups.

22. **Automatic Mouse-Fight Detection ("Touch-to-Yield")**
    - Optionally detect unexpected physical mouse movement or keystrokes from the user during an active run (even without pressing `Esc`), automatically entering the **Smart Pause** state so the user never fights the cursor.

23. **Subtle Sound & Haptic Micro-Cues (Opt-In)**
    - Play quiet, distinct system/WebAudio micro-tones (or Mac Force Touch haptics) for **Takeover**, **Paused**, **Countdown Tick**, and **Hard Stop**, helpful when the user is looking across multiple displays.

---

## Longer-Term Ecosystem Roadmap (v0.4.0 – v1.0.0)

24. **Built-In Native OCR (`VNRecognizeTextRequest` & `Windows.Media.Ocr`)**
    - Add a `find_text_on_screen` tool using OS-built-in OCR for Canvas apps, Electron views, games, and remote desktop windows with sparse accessibility trees.

25. **Windows CI & Automated Integration Matrix**
    - Add GitHub Actions CI (`macos-latest` + `windows-latest`) running `agy plugin validate --strict .`, MCP protocol tests, PowerShell/Win32/UIA live tests, and coordinate scaling assertions on every commit.

26. **Macro Recording & Deterministic Replay**
    - Save verified UI-element action sequences into `${PLUGIN_DATA}/macros/*.json` for zero-LLM-token deterministic replay of repetitive desktop workflows.

27. **Linux Desktop Driver (X11 & Wayland)**
    - Add `scripts/drivers/linux.mjs` supporting X11 (`xdotool`/`xrandr`/`scrot`/AT-SPI2) and Wayland (`ydotool`/`grim`/`xdg-desktop-portal`).

28. **Virtual / Secondary Desktop Isolation**
    - Support Windows Virtual Desktops (`IVirtualDesktopManager`) and dedicated macOS Spaces so autonomous desktop work can run in the background without stealing the user's primary workspace focus.
