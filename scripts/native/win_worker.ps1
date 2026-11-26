[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$csharpSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;

public static class ComputerUseWin {
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct CURSORINFO {
        public int cbSize;
        public int flags;
        public IntPtr hCursor;
        public POINT ptScreenPos;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    public struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDPIAware();

    [DllImport("user32.dll")]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern bool GetCursorInfo(ref CURSORINFO pci);

    [DllImport("user32.dll")]
    public static extern bool DrawIcon(IntPtr hDC, int X, int Y, IntPtr hIcon);

    [DllImport("user32.dll")]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool BringWindowToTop(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    [DllImport("user32.dll")]
    public static extern bool IsIconic(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsZoomed(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll")]
    public static extern int GetWindowTextLength(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

    [DllImport("user32.dll")]
    public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

    [DllImport("dwmapi.dll")]
    private static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out int pvAttribute, int cbAttribute);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hmonitor, int dpiType, out uint dpiX, out uint dpiY);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromPoint(POINT pt, uint dwFlags);

    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;
    private const uint MOUSEEVENTF_HWHEEL = 0x1000;
    private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    private const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;

    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    private const uint WM_CLOSE = 0x0010;
    private const int SW_MINIMIZE = 6;
    private const int SW_MAXIMIZE = 3;
    private const int SW_RESTORE = 9;

    private static int Clamp(int val, int min, int max) {
        return val < min ? min : (val > max ? max : val);
    }

    public static bool DpiAwareInitialized = false;

    public static void InitDpi() {
        try {
            if (SetProcessDpiAwarenessContext((IntPtr)(-4))) {
                DpiAwareInitialized = true;
                return;
            }
        } catch {}
        try {
            DpiAwareInitialized = SetProcessDPIAware();
        } catch {
            DpiAwareInitialized = false;
        }
    }

    public static bool IsElevated() {
        using (var id = WindowsIdentity.GetCurrent()) {
            var principal = new WindowsPrincipal(id);
            return principal.IsInRole(WindowsBuiltInRole.Administrator);
        }
    }

    public static RECT GetAccurateWindowRect(IntPtr hWnd) {
        RECT r;
        try {
            if (DwmGetWindowAttribute(hWnd, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0) {
                return r;
            }
        } catch {}
        GetWindowRect(hWnd, out r);
        return r;
    }

    public static bool IsCloaked(IntPtr hWnd) {
        try {
            int cloaked = 0;
            if (DwmGetWindowAttribute(hWnd, 14, out cloaked, Marshal.SizeOf(typeof(int))) == 0) {
                return cloaked != 0;
            }
        } catch {}
        return false;
    }

    public static double GetMonitorScale(Screen screen) {
        try {
            var pt = new POINT { X = screen.Bounds.Left + 1, Y = screen.Bounds.Top + 1 };
            var hMon = MonitorFromPoint(pt, 2);
            uint dpiX, dpiY;
            if (GetDpiForMonitor(hMon, 0, out dpiX, out dpiY) == 0 && dpiX > 0) {
                return Math.Round(dpiX / 96.0, 2);
            }
        } catch {}
        return 1.0;
    }

    public static Dictionary<string, object> GetScreenInfo() {
        var screens = new List<Dictionary<string, object>>();
        var all = Screen.AllScreens;
        for (int i = 0; i < all.Length; i++) {
            var s = all[i];
            var b = s.Bounds;
            var w = s.WorkingArea;
            screens.Add(new Dictionary<string, object> {
                { "id", i },
                { "name", s.DeviceName },
                { "primary", s.Primary },
                { "x", b.X },
                { "y", b.Y },
                { "width", b.Width },
                { "height", b.Height },
                { "scale", GetMonitorScale(s) },
                { "work_area", new Dictionary<string, object> {
                    { "x", w.X }, { "y", w.Y }, { "width", w.Width }, { "height", w.Height }
                }}
            });
        }

        POINT pt;
        GetCursorPos(out pt);

        var fg = GetForegroundWindow();
        Dictionary<string, object> front = null;
        if (fg != IntPtr.Zero) {
            uint pid = 0;
            GetWindowThreadProcessId(fg, out pid);
            string appName = "";
            try { appName = Process.GetProcessById((int)pid).ProcessName; } catch {}
            front = new Dictionary<string, object> {
                { "window_id", fg.ToInt64() },
                { "title", ReadWindowText(fg) },
                { "app_name", appName },
                { "pid", (int)pid }
            };
        }

        var vs = SystemInformation.VirtualScreen;
        return new Dictionary<string, object> {
            { "coordinate_space", "virtual_screen_pixels" },
            { "virtual_screen", new Dictionary<string, object> {
                { "x", vs.X }, { "y", vs.Y }, { "width", vs.Width }, { "height", vs.Height }
            }},
            { "displays", screens },
            { "cursor", new Dictionary<string, object> { { "x", pt.X }, { "y", pt.Y } } },
            { "frontmost_window", front }
        };
    }

    private static string ReadWindowText(IntPtr hWnd) {
        int len = GetWindowTextLength(hWnd);
        if (len <= 0) return "";
        var sb = new StringBuilder(len + 1);
        GetWindowText(hWnd, sb, sb.Capacity);
        return sb.ToString();
    }

    public static List<Dictionary<string, object>> ListWindows(string appFilter, bool includeMinimized) {
        var result = new List<Dictionary<string, object>>();
        var fg = GetForegroundWindow();
        EnumWindows((hWnd, lParam) => {
            if (!IsWindowVisible(hWnd)) return true;
            if (IsCloaked(hWnd)) return true;
            bool minimized = IsIconic(hWnd);
            if (!includeMinimized && minimized) return true;

            string title = ReadWindowText(hWnd);
            var r = GetAccurateWindowRect(hWnd);
            int w = r.Right - r.Left;
            int h = r.Bottom - r.Top;
            if (w <= 1 || h <= 1) return true;
            if (string.IsNullOrWhiteSpace(title)) return true;

            uint pid = 0;
            GetWindowThreadProcessId(hWnd, out pid);
            string appName = "";
            try { appName = Process.GetProcessById((int)pid).ProcessName; } catch {}

            if (!string.IsNullOrEmpty(appFilter)) {
                if (appName.IndexOf(appFilter, StringComparison.OrdinalIgnoreCase) < 0 &&
                    title.IndexOf(appFilter, StringComparison.OrdinalIgnoreCase) < 0) {
                    return true;
                }
            }

            result.Add(new Dictionary<string, object> {
                { "window_id", hWnd.ToInt64() },
                { "title", title },
                { "app_name", appName },
                { "pid", (int)pid },
                { "focused", hWnd == fg },
                { "minimized", minimized },
                { "maximized", IsZoomed(hWnd) },
                { "bounds", new Dictionary<string, object> {
                    { "x", r.Left }, { "y", r.Top }, { "width", w }, { "height", h }
                }}
            });
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static IntPtr ResolveWindow(long windowId, string appName, string titleContains, int pid) {
        if (windowId > 0) return new IntPtr(windowId);
        var wins = ListWindows(null, true);
        foreach (var w in wins) {
            int wPid = (int)w["pid"];
            string wApp = (string)w["app_name"];
            string wTitle = (string)w["title"];
            if (pid > 0 && wPid != pid) continue;
            if (!string.IsNullOrEmpty(appName) && wApp.IndexOf(appName, StringComparison.OrdinalIgnoreCase) < 0) continue;
            if (!string.IsNullOrEmpty(titleContains) && wTitle.IndexOf(titleContains, StringComparison.OrdinalIgnoreCase) < 0) continue;
            return new IntPtr((long)w["window_id"]);
        }
        return IntPtr.Zero;
    }

    public static Dictionary<string, object> FocusWindow(long windowId, string appName, string titleContains, int pid) {
        IntPtr hWnd = ResolveWindow(windowId, appName, titleContains, pid);
        if (hWnd == IntPtr.Zero) throw new Exception("Target window not found.");
        if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);

        IntPtr fg = GetForegroundWindow();
        uint curThread = GetCurrentThreadId();
        uint dummy;
        uint fgThread = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out dummy) : 0;
        if (fgThread != 0 && fgThread != curThread) {
            AttachThreadInput(curThread, fgThread, true);
            SetForegroundWindow(hWnd);
            BringWindowToTop(hWnd);
            AttachThreadInput(curThread, fgThread, false);
        } else {
            SetForegroundWindow(hWnd);
            BringWindowToTop(hWnd);
        }
        return new Dictionary<string, object> {
            { "focused", true },
            { "window_id", hWnd.ToInt64() },
            { "title", ReadWindowText(hWnd) }
        };
    }

    public static Dictionary<string, object> ManageWindow(string action, long windowId, string appName, string titleContains, int x, int y, int width, int height, bool hasX, bool hasY, bool hasW, bool hasH) {
        IntPtr hWnd = ResolveWindow(windowId, appName, titleContains, 0);
        if (hWnd == IntPtr.Zero) throw new Exception("Target window not found.");
        var r = GetAccurateWindowRect(hWnd);
        int curX = r.Left, curY = r.Top, curW = r.Right - r.Left, curH = r.Bottom - r.Top;

        switch (action.ToLowerInvariant()) {
            case "minimize": ShowWindow(hWnd, SW_MINIMIZE); break;
            case "maximize": ShowWindow(hWnd, SW_MAXIMIZE); break;
            case "restore": ShowWindow(hWnd, SW_RESTORE); break;
            case "close": PostMessage(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero); break;
            case "move":
                MoveWindow(hWnd, hasX ? x : curX, hasY ? y : curY, curW, curH, true);
                break;
            case "resize":
                MoveWindow(hWnd, curX, curY, hasW ? width : curW, hasH ? height : curH, true);
                break;
            case "set_bounds":
                MoveWindow(hWnd, hasX ? x : curX, hasY ? y : curY, hasW ? width : curW, hasH ? height : curH, true);
                break;
            default:
                throw new Exception("Unsupported manage_window action: " + action);
        }
        return new Dictionary<string, object> { { "ok", true }, { "window_id", hWnd.ToInt64() }, { "action", action } };
    }

    public static Dictionary<string, object> CaptureScreenshot(int displayId, bool hasDisplayId, int rx, int ry, int rw, int rh, bool hasRegion, long windowId, string appName, bool includeCursor, bool grid, int maxWidth, string format, int quality, string savePath) {
        Rectangle bounds;
        if (windowId > 0 || !string.IsNullOrEmpty(appName)) {
            IntPtr hWnd = ResolveWindow(windowId, appName, null, 0);
            if (hWnd == IntPtr.Zero) throw new Exception("Window not found for screenshot.");
            if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
            var r = GetAccurateWindowRect(hWnd);
            bounds = new Rectangle(r.Left, r.Top, Math.Max(1, r.Right - r.Left), Math.Max(1, r.Bottom - r.Top));
        } else if (hasRegion) {
            bounds = new Rectangle(rx, ry, Math.Max(1, rw), Math.Max(1, rh));
        } else if (hasDisplayId) {
            var all = Screen.AllScreens;
            if (displayId < 0 || displayId >= all.Length) throw new Exception("Invalid display_id: " + displayId);
            bounds = all[displayId].Bounds;
        } else {
            bounds = Screen.PrimaryScreen.Bounds;
        }

        using (var bmp = new Bitmap(bounds.Width, bounds.Height, PixelFormat.Format32bppArgb)) {
            using (var g = Graphics.FromImage(bmp)) {
                g.CopyFromScreen(bounds.Location, Point.Empty, bounds.Size, CopyPixelOperation.SourceCopy);
                if (includeCursor) {
                    var ci = new CURSORINFO { cbSize = Marshal.SizeOf(typeof(CURSORINFO)) };
                    if (GetCursorInfo(ref ci) && (ci.flags & 1) != 0) {
                        IntPtr hdc = g.GetHdc();
                        DrawIcon(hdc, ci.ptScreenPos.X - bounds.Left, ci.ptScreenPos.Y - bounds.Top, ci.hCursor);
                        g.ReleaseHdc(hdc);
                    }
                }
                if (grid) {
                    using (var pen = new Pen(Color.FromArgb(110, 255, 64, 64), 1))
                    using (var font = new Font("Consolas", 11, FontStyle.Bold))
                    using (var bgBrush = new SolidBrush(Color.FromArgb(170, 0, 0, 0)))
                    using (var txtBrush = new SolidBrush(Color.White)) {
                        for (int gx = 0; gx < bounds.Width; gx += 200) {
                            g.DrawLine(pen, gx, 0, gx, bounds.Height);
                            string lbl = (bounds.Left + gx).ToString();
                            g.FillRectangle(bgBrush, gx + 2, 2, 46, 18);
                            g.DrawString(lbl, font, txtBrush, gx + 3, 2);
                        }
                        for (int gy = 200; gy < bounds.Height; gy += 200) {
                            g.DrawLine(pen, 0, gy, bounds.Width, gy);
                            string lbl = (bounds.Top + gy).ToString();
                            g.FillRectangle(bgBrush, 2, gy + 2, 46, 18);
                            g.DrawString(lbl, font, txtBrush, 3, gy + 2);
                        }
                    }
                }
            }

            Bitmap finalBmp = bmp;
            bool disposeFinal = false;
            if (maxWidth > 0 && bmp.Width > maxWidth) {
                int targetH = Math.Max(1, (int)Math.Round(bmp.Height * (maxWidth / (double)bmp.Width)));
                finalBmp = new Bitmap(maxWidth, targetH);
                disposeFinal = true;
                using (var g2 = Graphics.FromImage(finalBmp)) {
                    g2.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g2.DrawImage(bmp, 0, 0, maxWidth, targetH);
                }
            }

            try {
                byte[] bytes;
                string mime = (format ?? "jpeg").ToLowerInvariant() == "png" ? "image/png" : "image/jpeg";
                using (var ms = new MemoryStream()) {
                    if (mime == "image/png") {
                        finalBmp.Save(ms, ImageFormat.Png);
                    } else {
                        var codec = Array.Find(ImageCodecInfo.GetImageEncoders(), c => c.FormatID == ImageFormat.Jpeg.Guid);
                        var ep = new EncoderParameters(1);
                        ep.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, (long)Clamp(quality, 10, 100));
                        finalBmp.Save(ms, codec, ep);
                    }
                    bytes = ms.ToArray();
                }

                if (!string.IsNullOrEmpty(savePath)) {
                    File.WriteAllBytes(savePath, bytes);
                }

                return new Dictionary<string, object> {
                    { "base64", Convert.ToBase64String(bytes) },
                    { "mime_type", mime },
                    { "capture_bounds", new Dictionary<string, object> {
                        { "x", bounds.X }, { "y", bounds.Y }, { "width", bounds.Width }, { "height", bounds.Height }
                    }},
                    { "image_size", new Dictionary<string, object> {
                        { "width", finalBmp.Width }, { "height", finalBmp.Height }
                    }}
                };
            } finally {
                if (disposeFinal) finalBmp.Dispose();
            }
        }
    }

    public static void MoveMouse(int x, int y, int durationMs) {
        if (durationMs <= 0) {
            SetCursorPos(x, y);
            return;
        }
        POINT start;
        GetCursorPos(out start);
        int steps = Clamp(durationMs / 16, 2, 60);
        for (int i = 1; i <= steps; i++) {
            double t = i / (double)steps;
            int cx = (int)Math.Round(start.X + (x - start.X) * t);
            int cy = (int)Math.Round(start.Y + (y - start.Y) * t);
            SetCursorPos(cx, cy);
            Thread.Sleep(Math.Max(1, durationMs / steps));
        }
    }

    private static void SendMouseFlag(uint flag, uint data = 0) {
        var inp = new INPUT {
            type = INPUT_MOUSE,
            U = new InputUnion {
                mi = new MOUSEINPUT { dwFlags = flag, mouseData = data }
            }
        };
        SendInput(1, new[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }

    private static uint DownFlag(string btn) {
        switch ((btn ?? "left").ToLowerInvariant()) {
            case "right": return MOUSEEVENTF_RIGHTDOWN;
            case "middle": return MOUSEEVENTF_MIDDLEDOWN;
            default: return MOUSEEVENTF_LEFTDOWN;
        }
    }

    private static uint UpFlag(string btn) {
        switch ((btn ?? "left").ToLowerInvariant()) {
            case "right": return MOUSEEVENTF_RIGHTUP;
            case "middle": return MOUSEEVENTF_MIDDLEUP;
            default: return MOUSEEVENTF_LEFTUP;
        }
    }

    public static ushort MapKey(string key) {
        if (string.IsNullOrEmpty(key)) return 0;
        switch (key.ToLowerInvariant()) {
            case "enter": return 0x0D;
            case "tab": return 0x09;
            case "escape": return 0x1B;
            case "backspace": return 0x08;
            case "delete": return 0x2E;
            case "insert": return 0x2D;
            case "space": return 0x20;
            case "up": return 0x26;
            case "down": return 0x28;
            case "left": return 0x25;
            case "right": return 0x27;
            case "home": return 0x24;
            case "end": return 0x23;
            case "pageup": return 0x21;
            case "pagedown": return 0x22;
            case "shift": return 0x10;
            case "ctrl": return 0x11;
            case "alt": return 0x12;
            case "win":
            case "cmd":
            case "meta": return 0x5B;
            case "capslock": return 0x14;
            case "f1": return 0x70; case "f2": return 0x71; case "f3": return 0x72; case "f4": return 0x73;
            case "f5": return 0x74; case "f6": return 0x75; case "f7": return 0x76; case "f8": return 0x77;
            case "f9": return 0x78; case "f10": return 0x79; case "f11": return 0x7A; case "f12": return 0x7B;
            case "volumeup": return 0xAF;
            case "volumedown": return 0xAE;
            case "mute": return 0xAD;
            case "-": return 0xBD; case "=": return 0xBB;
            case "[": return 0xDB; case "]": return 0xDD;
            case "\\": return 0xDC; case ";": return 0xBA;
            case "'": return 0xDE; case ",": return 0xBC;
            case ".": return 0xBE; case "/": return 0xBF;
            case "`": return 0xC0;
            default:
                if (key.Length == 1) {
                    char ch = char.ToUpperInvariant(key[0]);
                    if ((ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9')) return (ushort)ch;
                }
                throw new Exception("Unsupported key on Windows: " + key);
        }
    }

    private static bool IsExtended(ushort vk) {
        return vk == 0x21 || vk == 0x22 || vk == 0x23 || vk == 0x24 ||
               vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28 ||
               vk == 0x2D || vk == 0x2E || vk == 0x5B;
    }

    public static void KeyEvent(ushort vk, bool up) {
        uint flags = (IsExtended(vk) ? KEYEVENTF_EXTENDEDKEY : 0u) | (up ? KEYEVENTF_KEYUP : 0u);
        var inp = new INPUT {
            type = INPUT_KEYBOARD,
            U = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = flags } }
        };
        SendInput(1, new[] { inp }, Marshal.SizeOf(typeof(INPUT)));
    }

    public static void TypeUnicode(string text, int delayMs) {
        foreach (char ch in text) {
            if (ch == '\n') {
                KeyEvent(0x0D, false);
                KeyEvent(0x0D, true);
            } else if (ch == '\t') {
                KeyEvent(0x09, false);
                KeyEvent(0x09, true);
            } else if (ch != '\r') {
                var down = new INPUT {
                    type = INPUT_KEYBOARD,
                    U = new InputUnion { ki = new KEYBDINPUT { wScan = ch, dwFlags = KEYEVENTF_UNICODE } }
                };
                var up = new INPUT {
                    type = INPUT_KEYBOARD,
                    U = new InputUnion { ki = new KEYBDINPUT { wScan = ch, dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP } }
                };
                SendInput(2, new[] { down, up }, Marshal.SizeOf(typeof(INPUT)));
            }
            if (delayMs > 0) Thread.Sleep(delayMs);
        }
    }

    public static void MouseClick(int x, int y, bool hasPos, string button, int clickCount, string[] modifiers) {
        if (hasPos) SetCursorPos(x, y);
        var modVks = new List<ushort>();
        if (modifiers != null) {
            foreach (var m in modifiers) {
                var vk = MapKey(m);
                modVks.Add(vk);
                KeyEvent(vk, false);
            }
        }
        uint d = DownFlag(button), u = UpFlag(button);
        for (int i = 0; i < Math.Max(1, clickCount); i++) {
            SendMouseFlag(d);
            SendMouseFlag(u);
            if (i + 1 < clickCount) Thread.Sleep(40);
        }
        for (int i = modVks.Count - 1; i >= 0; i--) KeyEvent(modVks[i], true);
    }

    public static void MouseButton(int x, int y, bool hasPos, string button, bool down) {
        if (hasPos) SetCursorPos(x, y);
        SendMouseFlag(down ? DownFlag(button) : UpFlag(button));
    }

    public static void MouseDrag(int sx, int sy, int ex, int ey, string button, int durationMs, int steps) {
        SetCursorPos(sx, sy);
        Thread.Sleep(20);
        SendMouseFlag(DownFlag(button));
        int count = Clamp(steps, 2, 100);
        int stepDelay = Math.Max(1, durationMs / count);
        for (int i = 1; i <= count; i++) {
            double t = i / (double)count;
            SetCursorPos((int)Math.Round(sx + (ex - sx) * t), (int)Math.Round(sy + (ey - sy) * t));
            Thread.Sleep(stepDelay);
        }
        SendMouseFlag(UpFlag(button));
    }

    public static void MouseScroll(int x, int y, bool hasPos, int dx, int dy) {
        if (hasPos) SetCursorPos(x, y);
        if (dy != 0) SendMouseFlag(MOUSEEVENTF_WHEEL, unchecked((uint)(dy * 120)));
        if (dx != 0) SendMouseFlag(MOUSEEVENTF_HWHEEL, unchecked((uint)(dx * 120)));
    }

    public static void PressKey(string key, string[] modifiers, int repeat) {
        var modVks = new List<ushort>();
        if (modifiers != null) {
            foreach (var m in modifiers) {
                var vk = MapKey(m);
                modVks.Add(vk);
                KeyEvent(vk, false);
            }
        }
        if (!string.IsNullOrEmpty(key)) {
            ushort vk = MapKey(key);
            for (int i = 0; i < Math.Max(1, repeat); i++) {
                KeyEvent(vk, false);
                KeyEvent(vk, true);
                if (i + 1 < repeat) Thread.Sleep(25);
            }
        }
        for (int i = modVks.Count - 1; i >= 0; i--) KeyEvent(modVks[i], true);
    }

    private static bool IsInteractiveUia(string role) {
        string r = (role ?? "").ToLowerInvariant();
        return r.Contains("button") || r.Contains("edit") || r.Contains("document") ||
               r.Contains("check") || r.Contains("radio") || r.Contains("combo") ||
               r.Contains("menu") || r.Contains("tab") || r.Contains("link") ||
               r.Contains("hyperlink") || r.Contains("slider") || r.Contains("list") ||
               r.Contains("tree");
    }

    public static Dictionary<string, object> GetUiTree(string appName, int pid, int maxDepth, int maxNodes, bool interactiveOnly) {
        IntPtr hWnd = ResolveWindow(0, appName, null, pid);
        if (hWnd == IntPtr.Zero) hWnd = GetForegroundWindow();
        if (hWnd == IntPtr.Zero) throw new Exception("No active window found for UI tree.");

        var root = AutomationElement.FromHandle(hWnd);
        var elements = new List<Dictionary<string, object>>();
        var walker = TreeWalker.ControlViewWalker;

        Action<AutomationElement, int> walk = null;
        walk = (el, depth) => {
            if (elements.Count >= maxNodes || depth > maxDepth || el == null) return;
            try {
                var cur = el.Current;
                string role = cur.ControlType != null ? cur.ControlType.ProgrammaticName.Replace("ControlType.", "") : "";
                string title = cur.Name ?? "";
                string autoId = cur.AutomationId ?? "";
                string val = "";
                try {
                    object patternObj;
                    if (el.TryGetCurrentPattern(ValuePattern.Pattern, out patternObj)) {
                        val = ((ValuePattern)patternObj).Current.Value ?? "";
                    }
                } catch {}

                var rect = cur.BoundingRectangle;
                bool hasRect = !rect.IsEmpty && !double.IsInfinity(rect.Width) && rect.Width > 0 && rect.Height > 0;
                bool include = !interactiveOnly || IsInteractiveUia(role);

                if (include && hasRect && (!string.IsNullOrEmpty(title) || !string.IsNullOrEmpty(val) || IsInteractiveUia(role))) {
                    int rx = (int)Math.Round(rect.X);
                    int ry = (int)Math.Round(rect.Y);
                    int rw = (int)Math.Round(rect.Width);
                    int rh = (int)Math.Round(rect.Height);
                    elements.Add(new Dictionary<string, object> {
                        { "depth", depth },
                        { "role", role },
                        { "title", title },
                        { "value", val },
                        { "identifier", autoId },
                        { "enabled", cur.IsEnabled },
                        { "focused", cur.HasKeyboardFocus },
                        { "bounds", new Dictionary<string, object> { { "x", rx }, { "y", ry }, { "width", rw }, { "height", rh } } },
                        { "cx", rx + rw / 2 },
                        { "cy", ry + rh / 2 }
                    });
                }

                if (depth < maxDepth && elements.Count < maxNodes) {
                    var child = walker.GetFirstChild(el);
                    while (child != null && elements.Count < maxNodes) {
                        walk(child, depth + 1);
                        child = walker.GetNextSibling(child);
                    }
                }
            } catch {}
        };

        walk(root, 0);
        uint tPid = 0;
        GetWindowThreadProcessId(hWnd, out tPid);
        return new Dictionary<string, object> {
            { "target", new Dictionary<string, object> {
                { "window_id", hWnd.ToInt64() },
                { "pid", (int)tPid },
                { "title", ReadWindowText(hWnd) }
            }},
            { "elements", elements }
        };
    }
}
'@

Add-Type -TypeDefinition $csharpSource -ReferencedAssemblies @(
    "System.Windows.Forms",
    "System.Drawing",
    "UIAutomationClient",
    "UIAutomationTypes"
)
[ComputerUseWin]::InitDpi()

function ConvertTo-StringArray($val) {
    if ($null -eq $val) { return @() }
    return @($val | ForEach-Object { [string]$_ })
}

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $trimmed = $line.Trim()
    if (-not $trimmed) { continue }

    $req = $null
    try {
        $req = $trimmed | ConvertFrom-Json
        $id = $req.id
        $action = [string]$req.action
        $p = $req.params
        if ($null -eq $p) { $p = [PSCustomObject]@{} }

        $result = $null
        switch ($action) {
            "get_system_info" {
                $screen = [ComputerUseWin]::GetScreenInfo()
                $result = @{
                    os = "windows"
                    arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
                    hostname = $env:COMPUTERNAME
                    user = $env:USERNAME
                    driver = "win32_powershell_uia"
                    dpi_aware = [ComputerUseWin]::DpiAwareInitialized
                    is_elevated = [ComputerUseWin]::IsElevated()
                    displays_count = $screen.displays.Count
                    cursor = $screen.cursor
                    frontmost_window = $screen.frontmost_window
                }
            }
            "check_permissions" {
                $elevated = [ComputerUseWin]::IsElevated()
                $result = @{
                    os = "windows"
                    screen_recording = $true
                    accessibility = $true
                    dpi_aware = [ComputerUseWin]::DpiAwareInitialized
                    is_elevated = $elevated
                    uipi_note = if ($elevated) { "Running elevated; can control both standard and elevated windows." } else { "Running at standard user privilege; UIPI blocks input to Administrator-elevated windows." }
                }
            }
            "get_screen_info" {
                $result = [ComputerUseWin]::GetScreenInfo()
            }
            "screenshot" {
                $hasDisplay = $null -ne $p.display_id
                $dispId = if ($hasDisplay) { [int]$p.display_id } else { 0 }
                $hasReg = $null -ne $p.region
                $rx = if ($hasReg) { [int]$p.region.x } else { 0 }
                $ry = if ($hasReg) { [int]$p.region.y } else { 0 }
                $rw = if ($hasReg) { [int]$p.region.width } else { 0 }
                $rh = if ($hasReg) { [int]$p.region.height } else { 0 }
                $winId = if ($null -ne $p.window_id) { [long]$p.window_id } else { 0L }
                $appName = if ($null -ne $p.app_name) { [string]$p.app_name } else { $null }
                $incCursor = if ($null -ne $p.include_cursor) { [bool]$p.include_cursor } else { $true }
                $grid = if ($null -ne $p.grid) { [bool]$p.grid } else { $false }
                $maxW = if ($null -ne $p.max_width) { [int]$p.max_width } else { 1440 }
                $fmt = if ($null -ne $p.format) { [string]$p.format } else { "jpeg" }
                $qual = if ($null -ne $p.quality) { [int]$p.quality } else { 82 }
                $savePath = if ($null -ne $p.save_path) { [string]$p.save_path } else { $null }
                $result = [ComputerUseWin]::CaptureScreenshot($dispId, $hasDisplay, $rx, $ry, $rw, $rh, $hasReg, $winId, $appName, $incCursor, $grid, $maxW, $fmt, $qual, $savePath)
            }
            "mouse_move" {
                $dur = if ($null -ne $p.duration_ms) { [int]$p.duration_ms } else { 0 }
                [ComputerUseWin]::MoveMouse([int]$p.x, [int]$p.y, $dur)
                $result = @{ ok = $true; x = [int]$p.x; y = [int]$p.y }
            }
            "mouse_click" {
                $hasPos = ($null -ne $p.x) -and ($null -ne $p.y)
                $x = if ($hasPos) { [int]$p.x } else { 0 }
                $y = if ($hasPos) { [int]$p.y } else { 0 }
                $btn = if ($null -ne $p.button) { [string]$p.button } else { "left" }
                $cnt = if ($null -ne $p.click_count) { [int]$p.click_count } else { 1 }
                $mods = ConvertTo-StringArray $p.modifiers
                [ComputerUseWin]::MouseClick($x, $y, $hasPos, $btn, $cnt, $mods)
                $result = @{ ok = $true }
            }
            "mouse_down" {
                $hasPos = ($null -ne $p.x) -and ($null -ne $p.y)
                [ComputerUseWin]::MouseButton($(if ($hasPos) { [int]$p.x } else { 0 }), $(if ($hasPos) { [int]$p.y } else { 0 }), $hasPos, $(if ($p.button) { [string]$p.button } else { "left" }), $true)
                $result = @{ ok = $true }
            }
            "mouse_up" {
                $hasPos = ($null -ne $p.x) -and ($null -ne $p.y)
                [ComputerUseWin]::MouseButton($(if ($hasPos) { [int]$p.x } else { 0 }), $(if ($hasPos) { [int]$p.y } else { 0 }), $hasPos, $(if ($p.button) { [string]$p.button } else { "left" }), $false)
                $result = @{ ok = $true }
            }
            "mouse_drag" {
                $btn = if ($p.button) { [string]$p.button } else { "left" }
                $dur = if ($null -ne $p.duration_ms) { [int]$p.duration_ms } else { 250 }
                $steps = if ($null -ne $p.steps) { [int]$p.steps } else { 15 }
                [ComputerUseWin]::MouseDrag([int]$p.start_x, [int]$p.start_y, [int]$p.end_x, [int]$p.end_y, $btn, $dur, $steps)
                $result = @{ ok = $true }
            }
            "mouse_scroll" {
                $hasPos = ($null -ne $p.x) -and ($null -ne $p.y)
                $dx = if ($null -ne $p.delta_x) { [int]$p.delta_x } else { 0 }
                $dy = if ($null -ne $p.delta_y) { [int]$p.delta_y } else { 0 }
                [ComputerUseWin]::MouseScroll($(if ($hasPos) { [int]$p.x } else { 0 }), $(if ($hasPos) { [int]$p.y } else { 0 }), $hasPos, $dx, $dy)
                $result = @{ ok = $true }
            }
            "type_text" {
                $delay = if ($null -ne $p.delay_ms) { [int]$p.delay_ms } else { 0 }
                [ComputerUseWin]::TypeUnicode([string]$p.text, $delay)
                $result = @{ ok = $true; length = ([string]$p.text).Length }
            }
            "press_key" {
                $mods = ConvertTo-StringArray $p.modifiers
                $rep = if ($null -ne $p.repeat) { [int]$p.repeat } else { 1 }
                [ComputerUseWin]::PressKey([string]$p.key, $mods, $rep)
                $result = @{ ok = $true }
            }
            "hotkey" {
                $mods = ConvertTo-StringArray $p.modifiers
                $key = if ($null -ne $p.key) { [string]$p.key } else { "" }
                [ComputerUseWin]::PressKey($key, $mods, 1)
                $result = @{ ok = $true }
            }
            "key_down" {
                [ComputerUseWin]::KeyEvent([ComputerUseWin]::MapKey([string]$p.key), $false)
                $result = @{ ok = $true }
            }
            "key_up" {
                [ComputerUseWin]::KeyEvent([ComputerUseWin]::MapKey([string]$p.key), $true)
                $result = @{ ok = $true }
            }
            "get_ui_tree" {
                $appName = if ($null -ne $p.app_name) { [string]$p.app_name } else { $null }
                $pidVal = if ($null -ne $p.pid) { [int]$p.pid } else { 0 }
                $maxDepth = if ($null -ne $p.max_depth) { [int]$p.max_depth } else { 5 }
                $maxNodes = if ($null -ne $p.max_nodes) { [int]$p.max_nodes } else { 200 }
                $interOnly = if ($null -ne $p.interactive_only) { [bool]$p.interactive_only } else { $false }
                $result = [ComputerUseWin]::GetUiTree($appName, $pidVal, $maxDepth, $maxNodes, $interOnly)
            }
            "list_windows" {
                $appName = if ($null -ne $p.app_name) { [string]$p.app_name } else { $null }
                $incMin = if ($null -ne $p.include_minimized) { [bool]$p.include_minimized } else { $true }
                $result = [ComputerUseWin]::ListWindows($appName, $incMin)
            }
            "focus_window" {
                $winId = if ($null -ne $p.window_id) { [long]$p.window_id } else { 0L }
                $appName = if ($null -ne $p.app_name) { [string]$p.app_name } else { $null }
                $title = if ($null -ne $p.title_contains) { [string]$p.title_contains } else { $null }
                $pidVal = if ($null -ne $p.pid) { [int]$p.pid } else { 0 }
                $result = [ComputerUseWin]::FocusWindow($winId, $appName, $title, $pidVal)
            }
            "manage_window" {
                $winId = if ($null -ne $p.window_id) { [long]$p.window_id } else { 0L }
                $appName = if ($null -ne $p.app_name) { [string]$p.app_name } else { $null }
                $title = if ($null -ne $p.title_contains) { [string]$p.title_contains } else { $null }
                $hasX = $null -ne $p.x; $hasY = $null -ne $p.y; $hasW = $null -ne $p.width; $hasH = $null -ne $p.height
                $result = [ComputerUseWin]::ManageWindow([string]$p.action, $winId, $appName, $title, $(if ($hasX) { [int]$p.x } else { 0 }), $(if ($hasY) { [int]$p.y } else { 0 }), $(if ($hasW) { [int]$p.width } else { 0 }), $(if ($hasH) { [int]$p.height } else { 0 }), $hasX, $hasY, $hasW, $hasH)
            }
            "list_running_apps" {
                $apps = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
                    @{ pid = $_.Id; name = $_.ProcessName; title = $_.MainWindowTitle }
                }
                $result = @($apps)
            }
            "launch_app" {
                $target = [string]$p.target
                $psi = [System.Diagnostics.ProcessStartInfo]::new($target)
                $psi.UseShellExecute = $true
                if ($null -ne $p.args -and $p.args.Count -gt 0) {
                    $psi.Arguments = (($p.args | ForEach-Object { [string]$_ }) -join " ")
                }
                $started = [System.Diagnostics.Process]::Start($psi)
                $result = @{ launched = $true; target = $target; pid = if ($started) { $started.Id } else { $null } }
            }
            "clipboard_read" {
                $hasText = [System.Windows.Forms.Clipboard]::ContainsText()
                $text = if ($hasText) { [System.Windows.Forms.Clipboard]::GetText() } else { "" }
                $result = @{ has_text = $hasText; text = $text }
            }
            "clipboard_write" {
                [System.Windows.Forms.Clipboard]::SetText([string]$p.text)
                $result = @{ ok = $true; length = ([string]$p.text).Length }
            }
            default {
                throw "Unknown Windows worker action: $action"
            }
        }

        $resp = @{ id = $id; ok = $true; result = $result } | ConvertTo-Json -Depth 12 -Compress
        [Console]::Out.WriteLine($resp)
    } catch {
        $errId = if ($null -ne $req -and $null -ne $req.id) { $req.id } else { 0 }
        $errResp = @{ id = $errId; ok = $false; error = $_.Exception.Message } | ConvertTo-Json -Compress
        [Console]::Out.WriteLine($errResp)
    }
}
