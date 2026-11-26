---
name: computer-use
description: >-
  Full cross-platform desktop computer use on macOS and Windows: screen capture,
  mouse and keyboard control, window/app management, clipboard operations, and
  OS permission diagnostics. Use whenever the user asks to control the computer,
  interact with native desktop apps, click on screen, type into apps, manage
  windows, or automate GUI tasks outside a web browser.
---

# Computer Use Workflow (macOS & Windows)

Use this workflow to control the user's macOS or Windows desktop reliably, safely, and with minimal wasted tokens.

## Step 1: Preflight & Environment Check

1. Run `get_system_info` and `check_permissions` at the start of a desktop task.
   - On **macOS**, both **Screen Recording** and **Accessibility** permissions must be granted to the host terminal/Antigravity app for full screenshot and input/UI-tree control. If either is missing, present the exact System Settings pane path and stop so the user can grant access.
   - On **Windows**, verify `dpi_aware: true`. Note that UIPI prevents non-elevated processes from sending input into elevated (Administrator) windows.
2. Run `get_screen_info` to inspect connected displays, logical bounds `(x, y, width, height)`, scale factors, cursor position, and the frontmost window.

## Step 2: Observe Before Acting

- Call `list_windows` to see open windows, titles, PIDs, and bounds.
- Call `screenshot` to visually inspect the desktop, a specific display (`display_id`), a window (`window_id` or `app_name`), or a sub-region (`region`).
  - Screenshots default to `max_width: 1440` and `format: "jpeg"` for speed and token efficiency.
  - Check `capture_bounds` in the response: all coordinates you pass to `mouse_click`, `mouse_move`, or `mouse_drag` must be in **global logical screen coordinates**, NOT scaled image pixel coordinates!
  - Use `grid: true` when you need a quick visual ruler reference, or combine with `get_ui_tree` for exact element bounding boxes.

## Step 3: Focus & Ground Target

1. Before typing or clicking inside an app, call `focus_window` (by `window_id`, `app_name`, or `title_contains`) so keystrokes never land in the wrong window.
2. For native buttons, menus, tabs, and inputs, read `skills/ui-automation/SKILL.md` or call `find_ui_elements` / `get_ui_tree` to obtain exact `(cx, cy)` coordinates.
3. For custom canvases, webviews, or visual targets, read the location from the screenshot and map it to `capture_bounds`:
   - `screen_x = capture_bounds.x + (pixel_x / image_width) * capture_bounds.width`
   - `screen_y = capture_bounds.y + (pixel_y / image_height) * capture_bounds.height`

## Step 4: Execute Input Actions

- **Mouse**: `mouse_click`, `mouse_move`, `mouse_drag`, `mouse_scroll`, `mouse_down`, `mouse_up`.
- **Keyboard**:
  - `type_text`: Handles Unicode text directly. Set `via_clipboard: true` for long paragraphs or code snippets (note this updates clipboard).
  - `hotkey`: Pass an array like `["primary", "s"]` (`"primary"` -> `cmd` on macOS, `ctrl` on Windows).
  - `press_key`: Tap special keys (`enter`, `tab`, `escape`, `backspace`, `delete`, `up`, `down`, `left`, `right`, `space`, `f1`–`f12`).
- **Windows & Apps**: `launch_app`, `manage_window` (`move`, `resize`, `minimize`, `maximize`, `restore`, `close`), `list_running_apps`.
- **Clipboard**: `clipboard_read`, `clipboard_write`.

## Step 5: Verify Result

After critical clicks, form submissions, or app launches, call `wait` (e.g., `300`–`800` ms) with `capture_screenshot: true` or call `screenshot` / `get_ui_tree` to confirm the desktop reflects the expected state.

## Reference

See [references/platform-guide.md](references/platform-guide.md) for cross-platform key names, modifier mappings, and OS-specific quirks.
