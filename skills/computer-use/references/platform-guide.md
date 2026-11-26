# Cross-Platform Reference: macOS & Windows

## 1. Modifier Key Normalization

| Logical Name | macOS Mapping | Windows Mapping |
| --- | --- | --- |
| `"primary"` | Command (`cmd`) | Control (`ctrl`) |
| `"cmd"` / `"command"` / `"meta"` / `"win"` / `"super"` | Command (`⌘`) | Windows key (`LWin`) |
| `"ctrl"` / `"control"` | Control (`⌃`) | Control (`Ctrl`) |
| `"alt"` / `"option"` | Option (`⌥`) | Alt (`Alt`) |
| `"shift"` | Shift (`⇧`) | Shift (`Shift`) |

## 2. Supported Named Keys (`press_key` / `hotkey`)

- **Navigation**: `up`, `down`, `left`, `right`, `home`, `end`, `pageup`, `pagedown`
- **Editing**: `enter` / `return`, `tab`, `backspace`, `delete`, `escape` / `esc`, `space`, `insert` (Windows)
- **Function keys**: `f1` through `f12`
- **Characters**: `a`–`z`, `0`–`9`, `-`, `=`, `[`, `]`, `\`, `;`, `'`, `,`, `.`, `/`, `` ` ``
- **Media / System**: `capslock`, `volumeup`, `volumedown`, `mute`

## 3. Common Cross-Platform Shortcuts

| Action | Cross-Platform `hotkey` |
| --- | --- |
| Copy | `["primary", "c"]` |
| Cut | `["primary", "x"]` |
| Paste | `["primary", "v"]` |
| Select All | `["primary", "a"]` |
| Undo | `["primary", "z"]` |
| Save | `["primary", "s"]` |
| Find | `["primary", "f"]` |
| New Tab / Window | `["primary", "t"]` / `["primary", "n"]` |
| Close Tab / Window | `["primary", "w"]` |
| Switch App | macOS: `["cmd", "tab"]` · Windows: `["alt", "tab"]` |
| App Launcher | macOS: `["cmd", "space"]` · Windows: `["win"]` |

## 4. Coordinate Systems & Multi-Monitor

- **Primary display top-left is `(0, 0)`** on both macOS and Windows.
- Secondary displays arranged to the left or above the primary display have **negative `x` or `y`** coordinates.
- Always read `capture_bounds` returned by `screenshot`:
  - `capture_bounds`: `{ x, y, width, height }` in logical input space.
  - `image_size`: `{ width, height }` of the returned PNG/JPEG buffer.
  - Convert pixel coordinates `(px, py)` in the screenshot back to input coordinates via:
    - `x = capture_bounds.x + px * (capture_bounds.width / image_size.width)`
    - `y = capture_bounds.y + py * (capture_bounds.height / image_size.height)`

## 5. OS Permission Troubleshooting

### macOS
- **Screen Recording**: *System Settings → Privacy & Security → Screen & System Audio Recording* → enable the host terminal or Antigravity app.
- **Accessibility**: *System Settings → Privacy & Security → Accessibility* → enable the host terminal or Antigravity app.

### Windows
- Works out of the box for standard user-level desktop apps.
- Elevated (Administrator) windows block input from non-elevated MCP processes due to Windows **UIPI (User Interface Privilege Isolation)**. Launch Antigravity at the matching privilege level only when explicitly required.
