import AppKit
import ApplicationServices
import Foundation

// MARK: - Accessibility

/// One element of an app's accessibility tree, flattened for matching.
struct AXNode {
    let element: AXUIElement
    let role: String
    let title: String
    let label: String
    let value: String
    let identifier: String
    /// Global top-left-origin points.
    let frame: CGRect
    let depth: Int

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    /// Every piece of text the element exposes, for loose matching.
    var texts: [String] { [title, label, value, identifier].filter { !$0.isEmpty } }

    var summary: String {
        var parts = [role.replacingOccurrences(of: "AX", with: "")]
        if !label.isEmpty { parts.append("label=\"\(label)\"") }
        if !title.isEmpty, title != label { parts.append("title=\"\(title)\"") }
        if !value.isEmpty, value != title, value != label { parts.append("value=\"\(value.prefix(80))\"") }
        if !identifier.isEmpty { parts.append("id=\(identifier)") }
        parts.append(String(format: "@%.0f,%.0f %.0f×%.0f", frame.minX, frame.minY, frame.width, frame.height))
        return parts.joined(separator: " ")
    }
}

func requireAccessibility() {
    guard AXIsProcessTrusted() else {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        fail("needs Accessibility permission for this terminal, to find controls and move the pointer: System Settings > Privacy & Security > Accessibility")
    }
}

private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value as? T
}

private func string(_ element: AXUIElement, _ name: String) -> String {
    if let text: String = attribute(element, name) { return text }
    if let number: NSNumber = attribute(element, name) { return number.stringValue }
    return ""
}

private func frame(of element: AXUIElement) -> CGRect {
    var position = CGPoint.zero, size = CGSize.zero
    if let value: AXValue = attribute(element, kAXPositionAttribute) { AXValueGetValue(value, .cgPoint, &position) }
    if let value: AXValue = attribute(element, kAXSizeAttribute) { AXValueGetValue(value, .cgSize, &size) }
    return CGRect(origin: position, size: size)
}

/// Brings an app to the front. `NSRunningApplication.activate()` is only a request since
/// macOS 14 and is ignored when the caller isn't frontmost; setting AXFrontmost isn't.
/// Tooltips and key-window styling need the app active.
@discardableResult
func makeFrontmost(_ pid: pid_t) -> Bool {
    NSRunningApplication(processIdentifier: pid)?.activate()
    return AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
}

/// The accessibility tree of every process in `pids`, depth first.
func accessibilityTree(of pids: Set<pid_t>, limit: Int = 4000) -> [AXNode] {
    var nodes: [AXNode] = []
    for pid in pids.sorted() {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1)
        // SwiftUI and Chromium build their trees on demand.
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        var stack = windows.reversed().map { ($0, 0) }
        while let (element, depth) = stack.popLast(), nodes.count < limit {
            nodes.append(AXNode(
                element: element,
                role: string(element, kAXRoleAttribute),
                title: string(element, kAXTitleAttribute),
                label: string(element, kAXDescriptionAttribute),
                value: string(element, kAXValueAttribute),
                identifier: string(element, kAXIdentifierAttribute),
                frame: frame(of: element),
                depth: depth
            ))
            let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) ?? []
            stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
        }
    }
    return nodes
}

/// What a plan step points at. A bare string matches a label, title, value or identifier.
struct Target: Decodable, CustomStringConvertible {
    var label: String?
    var id: String?
    var text: String?
    var role: String?
    /// Which match to use when several fit, from 0.
    var index: Int?
    /// Points from the element's centre.
    var offset: [Double]?
    /// Points from the top-left of the app's first window, when nothing can be found by label.
    var point: [Double]?

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            self.text = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        offset = try container.decodeIfPresent([Double].self, forKey: .offset)
        point = try container.decodeIfPresent([Double].self, forKey: .point)
    }

    private enum CodingKeys: String, CodingKey { case label, id, text, role, index, offset, point }

    var description: String {
        [label.map { "label \"\($0)\"" }, id.map { "id \($0)" }, text.map { "\"\($0)\"" }, role.map { "role \($0)" },
         point.map { "point \($0)" }].compactMap { $0 }.joined(separator: " ")
    }

    /// Matching nodes, best first: exact matches before partial ones, smaller elements first.
    func matches(in nodes: [AXNode]) -> [AXNode] {
        func equal(_ a: String, _ b: String) -> Bool { a.caseInsensitiveCompare(b) == .orderedSame }
        func contains(_ a: String, _ b: String) -> Bool { a.range(of: b, options: .caseInsensitive) != nil }
        let visible = nodes.filter { $0.frame.width > 0 && $0.frame.height > 0 }
        let scored: [(AXNode, Int)] = visible.compactMap { node in
            if let role, !equal(node.role, role), !equal(node.role, "AX" + role) { return nil }
            if let id { return node.identifier == id ? (node, 0) : nil }
            if let label {
                if equal(node.label, label) || equal(node.title, label) { return (node, 0) }
                if contains(node.label, label) || contains(node.title, label) { return (node, 1) }
                return nil
            }
            if let text {
                if node.texts.contains(where: { equal($0, text) }) { return (node, 0) }
                if node.texts.contains(where: { contains($0, text) }) { return (node, 1) }
                return nil
            }
            return role == nil ? nil : (node, 0)
        }
        return scored
            .sorted { ($0.1, $0.0.frame.width * $0.0.frame.height) < ($1.1, $1.0.frame.width * $1.0.frame.height) }
            .map(\.0)
    }
}

// MARK: - Input

/// Moves the real pointer and sends real clicks and keys, so hover effects and tracking
/// areas behave as they do for a person.
enum Input {
    static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func warp(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
        post(.mouseMoved, at: point)
    }

    /// Glides along a slight arc with ease-in-out, like a hand on a trackpad.
    static func move(to target: CGPoint, duration: Double, dragging: Bool = false) async {
        let start = location
        let distance = hypot(target.x - start.x, target.y - start.y)
        guard distance > 0.5, duration > 0 else {
            post(dragging ? .leftMouseDragged : .mouseMoved, at: target)
            return
        }
        let bend = min(distance * 0.08, 40)
        let normal = CGPoint(x: -(target.y - start.y) / distance * bend, y: (target.x - start.x) / distance * bend)
        let control = CGPoint(x: (start.x + target.x) / 2 + normal.x, y: (start.y + target.y) / 2 + normal.y)
        let steps = max(Int(duration * 120), 2)
        let begin = hostSeconds()
        for step in 1...steps {
            let linear = Double(step) / Double(steps)
            let t = linear < 0.5 ? 4 * linear * linear * linear : 1 - pow(-2 * linear + 2, 3) / 2
            let u = 1 - t
            let point = CGPoint(
                x: u * u * start.x + 2 * u * t * control.x + t * t * target.x,
                y: u * u * start.y + 2 * u * t * control.y + t * t * target.y
            )
            post(dragging ? .leftMouseDragged : .mouseMoved, at: point)
            await sleep(until: begin + duration * linear)
        }
    }

    static func click(at point: CGPoint, count: Int = 1, right: Bool = false) async {
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        for clickIndex in 1...count {
            post(down, at: point, clickState: clickIndex, button: right ? .right : .left)
            await sleep(seconds: 0.06)
            post(up, at: point, clickState: clickIndex, button: right ? .right : .left)
            if clickIndex < count { await sleep(seconds: 0.08) }
        }
    }

    static func press(at point: CGPoint) { post(.leftMouseDown, at: point) }
    static func release(at point: CGPoint) { post(.leftMouseUp, at: point) }

    static func scroll(by lines: Int, at point: CGPoint) async {
        let direction: Int32 = lines < 0 ? -1 : 1
        for _ in 0..<abs(lines) {
            let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: direction, wheel2: 0, wheel3: 0)
            event?.location = point
            event?.post(tap: .cghidEventTap)
            await sleep(seconds: 0.03)
        }
    }

    /// Types text one character at a time at a natural pace.
    static func type(_ text: String, interval: Double = 0.045) async {
        for character in text {
            if character == "\n" {
                await key("return")
            } else {
                let units = Array(String(character).utf16)
                for isDown in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: isDown)
                    event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                    event?.post(tap: .cghidEventTap)
                }
            }
            await sleep(seconds: interval)
        }
    }

    /// A key combination like "cmd+shift+k", "escape" or "cmd+,".
    static func key(_ combo: String) async {
        var flags: CGEventFlags = []
        var keyName = combo.lowercased()
        let parts = keyName.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        if parts.count > 1 {
            keyName = parts.last!.isEmpty ? "+" : parts.last!
            for modifier in parts.dropLast() {
                switch modifier {
                case "cmd", "command": flags.insert(.maskCommand)
                case "shift": flags.insert(.maskShift)
                case "alt", "option", "opt": flags.insert(.maskAlternate)
                case "ctrl", "control": flags.insert(.maskControl)
                case "fn": flags.insert(.maskSecondaryFn)
                default: fail("unknown modifier \(modifier) in \(combo)")
                }
            }
        }
        guard let code = keyCodes[keyName] else { fail("unknown key \(keyName) in \(combo)") }
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: isDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            await sleep(seconds: 0.03)
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint, clickState: Int = 1, button: CGMouseButton = .left) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
        event?.post(tap: .cghidEventTap)
    }

    private static let keyCodes: [String: CGKeyCode] = {
        var codes: [String: CGKeyCode] = [
            "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
            "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27,
            "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41,
            "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "`": 50,
            "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
            "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        codes["+"] = 24
        return codes
    }()
}

// MARK: - ax subcommand

let axUsage = """
Usage: demo-video ax (--pid <pid> | --app <name|bundle-id>) [--find <text>] [--depth <n>]

Prints an app's accessibility tree: role, label, title, value, id and frame of each element.
Use it to pick targets for a plan. For the iOS Simulator, use --app Simulator.
"""

func axCommand(_ arguments: [String]) {
    let args = Arguments(arguments, flags: ["help"])
    if args.has("help") || arguments.isEmpty { print(axUsage); exit(0) }
    requireAccessibility()
    let pid: pid_t
    if let value = args.int("pid") {
        pid = pid_t(value)
    } else if let name = args["app"] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name || $0.bundleIdentifier == name }) else { fail("no running app named \(name)") }
        pid = app.processIdentifier
    } else {
        fail(axUsage)
    }
    var nodes = accessibilityTree(of: processTree(pid))
    if let find = args["find"] {
        let target = try! JSONDecoder().decode(Target.self, from: JSONEncoder().encode(find))
        nodes = target.matches(in: nodes)
        for node in nodes { print(node.summary) }
        return
    }
    let maxDepth = args.int("depth") ?? .max
    for node in nodes where node.depth <= maxDepth {
        print(String(repeating: "  ", count: node.depth) + node.summary)
    }
}
