---
name: ui-automation
description: >-
  Accessibility-first desktop UI automation using macOS AXUIElement and Windows
  UI Automation (UIA). Use when you need to inspect desktop application
  controls, find buttons/text fields/menus by label or role, or click native UI
  elements with exact coordinates instead of guessing pixels.
---

# Accessibility-First UI Automation

Reading the native accessibility tree is faster, deterministic, and uses far fewer tokens than repeated high-resolution screenshots.

## Recommended Pattern

1. **Discover Windows**: Call `list_windows` to identify the target `app_name` or `pid`.
2. **Focus Window**: Call `focus_window` so the target window is active and on top.
3. **Inspect Controls**:
   - Call `get_ui_tree` with `app_name` (or `pid`), `max_depth: 5`, and `interactive_only: true` to list buttons, text fields, checkboxes, tabs, menu items, and links with their `(cx, cy)` center coordinates.
   - Or call `find_ui_elements` with `query` (case-insensitive substring match against title/label/value/identifier) and/or `role`.
4. **Click or Type**:
   - Call `click_ui_element` with the matched `query`/`role`/`app_name` (and `index` if multiple matches exist).
   - After clicking a text field, call `type_text` or `hotkey` (`["primary", "a"]` then `type_text` to replace existing text).
5. **Fallback to Vision**:
   - Electron, custom game engines, or canvas-heavy apps sometimes expose sparse UI trees. If `get_ui_tree` returns few elements, capture a `screenshot` and ground visually.
