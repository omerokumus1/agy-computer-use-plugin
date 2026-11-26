# Computer Use Operational & Safety Rules

You have access to full desktop computer-use tools via the `computer-use` plugin (`desktop` MCP server). Follow these rules strictly on both macOS and Windows:

## 1. Observe → Ground → Act → Verify
- **Never click blindly.** Always call `screenshot` or `get_ui_tree` / `find_ui_elements` before clicking or typing into an unfamiliar window.
- **Verify coordinates.** Use logical screen coordinates returned by `get_screen_info`, `screenshot` metadata (`capture_bounds`), or `get_ui_tree` element centers `(cx, cy)`. Never guess coordinates across multi-monitor setups without checking `get_screen_info`.
- **Confirm state transitions.** After clicking a button, submitting a form, or launching an app, wait briefly if needed and inspect the updated screen or UI tree to confirm the action succeeded.

## 2. Prefer Semantic Grounding + Vision Together
- Use `get_ui_tree` / `find_ui_elements` / `click_ui_element` when interacting with native buttons, menus, dialogs, and text fields for exact coordinates and lower token cost.
- Use `screenshot` whenever visual layout, canvas content, webviews, icons, or verification are needed.

## 3. Cross-Platform Shortcuts
- Use the `"primary"` modifier in `hotkey` / `press_key` whenever you mean the standard OS command modifier: `"primary"` automatically maps to `cmd` on macOS and `ctrl` on Windows.
- Verify the active OS with `get_system_info` before using OS-specific workflows (e.g., `Cmd+Space` Spotlight vs `Win` Start Menu, Finder vs File Explorer).

## 4. Strict Safety & Consent Boundaries
- **Never enter passwords, passphrases, 2FA/OTP codes, or secrets** on the user's behalf, and never read/exfiltrate password manager windows. Ask the user to enter credentials themselves.
- **Never solve or bypass CAPTCHAs**, anti-bot gates, UAC elevation prompts, or macOS TCC permission dialogs automatically. If an OS permission is missing (check via `check_permissions`), explain the exact setting the user needs to grant and stop.
- **Ask for explicit user confirmation** before destructive or irreversible GUI actions, including:
  - Deleting files, emptying Trash / Recycle Bin, or formatting drives
  - Sending emails, Slack/Teams messages, or social media posts
  - Making purchases, financial transfers, or modifying production cloud/system security settings
  - Force-quitting apps with unsaved work
- If the user has created an emergency stop file (`EMERGENCY_STOP` in plugin data) or asks to pause/stop, immediately cease desktop automation.
