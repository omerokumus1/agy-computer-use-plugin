ObjC.import("Cocoa");
ObjC.import("CoreGraphics");
ObjC.import("ApplicationServices");

const KEY_CODES = {
  a: 0, s: 1, d: 2, f: 3, h: 4, g: 5, z: 6, x: 7,
  c: 8, v: 9, b: 11, q: 12, w: 13, e: 14, r: 15,
  y: 16, t: 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
  "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
  "]": 30, o: 31, u: 32, "[": 33, i: 34, p: 35,
  enter: 36, l: 37, j: 38, "'": 39, k: 40, ";": 41, "\\": 42,
  ",": 43, "/": 44, n: 45, m: 46, ".": 47, tab: 48, space: 49,
  "`": 50, backspace: 51, escape: 53,
  cmd: 55, shift: 56, capslock: 57, alt: 58, ctrl: 59,
  f5: 96, f6: 97, f7: 98, f3: 99, f8: 100, f9: 101,
  f11: 103, f10: 109, f12: 111, home: 115, pageup: 116,
  delete: 117, f4: 118, end: 119, f2: 120, pagedown: 121,
  f1: 122, left: 123, right: 124, down: 125, up: 126
};

function maskForModifiers(mods) {
  let mask = 0;
  for (const m of mods || []) {
    const l = m.toLowerCase();
    if (l === "cmd" || l === "command" || l === "meta") mask |= $.kCGEventFlagMaskCommand;
    else if (l === "ctrl" || l === "control") mask |= $.kCGEventFlagMaskControl;
    else if (l === "alt" || l === "option") mask |= $.kCGEventFlagMaskAlternate;
    else if (l === "shift") mask |= $.kCGEventFlagMaskShift;
  }
  return mask;
}

function getDisplays() {
  const screens = $.NSScreen.screens;
  const mainFrame = screens.objectAtIndex(0).frame;
  const primaryH = mainFrame.size.height;
  const out = [];
  for (let i = 0; i < screens.count; i++) {
    const s = screens.objectAtIndex(i);
    const f = s.frame;
    const vf = s.visibleFrame;
    const yTop = primaryH - (f.origin.y + f.size.height);
    const vyTop = primaryH - (vf.origin.y + vf.size.height);
    out.push({
      id: i,
      primary: i === 0,
      x: Math.round(f.origin.x),
      y: Math.round(yTop),
      width: Math.round(f.size.width),
      height: Math.round(f.size.height),
      scale: s.backingScaleFactor,
      work_area: {
        x: Math.round(vf.origin.x),
        y: Math.round(vyTop),
        width: Math.round(vf.size.width),
        height: Math.round(vf.size.height)
      }
    });
  }
  return out;
}

function getCursor() {
  const ev = $.CGEventCreate($());
  const pt = $.CGEventGetLocation(ev);
  return { x: Math.round(pt.x), y: Math.round(pt.y) };
}

function listWindows(appFilter, includeMinimized) {
  const opts = includeMinimized
    ? $.kCGWindowListExcludeDesktopElements
    : ($.kCGWindowListOptionOnScreenOnly | $.kCGWindowListExcludeDesktopElements);
  const raw = $.CGWindowListCopyWindowInfo(opts, $.kCGNullWindowID);
  const wins = ObjC.deepUnwrap(ObjC.castRefToObject(raw)) || [];
  const frontPid = $.NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier;
  const out = [];
  let seenFront = false;

  for (const w of wins) {
    if ((w.kCGWindowLayer || 0) !== 0) continue;
    const owner = w.kCGWindowOwnerName || "";
    const title = w.kCGWindowName || "";
    const pid = w.kCGWindowOwnerPID || 0;
    const onScreen = Boolean(w.kCGWindowIsOnscreen);
    const alpha = w.kCGWindowAlpha !== undefined ? w.kCGWindowAlpha : 1;
    if (alpha <= 0.01) continue;
    if (!includeMinimized && !onScreen) continue;
    const b = w.kCGWindowBounds || {};
    if ((b.Width || 0) <= 60 && (b.Height || 0) <= 60) continue;
    if ((b.Height || 0) <= 28 && (b.Width || 0) >= 800 && !title) continue;
    if (!title && !onScreen) continue;
    if (appFilter) {
      const f = appFilter.toLowerCase();
      if (!owner.toLowerCase().includes(f) && !title.toLowerCase().includes(f)) continue;
    }
    let focused = false;
    if (pid === frontPid && onScreen && !seenFront) {
      focused = true;
      seenFront = true;
    }
    out.push({
      window_id: w.kCGWindowNumber,
      title,
      app_name: owner,
      pid,
      focused,
      minimized: !onScreen,
      bounds: {
        x: Math.round(b.X),
        y: Math.round(b.Y),
        width: Math.round(b.Width),
        height: Math.round(b.Height)
      }
    });
  }
  return out;
}

function postMouse(type, x, y, btn, clickCount, mask) {
  const ev = $.CGEventCreateMouseEvent($(), type, { x, y }, btn);
  if (clickCount > 1) $.CGEventSetIntegerValueField(ev, $.kCGMouseEventClickState, clickCount);
  if (mask) $.CGEventSetFlags(ev, mask);
  $.CGEventPost($.kCGHIDEventTap, ev);
}

function btnTuple(btn) {
  const b = (btn || "left").toLowerCase();
  if (b === "right") return [$.kCGMouseButtonRight, $.kCGEventRightMouseDown, $.kCGEventRightMouseUp, $.kCGEventRightMouseDragged];
  if (b === "middle") return [$.kCGMouseButtonCenter, $.kCGEventOtherMouseDown, $.kCGEventOtherMouseUp, $.kCGEventOtherMouseDragged];
  return [$.kCGMouseButtonLeft, $.kCGEventLeftMouseDown, $.kCGEventLeftMouseUp, $.kCGEventLeftMouseDragged];
}

function run(argv) {
  const payload = JSON.parse(argv[0]);
  const action = payload.action;
  const p = payload.params || {};

  switch (action) {
    case "get_system_info": {
      const front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
      return JSON.stringify({
        os: "macos",
        driver: "macos_jxa_fallback",
        displays_count: $.NSScreen.screens.count,
        cursor: getCursor(),
        frontmost_window: {
          app_name: ObjC.unwrap(front.localizedName),
          bundle_id: ObjC.unwrap(front.bundleIdentifier),
          pid: front.processIdentifier
        }
      });
    }
    case "check_permissions": {
      return JSON.stringify({
        os: "macos",
        accessibility: $.AXIsProcessTrusted(),
        screen_recording: Boolean($.CGPreflightScreenCaptureAccess()),
        remediation: "Grant Screen Recording and Accessibility permissions in System Settings -> Privacy & Security."
      });
    }
    case "get_screen_info": {
      const front = $.NSWorkspace.sharedWorkspace.frontmostApplication;
      return JSON.stringify({
        coordinate_space: "coregraphics_logical_points",
        displays: getDisplays(),
        cursor: getCursor(),
        frontmost_window: {
          app_name: ObjC.unwrap(front.localizedName),
          bundle_id: ObjC.unwrap(front.bundleIdentifier),
          pid: front.processIdentifier
        }
      });
    }
    case "list_windows":
      return JSON.stringify(listWindows(p.app_name || null, p.include_minimized !== false));
    case "list_running_apps": {
      const apps = $.NSWorkspace.sharedWorkspace.runningApplications;
      const out = [];
      for (let i = 0; i < apps.count; i++) {
        const a = apps.objectAtIndex(i);
        if (a.activationPolicy !== $.NSApplicationActivationPolicyRegular) continue;
        out.push({
          pid: a.processIdentifier,
          name: ObjC.unwrap(a.localizedName) || "",
          bundle_id: ObjC.unwrap(a.bundleIdentifier) || "",
          active: Boolean(a.active)
        });
      }
      return JSON.stringify(out);
    }
    case "mouse_move": {
      postMouse($.kCGEventMouseMoved, p.x, p.y, $.kCGMouseButtonLeft, 1, 0);
      return JSON.stringify({ ok: true, x: p.x, y: p.y });
    }
    case "mouse_click": {
      const cur = getCursor();
      const x = p.x !== undefined ? p.x : cur.x;
      const y = p.y !== undefined ? p.y : cur.y;
      const [btn, downT, upT] = btnTuple(p.button);
      const count = p.click_count || 1;
      const mask = maskForModifiers(p.modifiers);
      postMouse($.kCGEventMouseMoved, x, y, btn, 1, 0);
      delay(0.01);
      for (let c = 1; c <= count; c++) {
        postMouse(downT, x, y, btn, c, mask);
        delay(0.01);
        postMouse(upT, x, y, btn, c, mask);
        if (c < count) delay(0.035);
      }
      return JSON.stringify({ ok: true });
    }
    case "mouse_down": {
      const cur = getCursor();
      const [btn, downT] = btnTuple(p.button);
      postMouse(downT, p.x !== undefined ? p.x : cur.x, p.y !== undefined ? p.y : cur.y, btn, 1, 0);
      return JSON.stringify({ ok: true });
    }
    case "mouse_up": {
      const cur = getCursor();
      const [btn, , upT] = btnTuple(p.button);
      postMouse(upT, p.x !== undefined ? p.x : cur.x, p.y !== undefined ? p.y : cur.y, btn, 1, 0);
      return JSON.stringify({ ok: true });
    }
    case "mouse_drag": {
      const [btn, downT, upT, dragT] = btnTuple(p.button);
      const steps = Math.max(2, Math.min(100, p.steps || 15));
      const stepWait = Math.max(0.002, ((p.duration_ms || 250) / 1000) / steps);
      postMouse($.kCGEventMouseMoved, p.start_x, p.start_y, btn, 1, 0);
      delay(0.015);
      postMouse(downT, p.start_x, p.start_y, btn, 1, 0);
      for (let i = 1; i <= steps; i++) {
        const t = i / steps;
        postMouse(dragT, p.start_x + (p.end_x - p.start_x) * t, p.start_y + (p.end_y - p.start_y) * t, btn, 1, 0);
        delay(stepWait);
      }
      postMouse(upT, p.end_x, p.end_y, btn, 1, 0);
      return JSON.stringify({ ok: true });
    }
    case "mouse_scroll": {
      const cur = getCursor();
      const x = p.x !== undefined ? p.x : cur.x;
      const y = p.y !== undefined ? p.y : cur.y;
      postMouse($.kCGEventMouseMoved, x, y, $.kCGMouseButtonLeft, 1, 0);
      const ev = $.CGEventCreateScrollWheelEvent($(), $.kCGScrollEventUnitLine, 2, (p.delta_y || 0) * 3, -(p.delta_x || 0) * 3);
      $.CGEventPost($.kCGHIDEventTap, ev);
      return JSON.stringify({ ok: true });
    }
    case "press_key":
    case "hotkey": {
      const key = (p.key || "").toLowerCase();
      const mask = maskForModifiers(p.modifiers);
      const rep = p.repeat || 1;
      const code = KEY_CODES[key];
      if (code === undefined) throw new Error("Unsupported macOS key in JXA fallback: " + key);
      for (let i = 0; i < rep; i++) {
        const down = $.CGEventCreateKeyboardEvent($(), code, true);
        const up = $.CGEventCreateKeyboardEvent($(), code, false);
        if (mask) { $.CGEventSetFlags(down, mask); $.CGEventSetFlags(up, mask); }
        $.CGEventPost($.kCGHIDEventTap, down);
        delay(0.01);
        $.CGEventPost($.kCGHIDEventTap, up);
      }
      return JSON.stringify({ ok: true });
    }
    case "key_down":
    case "key_up": {
      const code = KEY_CODES[(p.key || "").toLowerCase()];
      if (code === undefined) throw new Error("Unsupported key: " + p.key);
      const ev = $.CGEventCreateKeyboardEvent($(), code, action === "key_down");
      $.CGEventPost($.kCGHIDEventTap, ev);
      return JSON.stringify({ ok: true });
    }
    case "focus_window": {
      const wins = listWindows(null, true);
      const match = wins.find(w => {
        if (p.window_id && w.window_id !== p.window_id) return false;
        if (p.pid && w.pid !== p.pid) return false;
        if (p.app_name && !w.app_name.toLowerCase().includes(p.app_name.toLowerCase())) return false;
        if (p.title_contains && !w.title.toLowerCase().includes(p.title_contains.toLowerCase())) return false;
        return true;
      });
      if (!match) throw new Error("Window not found.");
      const app = $.NSRunningApplication.runningApplicationWithProcessIdentifier(match.pid);
      app.activateWithOptions($.NSApplicationActivateIgnoringOtherApps | $.NSApplicationActivateAllWindows);
      return JSON.stringify({ focused: true, window_id: match.window_id, app_name: match.app_name });
    }
    default:
      throw new Error("Unsupported JXA fallback action: " + action);
  }
}
