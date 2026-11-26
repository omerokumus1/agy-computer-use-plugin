import Cocoa
import CoreGraphics
import ApplicationServices
import Foundation
import ImageIO

// MARK: - JSON Helpers

func jsonOut(_ obj: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: []),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func okOut(_ id: Int, _ result: Any) {
    jsonOut(["id": id, "ok": true, "result": result])
}

func errOut(_ id: Int, _ message: String) {
    jsonOut(["id": id, "ok": false, "error": message])
}

// MARK: - Key Mapping

let KEY_CODES: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7,
    "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15,
    "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22,
    "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29,
    "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "enter": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42,
    ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49,
    "`": 50, "backspace": 51, "escape": 53,
    "cmd": 55, "shift": 56, "capslock": 57, "alt": 58, "ctrl": 59,
    "f17": 64, "f18": 79, "f19": 80, "f20": 90,
    "f5": 96, "f6": 97, "f7": 98, "f3": 99, "f8": 100, "f9": 101,
    "f11": 103, "f10": 109, "f12": 111, "home": 115, "pageup": 116,
    "delete": 117, "f4": 118, "end": 119, "f2": 120, "pagedown": 121,
    "f1": 122, "left": 123, "right": 124, "down": 125, "up": 126
]

func modifierFlags(_ modifiers: [String]) -> CGEventFlags {
    var flags: CGEventFlags = []
    for m in modifiers {
        switch m.lowercased() {
        case "cmd", "command", "meta", "win": flags.insert(.maskCommand)
        case "ctrl", "control": flags.insert(.maskControl)
        case "alt", "option": flags.insert(.maskAlternate)
        case "shift": flags.insert(.maskShift)
        default: break
        }
    }
    return flags
}

// MARK: - Displays & Windows

func getDisplays() -> [[String: Any]] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)

    let nsScreens = NSScreen.screens
    let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height

    var out: [[String: Any]] = []
    for (idx, did) in ids.enumerated() {
        let bounds = CGDisplayBounds(did)
        var scale: Double = 1.0
        var workArea: [String: Any] = [
            "x": Int(bounds.origin.x),
            "y": Int(bounds.origin.y),
            "width": Int(bounds.size.width),
            "height": Int(bounds.size.height)
        ]

        for s in nsScreens {
            if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
               CGDirectDisplayID(num.uint32Value) == did {
                scale = Double(s.backingScaleFactor)
                let vf = s.visibleFrame
                let topY = primaryHeight - (vf.origin.y + vf.size.height)
                workArea = [
                    "x": Int(vf.origin.x),
                    "y": Int(topY),
                    "width": Int(vf.size.width),
                    "height": Int(vf.size.height)
                ]
                break
            }
        }

        out.append([
            "id": idx,
            "cg_display_id": Int(did),
            "primary": CGDisplayIsMain(did) != 0,
            "x": Int(bounds.origin.x),
            "y": Int(bounds.origin.y),
            "width": Int(bounds.size.width),
            "height": Int(bounds.size.height),
            "scale": scale,
            "work_area": workArea
        ])
    }
    return out
}

func getCursorPos() -> [String: Any] {
    let loc = CGEvent(source: nil)?.location ?? .zero
    return ["x": Int(round(loc.x)), "y": Int(round(loc.y))]
}

func listWindows(appFilter: String?, includeMinimized: Bool) -> [[String: Any]] {
    let options: CGWindowListOption = includeMinimized
        ? [.excludeDesktopElements]
        : [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    var results: [[String: Any]] = []
    var seenFirstForFront = false

    for w in list {
        let layer = (w[kCGWindowLayer as String] as? Int) ?? 0
        if layer != 0 { continue }
        let owner = (w[kCGWindowOwnerName as String] as? String) ?? ""
        let title = (w[kCGWindowName as String] as? String) ?? ""
        let pid = (w[kCGWindowOwnerPID as String] as? Int32) ?? 0
        let winId = (w[kCGWindowNumber as String] as? Int) ?? 0
        let onScreen = (w[kCGWindowIsOnscreen as String] as? Bool) ?? false
        let alpha = (w[kCGWindowAlpha as String] as? Double) ?? 1.0

        if alpha <= 0.01 { continue }
        if !includeMinimized && !onScreen { continue }
        guard let bDict = w[kCGWindowBounds as String] as? [String: Any],
              let bx = bDict["X"] as? Double,
              let by = bDict["Y"] as? Double,
              let bw = bDict["Width"] as? Double,
              let bh = bDict["Height"] as? Double else { continue }
        if bw <= 60 && bh <= 60 { continue }
        if bh <= 28 && bw >= 800 && title.isEmpty { continue }
        if title.isEmpty && !onScreen { continue }

        if let f = appFilter, !f.isEmpty {
            let matchesOwner = owner.range(of: f, options: .caseInsensitive) != nil
            let matchesTitle = title.range(of: f, options: .caseInsensitive) != nil
            if !matchesOwner && !matchesTitle { continue }
        }

        var focused = false
        if pid == frontPid && onScreen && !seenFirstForFront {
            focused = true
            seenFirstForFront = true
        }

        results.append([
            "window_id": winId,
            "title": title,
            "app_name": owner,
            "pid": Int(pid),
            "focused": focused,
            "minimized": !onScreen,
            "bounds": [
                "x": Int(round(bx)),
                "y": Int(round(by)),
                "width": Int(round(bw)),
                "height": Int(round(bh))
            ]
        ])
    }
    return results
}

func getFrontmostSummary() -> [String: Any]? {
    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
    let pid = app.processIdentifier
    let wins = listWindows(appFilter: nil, includeMinimized: false)
    let firstWin = wins.first(where: { ($0["pid"] as? Int) == Int(pid) })
    return [
        "window_id": firstWin?["window_id"] ?? 0,
        "title": firstWin?["title"] ?? "",
        "app_name": app.localizedName ?? "",
        "bundle_id": app.bundleIdentifier ?? "",
        "pid": Int(pid)
    ]
}

// MARK: - Screenshot via screencapture + ImageIO/CGContext

func drawGridOverlay(on ctx: CGContext, pixelW: Int, pixelH: Int, bounds: CGRect) {
    let scaleX = Double(pixelW) / Double(bounds.width)
    let scaleY = Double(pixelH) / Double(bounds.height)

    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1.0, green: 0.25, blue: 0.25, alpha: 0.55))
    ctx.setLineWidth(max(1.0, scaleX))

    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: max(11.0, 12.0 * scaleX), weight: .bold),
        .foregroundColor: NSColor.white,
        .backgroundColor: NSColor(calibratedWhite: 0.0, alpha: 0.72)
    ]

    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    var gx: Double = 0
    while gx < Double(bounds.width) {
        let px = gx * scaleX
        ctx.move(to: CGPoint(x: px, y: 0))
        ctx.addLine(to: CGPoint(x: px, y: Double(pixelH)))
        ctx.strokePath()
        let label = "\(Int(round(bounds.origin.x + gx)))" as NSString
        label.draw(at: NSPoint(x: px + 3, y: Double(pixelH) - 22.0 * scaleY), withAttributes: attrs)
        gx += 200
    }

    var gy: Double = 200
    while gy < Double(bounds.height) {
        let py = Double(pixelH) - gy * scaleY
        ctx.move(to: CGPoint(x: 0, y: py))
        ctx.addLine(to: CGPoint(x: Double(pixelW), y: py))
        ctx.strokePath()
        let label = "\(Int(round(bounds.origin.y + gy)))" as NSString
        label.draw(at: NSPoint(x: 4, y: py - 18.0 * scaleY), withAttributes: attrs)
        gy += 200
    }

    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
}

func captureScreenshot(_ p: [String: Any]) throws -> [String: Any] {
    let displays = getDisplays()
    var captureRect: CGRect
    var windowIdToCapture: Int? = nil

    if let wid = p["window_id"] as? Int, wid > 0 {
        let wins = listWindows(appFilter: nil, includeMinimized: true)
        guard let w = wins.first(where: { ($0["window_id"] as? Int) == wid }),
              let b = w["bounds"] as? [String: Int] else {
            throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "Window \(wid) not found."])
        }
        windowIdToCapture = wid
        captureRect = CGRect(x: b["x"] ?? 0, y: b["y"] ?? 0, width: b["width"] ?? 100, height: b["height"] ?? 100)
    } else if let appName = p["app_name"] as? String, !appName.isEmpty {
        let wins = listWindows(appFilter: appName, includeMinimized: false)
        guard let w = wins.first,
              let wid = w["window_id"] as? Int,
              let b = w["bounds"] as? [String: Int] else {
            throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "No visible window found for app '\(appName)'."])
        }
        windowIdToCapture = wid
        captureRect = CGRect(x: b["x"] ?? 0, y: b["y"] ?? 0, width: b["width"] ?? 100, height: b["height"] ?? 100)
    } else if let reg = p["region"] as? [String: Any],
              let rx = reg["x"] as? Double, let ry = reg["y"] as? Double,
              let rw = reg["width"] as? Double, let rh = reg["height"] as? Double {
        captureRect = CGRect(x: rx, y: ry, width: max(1, rw), height: max(1, rh))
    } else if let did = p["display_id"] as? Int {
        guard did >= 0 && did < displays.count else {
            throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid display_id \(did)."])
        }
        let d = displays[did]
        captureRect = CGRect(
            x: Double(d["x"] as? Int ?? 0),
            y: Double(d["y"] as? Int ?? 0),
            width: Double(d["width"] as? Int ?? 1280),
            height: Double(d["height"] as? Int ?? 800)
        )
    } else {
        let primary = displays.first(where: { ($0["primary"] as? Bool) == true }) ?? displays[0]
        captureRect = CGRect(
            x: Double(primary["x"] as? Int ?? 0),
            y: Double(primary["y"] as? Int ?? 0),
            width: Double(primary["width"] as? Int ?? 1280),
            height: Double(primary["height"] as? Int ?? 800)
        )
    }

    let tmpPath = NSTemporaryDirectory() + "cu_shot_\(UUID().uuidString).png"
    defer { try? FileManager.default.removeItem(atPath: tmpPath) }

    var scArgs = ["-x"]
    if (p["include_cursor"] as? Bool) ?? true {
        scArgs.append("-C")
    }
    if let wid = windowIdToCapture {
        scArgs.append(contentsOf: ["-l", "\(wid)", "-o", tmpPath])
    } else {
        scArgs.append(contentsOf: ["-R", "\(Int(captureRect.origin.x)),\(Int(captureRect.origin.y)),\(Int(captureRect.size.width)),\(Int(captureRect.size.height))", tmpPath])
    }

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = scArgs
    let errPipe = Pipe()
    proc.standardError = errPipe
    try proc.run()
    proc.waitUntilExit()

    guard proc.terminationStatus == 0,
          let srcData = try? Data(contentsOf: URL(fileURLWithPath: tmpPath)),
          let imgSrc = CGImageSourceCreateWithData(srcData as CFData, nil),
          let cgImg = CGImageSourceCreateImageAtIndex(imgSrc, 0, nil) else {
        let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw NSError(domain: "ComputerUse", code: 500, userInfo: [NSLocalizedDescriptionKey: "screencapture failed (check Screen Recording permission). \(errText)"])
    }

    let maxWidth = (p["max_width"] as? Int) ?? 1440
    let grid = (p["grid"] as? Bool) ?? false
    let format = ((p["format"] as? String) ?? "jpeg").lowercased()
    let quality = max(10, min(100, (p["quality"] as? Int) ?? 82))

    let origW = cgImg.width
    let origH = cgImg.height
    var outW = origW
    var outH = origH
    if maxWidth > 0 && origW > maxWidth {
        outW = maxWidth
        outH = max(1, Int(round(Double(origH) * (Double(maxWidth) / Double(origW)))))
    }

    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: outW,
        height: outH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "ComputerUse", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create CGContext."])
    }

    ctx.interpolationQuality = .high
    ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
    if grid {
        drawGridOverlay(on: ctx, pixelW: outW, pixelH: outH, bounds: captureRect)
    }

    guard let finalImg = ctx.makeImage() else {
        throw NSError(domain: "ComputerUse", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to render final image."])
    }

    let outData = NSMutableData()
    let uti: CFString = (format == "png") ? ("public.png" as CFString) : ("public.jpeg" as CFString)
    let mime = (format == "png") ? "image/png" : "image/jpeg"
    guard let dest = CGImageDestinationCreateWithData(outData, uti, 1, nil) else {
        throw NSError(domain: "ComputerUse", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create image encoder."])
    }
    let props: [CFString: Any] = format == "png" ? [:] : [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100.0]
    CGImageDestinationAddImage(dest, finalImg, props as CFDictionary)
    CGImageDestinationFinalize(dest)

    let encoded = outData as Data
    if let savePath = p["save_path"] as? String, !savePath.isEmpty {
        try encoded.write(to: URL(fileURLWithPath: savePath))
    }

    return [
        "base64": encoded.base64EncodedString(),
        "mime_type": mime,
        "capture_bounds": [
            "x": Int(round(captureRect.origin.x)),
            "y": Int(round(captureRect.origin.y)),
            "width": Int(round(captureRect.size.width)),
            "height": Int(round(captureRect.size.height))
        ],
        "image_size": ["width": outW, "height": outH]
    ]
}

// MARK: - Mouse & Keyboard

func currentCursorPoint() -> CGPoint {
    return CGEvent(source: nil)?.location ?? .zero
}

func postMouse(_ type: CGEventType, _ pt: CGPoint, _ button: CGMouseButton, clickCount: Int = 1, flags: CGEventFlags = []) {
    if let ev = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: pt, mouseButton: button) {
        if clickCount > 1 {
            ev.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        if !flags.isEmpty {
            ev.flags = flags
        }
        ev.post(tap: .cghidEventTap)
    }
}

func mapMouseButton(_ name: String?) -> (CGMouseButton, CGEventType, CGEventType, CGEventType) {
    switch (name ?? "left").lowercased() {
    case "right": return (.right, .rightMouseDown, .rightMouseUp, .rightMouseDragged)
    case "middle": return (.center, .otherMouseDown, .otherMouseUp, .otherMouseDragged)
    default: return (.left, .leftMouseDown, .leftMouseUp, .leftMouseDragged)
    }
}

func postKey(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
    if let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down) {
        if !flags.isEmpty {
            ev.flags = flags
        }
        ev.post(tap: .cghidEventTap)
    }
}

func typeUnicodeText(_ text: String, delayMs: Int) {
    for ch in text {
        if ch == "\n" {
            postKey(36, down: true)
            postKey(36, down: false)
        } else if ch == "\t" {
            postKey(48, down: true)
            postKey(48, down: false)
        } else if ch != "\r" {
            var utf16 = Array(String(ch).utf16)
            if let downEv = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let upEv = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                downEv.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                upEv.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                downEv.post(tap: .cghidEventTap)
                upEv.post(tap: .cghidEventTap)
            }
        }
        if delayMs > 0 {
            usleep(useconds_t(delayMs * 1000))
        }
    }
}

// MARK: - Accessibility (AXUIElement)

func axAttr(_ el: AXUIElement, _ attr: String) -> AnyObject? {
    var val: AnyObject?
    let err = AXUIElementCopyAttributeValue(el, attr as CFString, &val)
    return err == .success ? val : nil
}

func axString(_ el: AXUIElement, _ attr: String) -> String {
    if let s = axAttr(el, attr) as? String { return s }
    if let n = axAttr(el, attr) as? NSNumber { return n.stringValue }
    return ""
}

func axBool(_ el: AXUIElement, _ attr: String, defaultVal: Bool = false) -> Bool {
    if let n = axAttr(el, attr) as? NSNumber { return n.boolValue }
    return defaultVal
}

func axRect(_ el: AXUIElement) -> CGRect? {
    guard let posVal = axAttr(el, kAXPositionAttribute),
          let sizeVal = axAttr(el, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero
    var sz = CGSize.zero
    guard AXValueGetValue(posVal as! AXValue, .cgPoint, &pt),
          AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz),
          sz.width > 0 && sz.height > 0 else { return nil }
    return CGRect(origin: pt, size: sz)
}

let INTERACTIVE_AX_ROLES: Set<String> = [
    "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea",
    "AXComboBox", "AXPopUpButton", "AXMenuButton", "AXMenuItem", "AXLink",
    "AXSlider", "AXTabGroup", "AXRadioGroup", "AXRow", "AXCell", "AXDisclosureTriangle"
]

func resolveTargetApp(appName: String?, pid: Int?) -> NSRunningApplication? {
    if let p = pid, p > 0 {
        return NSRunningApplication(processIdentifier: pid_t(p))
    }
    if let name = appName, !name.isEmpty {
        return NSWorkspace.shared.runningApplications.first { app in
            (app.localizedName?.range(of: name, options: .caseInsensitive) != nil) ||
            (app.bundleIdentifier?.range(of: name, options: .caseInsensitive) != nil)
        }
    }
    return NSWorkspace.shared.frontmostApplication
}

func requireAccessibility() throws {
    if !AXIsProcessTrusted() {
        throw NSError(
            domain: "ComputerUse",
            code: 403,
            userInfo: [NSLocalizedDescriptionKey: "macOS Accessibility permission is not granted for this process (AXIsProcessTrusted=false). Enable Antigravity (and restart Antigravity if already toggled) under System Settings -> Privacy & Security -> Accessibility."]
        )
    }
}

func getUiTree(appName: String?, pid: Int?, maxDepth: Int, maxNodes: Int, interactiveOnly: Bool) throws -> [String: Any] {
    try requireAccessibility()
    guard let app = resolveTargetApp(appName: appName, pid: pid) else {
        throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target application not found."])
    }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var root: AXUIElement = axApp
    if let focusedWin = axAttr(axApp, kAXFocusedWindowAttribute) {
        root = focusedWin as! AXUIElement
    } else if let wins = axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement], let first = wins.first {
        root = first
    }

    var elements: [[String: Any]] = []

    func walk(_ el: AXUIElement, _ depth: Int) {
        if elements.count >= maxNodes || depth > maxDepth { return }
        let role = axString(el, kAXRoleAttribute)
        let title = axString(el, kAXTitleAttribute)
        let desc = axString(el, kAXDescriptionAttribute)
        let val = axString(el, kAXValueAttribute)
        let ident = axString(el, kAXIdentifierAttribute)
        let rect = axRect(el)
        let isInter = INTERACTIVE_AX_ROLES.contains(role)

        if (!interactiveOnly || isInter), let r = rect {
            if !title.isEmpty || !desc.isEmpty || !val.isEmpty || isInter {
                elements.append([
                    "depth": depth,
                    "role": role,
                    "title": title.isEmpty ? desc : title,
                    "description": desc,
                    "value": val,
                    "identifier": ident,
                    "enabled": axBool(el, kAXEnabledAttribute, defaultVal: true),
                    "focused": axBool(el, kAXFocusedAttribute, defaultVal: false),
                    "bounds": [
                        "x": Int(round(r.origin.x)),
                        "y": Int(round(r.origin.y)),
                        "width": Int(round(r.size.width)),
                        "height": Int(round(r.size.height))
                    ],
                    "cx": Int(round(r.midX)),
                    "cy": Int(round(r.midY))
                ])
            }
        }

        if depth < maxDepth && elements.count < maxNodes {
            if let children = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] {
                for child in children {
                    if elements.count >= maxNodes { break }
                    walk(child, depth + 1)
                }
            }
        }
    }

    walk(root, 0)
    return [
        "target": [
            "app_name": app.localizedName ?? "",
            "bundle_id": app.bundleIdentifier ?? "",
            "pid": Int(app.processIdentifier),
            "accessibility_trusted": AXIsProcessTrusted()
        ],
        "elements": elements
    ]
}

// MARK: - Window Focus & Management

func resolveWindowTarget(_ p: [String: Any]) -> [String: Any]? {
    let wins = listWindows(appFilter: nil, includeMinimized: true)
    let wid = p["window_id"] as? Int
    let pid = p["pid"] as? Int
    let appName = p["app_name"] as? String
    let title = p["title_contains"] as? String

    return wins.first { w in
        if let wid = wid, wid > 0, (w["window_id"] as? Int) != wid { return false }
        if let pid = pid, pid > 0, (w["pid"] as? Int) != pid { return false }
        if let appName = appName, !appName.isEmpty {
            let owner = (w["app_name"] as? String) ?? ""
            if owner.range(of: appName, options: .caseInsensitive) == nil { return false }
        }
        if let title = title, !title.isEmpty {
            let wt = (w["title"] as? String) ?? ""
            if wt.range(of: title, options: .caseInsensitive) == nil { return false }
        }
        return true
    }
}

func findAxWindow(pid: pid_t, title: String?) -> AXUIElement? {
    let axApp = AXUIElementCreateApplication(pid)
    guard let wins = axAttr(axApp, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
    if let t = title, !t.isEmpty {
        if let match = wins.first(where: { axString($0, kAXTitleAttribute).range(of: t, options: .caseInsensitive) != nil }) {
            return match
        }
    }
    return wins.first
}

func focusWindow(_ p: [String: Any]) throws -> [String: Any] {
    var targetPid: pid_t? = nil
    var targetTitle: String? = p["title_contains"] as? String

    if let w = resolveWindowTarget(p), let pid = w["pid"] as? Int {
        targetPid = pid_t(pid)
        if targetTitle == nil { targetTitle = w["title"] as? String }
    } else if let app = resolveTargetApp(appName: p["app_name"] as? String, pid: p["pid"] as? Int) {
        targetPid = app.processIdentifier
    }

    guard let pid = targetPid, let app = NSRunningApplication(processIdentifier: pid) else {
        throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target window/app not found."])
    }

    app.unhide()
    app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    if let axWin = findAxWindow(pid: pid, title: targetTitle) {
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
    }

    return [
        "focused": true,
        "pid": Int(pid),
        "app_name": app.localizedName ?? "",
        "title": targetTitle ?? ""
    ]
}

func manageWindow(_ p: [String: Any]) throws -> [String: Any] {
    guard let action = (p["action"] as? String)?.lowercased() else {
        throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing action."])
    }
    guard let w = resolveWindowTarget(p), let pidInt = w["pid"] as? Int else {
        throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "Target window not found."])
    }
    let pid = pid_t(pidInt)
    guard let axWin = findAxWindow(pid: pid, title: w["title"] as? String) else {
        throw NSError(domain: "ComputerUse", code: 404, userInfo: [NSLocalizedDescriptionKey: "AX window handle unavailable (check Accessibility permission)."])
    }

    switch action {
    case "minimize":
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanTrue)
    case "restore":
        AXUIElementSetAttributeValue(axWin, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
    case "maximize":
        if let zoomBtn = axAttr(axWin, kAXZoomButtonAttribute) {
            AXUIElementPerformAction(zoomBtn as! AXUIElement, kAXPressAction as CFString)
        }
    case "close":
        if let closeBtn = axAttr(axWin, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(closeBtn as! AXUIElement, kAXPressAction as CFString)
        }
    case "move", "resize", "set_bounds":
        if let x = p["x"] as? Double, let y = p["y"] as? Double {
            var pt = CGPoint(x: x, y: y)
            if let val = AXValueCreate(.cgPoint, &pt) {
                AXUIElementSetAttributeValue(axWin, kAXPositionAttribute as CFString, val)
            }
        }
        if let width = p["width"] as? Double, let height = p["height"] as? Double {
            var sz = CGSize(width: width, height: height)
            if let val = AXValueCreate(.cgSize, &sz) {
                AXUIElementSetAttributeValue(axWin, kAXSizeAttribute as CFString, val)
            }
        }
    default:
        throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported action: \(action)"])
    }

    return ["ok": true, "action": action, "pid": pidInt]
}

// MARK: - Main Loop

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { continue }

    guard let data = trimmed.data(using: .utf8),
          let req = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = req["id"] as? Int,
          let action = req["action"] as? String else {
        errOut(0, "Invalid JSON request.")
        continue
    }

    let p = (req["params"] as? [String: Any]) ?? [:]

    do {
        switch action {
        case "get_system_info":
            let displays = getDisplays()
            var arch = "unknown"
            #if arch(arm64)
            arch = "arm64"
            #elseif arch(x86_64)
            arch = "x86_64"
            #endif
            okOut(id, [
                "os": "macos",
                "arch": arch,
                "hostname": ProcessInfo.processInfo.hostName,
                "user": NSUserName(),
                "driver": "macos_swift_coregraphics",
                "displays_count": displays.count,
                "cursor": getCursorPos(),
                "frontmost_window": getFrontmostSummary() as Any
            ])

        case "check_permissions":
            let ax = AXIsProcessTrusted()
            let sr = CGPreflightScreenCaptureAccess()
            okOut(id, [
                "os": "macos",
                "accessibility": ax,
                "screen_recording": sr,
                "remediation": (ax && sr) ? "All required macOS permissions are granted." :
                    "Grant permissions in System Settings -> Privacy & Security -> Screen & System Audio Recording and Accessibility for your terminal / Antigravity app."
            ])

        case "get_screen_info":
            okOut(id, [
                "coordinate_space": "coregraphics_logical_points",
                "displays": getDisplays(),
                "cursor": getCursorPos(),
                "frontmost_window": getFrontmostSummary() as Any
            ])

        case "screenshot":
            okOut(id, try captureScreenshot(p))

        case "mouse_move":
            try requireAccessibility()
            let tx = (p["x"] as? Double) ?? 0
            let ty = (p["y"] as? Double) ?? 0
            let dur = max(0, (p["duration_ms"] as? Int) ?? 0)
            if dur <= 0 {
                postMouse(.mouseMoved, CGPoint(x: tx, y: ty), .left)
            } else {
                let start = currentCursorPoint()
                let steps = max(2, min(60, dur / 16))
                let delayUs = useconds_t(max(1000, (dur * 1000) / steps))
                for i in 1...steps {
                    let t = Double(i) / Double(steps)
                    postMouse(.mouseMoved, CGPoint(x: start.x + (tx - start.x) * t, y: start.y + (ty - start.y) * t), .left)
                    usleep(delayUs)
                }
            }
            okOut(id, ["ok": true, "x": Int(round(tx)), "y": Int(round(ty))])

        case "mouse_click":
            try requireAccessibility()
            let cur = currentCursorPoint()
            let pt = CGPoint(x: (p["x"] as? Double) ?? Double(cur.x), y: (p["y"] as? Double) ?? Double(cur.y))
            let (btn, downT, upT, _) = mapMouseButton(p["button"] as? String)
            let count = max(1, min(3, (p["click_count"] as? Int) ?? 1))
            let flags = modifierFlags((p["modifiers"] as? [String]) ?? [])
            postMouse(.mouseMoved, pt, btn)
            usleep(10000)
            for c in 1...count {
                postMouse(downT, pt, btn, clickCount: c, flags: flags)
                usleep(12000)
                postMouse(upT, pt, btn, clickCount: c, flags: flags)
                if c < count { usleep(35000) }
            }
            okOut(id, ["ok": true])

        case "mouse_down":
            try requireAccessibility()
            let cur = currentCursorPoint()
            let pt = CGPoint(x: (p["x"] as? Double) ?? Double(cur.x), y: (p["y"] as? Double) ?? Double(cur.y))
            let (btn, downT, _, _) = mapMouseButton(p["button"] as? String)
            postMouse(downT, pt, btn)
            okOut(id, ["ok": true])

        case "mouse_up":
            try requireAccessibility()
            let cur = currentCursorPoint()
            let pt = CGPoint(x: (p["x"] as? Double) ?? Double(cur.x), y: (p["y"] as? Double) ?? Double(cur.y))
            let (btn, _, upT, _) = mapMouseButton(p["button"] as? String)
            postMouse(upT, pt, btn)
            okOut(id, ["ok": true])

        case "mouse_drag":
            try requireAccessibility()
            let sx = (p["start_x"] as? Double) ?? 0
            let sy = (p["start_y"] as? Double) ?? 0
            let ex = (p["end_x"] as? Double) ?? 0
            let ey = (p["end_y"] as? Double) ?? 0
            let (btn, downT, upT, dragT) = mapMouseButton(p["button"] as? String)
            let dur = max(20, (p["duration_ms"] as? Int) ?? 250)
            let steps = max(2, min(100, (p["steps"] as? Int) ?? 15))
            postMouse(.mouseMoved, CGPoint(x: sx, y: sy), btn)
            usleep(15000)
            postMouse(downT, CGPoint(x: sx, y: sy), btn)
            let delayUs = useconds_t(max(1000, (dur * 1000) / steps))
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                postMouse(dragT, CGPoint(x: sx + (ex - sx) * t, y: sy + (ey - sy) * t), btn)
                usleep(delayUs)
            }
            postMouse(upT, CGPoint(x: ex, y: ey), btn)
            okOut(id, ["ok": true])

        case "mouse_scroll":
            try requireAccessibility()
            let cur = currentCursorPoint()
            let pt = CGPoint(x: (p["x"] as? Double) ?? Double(cur.x), y: (p["y"] as? Double) ?? Double(cur.y))
            postMouse(.mouseMoved, pt, .left)
            let dx = (p["delta_x"] as? Int) ?? 0
            let dy = (p["delta_y"] as? Int) ?? 0
            if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: Int32(dy * 3), wheel2: Int32(-dx * 3), wheel3: 0) {
                ev.post(tap: .cghidEventTap)
            }
            okOut(id, ["ok": true])

        case "type_text":
            try requireAccessibility()
            let text = (p["text"] as? String) ?? ""
            let delay = max(0, (p["delay_ms"] as? Int) ?? 0)
            typeUnicodeText(text, delayMs: delay)
            okOut(id, ["ok": true, "length": text.count])

        case "press_key", "hotkey":
            try requireAccessibility()
            let key = ((p["key"] as? String) ?? "").lowercased()
            let mods = (p["modifiers"] as? [String]) ?? []
            let flags = modifierFlags(mods)
            let repeatCount = max(1, (p["repeat"] as? Int) ?? 1)
            if !key.isEmpty {
                guard let code = KEY_CODES[key] else {
                    throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported macOS key: '\(key)'"])
                }
                for i in 0..<repeatCount {
                    postKey(code, down: true, flags: flags)
                    usleep(10000)
                    postKey(code, down: false, flags: flags)
                    if i + 1 < repeatCount { usleep(25000) }
                }
            } else if let firstMod = mods.first, let mCode = KEY_CODES[firstMod.lowercased()] {
                postKey(mCode, down: true)
                usleep(10000)
                postKey(mCode, down: false)
            }
            okOut(id, ["ok": true])

        case "key_down":
            try requireAccessibility()
            let key = ((p["key"] as? String) ?? "").lowercased()
            guard let code = KEY_CODES[key] else {
                throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported macOS key: '\(key)'"])
            }
            postKey(code, down: true)
            okOut(id, ["ok": true])

        case "key_up":
            try requireAccessibility()
            let key = ((p["key"] as? String) ?? "").lowercased()
            guard let code = KEY_CODES[key] else {
                throw NSError(domain: "ComputerUse", code: 400, userInfo: [NSLocalizedDescriptionKey: "Unsupported macOS key: '\(key)'"])
            }
            postKey(code, down: false)
            okOut(id, ["ok": true])

        case "get_ui_tree":
            okOut(id, try getUiTree(
                appName: p["app_name"] as? String,
                pid: p["pid"] as? Int,
                maxDepth: (p["max_depth"] as? Int) ?? 5,
                maxNodes: (p["max_nodes"] as? Int) ?? 200,
                interactiveOnly: (p["interactive_only"] as? Bool) ?? false
            ))

        case "list_windows":
            okOut(id, listWindows(
                appFilter: p["app_name"] as? String,
                includeMinimized: (p["include_minimized"] as? Bool) ?? true
            ))

        case "focus_window":
            okOut(id, try focusWindow(p))

        case "manage_window":
            okOut(id, try manageWindow(p))

        case "list_running_apps":
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map { app -> [String: Any] in
                    [
                        "pid": Int(app.processIdentifier),
                        "name": app.localizedName ?? "",
                        "bundle_id": app.bundleIdentifier ?? "",
                        "active": app.isActive,
                        "hidden": app.isHidden
                    ]
                }
            okOut(id, apps)

        case "launch_app":
            let target = (p["target"] as? String) ?? ""
            let args = (p["args"] as? [String]) ?? []
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            if target.hasPrefix("http://") || target.hasPrefix("https://") || FileManager.default.fileExists(atPath: target) {
                proc.arguments = [target] + args
            } else if target.contains(".") && !target.contains(" ") {
                proc.arguments = ["-b", target] + (args.isEmpty ? [] : ["--args"] + args)
            } else {
                proc.arguments = ["-a", target] + (args.isEmpty ? [] : ["--args"] + args)
            }
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 {
                throw NSError(domain: "ComputerUse", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to launch '\(target)'"])
            }
            okOut(id, ["launched": true, "target": target])

        case "clipboard_read":
            let text = NSPasteboard.general.string(forType: .string)
            okOut(id, ["has_text": text != nil, "text": text ?? ""])

        case "clipboard_write":
            let text = (p["text"] as? String) ?? ""
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            okOut(id, ["ok": true, "length": text.count])

        default:
            errOut(id, "Unknown macOS helper action: \(action)")
        }
    } catch {
        errOut(id, error.localizedDescription)
    }
}
