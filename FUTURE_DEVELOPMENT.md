# Future Development & Roadmap Suggestions

This document captures prioritized architectural improvements, feature ideas, and platform expansions for future iterations of the **Computer Use** plugin (`computer-use`).

---

## v0.2.0 — Visual Grounding & Windows Verification

1. **Set-of-Mark (SoM) Annotated Screenshots**
   - Add an `annotate_ui: true` option to `screenshot` that combines `get_ui_tree` bounding boxes with the captured screenshot, drawing numbered bounding boxes (`[1]`, `[2]`, ...) directly onto the image and returning a compact legend `{id, role, name, center_x, center_y}`.
   - Greatly reduces click coordinate hallucinations on dense apps (IDEs, spreadsheets, CAD tools).

2. **Native Image Grid & Coordinate Overlay in Driver**
   - Currently optional grid overlay metadata/SVG or native drawing can be rendered directly inside the Swift (`CoreGraphics` `CGContext`) and Windows C# (`System.Drawing.Graphics`) screenshot pipelines with crisp coordinate ticks every 200px so zero extra dependencies are needed.

3. **Windows CI & Automated Integration Matrix**
   - Add a GitHub Actions workflow (`windows-latest` + `macos-latest`) that boots the MCP server, runs `screenshot`, `list_windows`, `get_ui_tree`, `clipboard_write`/`clipboard_read`, and validates `agy plugin validate --strict .` on every PR.

4. **macOS `ScreenCaptureKit` Upgrade (macOS 14+)**
   - Replace `screencapture` subprocess calls inside `macos_helper.swift` with `ScreenCaptureKit` (`SCShareableContent` + `SCScreenshotManager`) for sub-80ms in-memory captures of specific windows even when partially occluded, without writing temporary files to disk.

---

## v0.3.0 — Semantic Reliability & Faster Feedback Loops

5. **Wait-for-Visual / Wait-for-UI-Change Conditions**
   - Upgrade `wait` with smart conditions:
     - `until_ui_element`: Poll `find_ui_elements` until a button/dialog appears (e.g., `"Save"`, `"Build Succeeded"`).
     - `until_screen_changes`: Hash downscaled region pixels and return as soon as the UI stops changing (settle detection after clicking a slow action).

6. **Direct Accessibility Actions (`AXPress` / UIA `InvokePattern` / `ValuePattern`)**
   - Add an optional `native_action: true` mode in `click_ui_element` and a `set_ui_value` tool that invokes native Accessibility actions (`AXPress`, `AXRaise`, UIA `InvokePattern`, `ValuePattern.SetValue`, `TogglePattern`) without moving the physical mouse cursor—enabling background-window automation where supported.

7. **Diff-Only / Cropped Follow-Up Screenshots**
   - Compute a bounding box of pixels changed since the previous screenshot and optionally return only the changed crop + full coordinates, cutting multimodal token usage by 60–85% during repetitive form-filling or terminal/UI monitoring loops.

8. **Built-In OCR Fallback (macOS Vision & Windows.Media.Ocr)**
   - Add a `find_text_on_screen` tool using **Apple Vision** (`VNRecognizeTextRequest`, built into macOS) and **Windows OCR** (`Windows.Media.Ocr`, built into Win10/11).
   - Crucial for Electron apps, games, RDP/VNC windows, or custom Canvas UIs that expose sparse accessibility trees.

---

## v0.4.0 — Safety, Privacy & Developer UX

9. **Antigravity Sidecar Live Preview & Action Replay Pane**
   - Add an optional Antigravity `sidecars/` UI panel showing:
     - Live thumbnail of the last screenshot with click/drag markers overlaid.
     - One-click **Emergency Pause / Resume** toggle button (manages `${PLUGIN_DATA}/EMERGENCY_STOP`).
     - Real-time action ledger parsed from `${PLUGIN_DATA}/audit.jsonl`.

10. **Sensitive Window & Region Redaction**
    - Automatically detect password managers (1Password, Bitwarden, Keychain Access), banking tabs, or OS `AXSecureTextField` / `IsPassword` elements and blur/mask those bounding boxes before returning screenshots to the model.

11. **Global OS Emergency Hotkey Listener**
    - Allow the user to press a physical emergency abort shortcut (e.g., `Ctrl+Alt+Shift+Escape` / `Cmd+Option+Shift+Escape`) that writes `${PLUGIN_DATA}/EMERGENCY_STOP`, immediately halting any ongoing `computer-operator` automation loop.

12. **Macro Recording & Deterministic Replay**
    - Record successful tool trajectories (UI element selectors + fallback coordinates) into reusable `.json` workflows stored in `${PLUGIN_DATA}/macros/`, enabling instant deterministic replay without LLM turns.

---

## v1.0.0 — Ecosystem & Cross-Platform Expansion

13. **Linux Desktop Driver (X11 & Wayland)**
    - Support X11 (`xdotool`/`xrandr`/`scrot`/AT-SPI2) and Wayland (`ydotool`/`wlr-randr`/`grim`/xdg-desktop-portal RemoteDesktop) to cover all three desktop OSes.

14. **Virtual / Secondary Desktop Isolation (Optional)**
    - On Windows: support Windows Virtual Desktops (`IVirtualDesktopManager`) or Windows Sandbox isolation so the agent works on Desktop 2 without hijacking the user's active mouse/keyboard on Desktop 1.
    - On macOS: support dedicated Space switching or Screen Sharing virtual session workflows.

15. **Multi-Agent Guardrails & Approval Tiers**
    - Configurable policy profiles (`observe-only`, `app-scoped` allowlist, `full-control`) persisted in `${PLUGIN_DATA}/policy.json` and enforced deterministically in `scripts/safety-hook.mjs`.
