import Foundation

/// A demo plan: what to launch, and timed steps to perform while recording.
/// Written as YAML (needs python3 with PyYAML) or JSON. See references/plan-format.md.
struct Plan: Decodable {
    var name: String?
    /// "macos" or "ios".
    var platform: String
    var app: AppSpec
    var output: OutputSpec?
    var pointer: PointerSpec?
    var steps: [Step]
}

struct AppSpec: Decodable {
    // macOS
    /// Command and arguments. State commands are written to its stdin, one per line.
    var launch: [String]?
    /// Working directory for `launch`, relative to the plan file.
    var cwd: String?
    var env: [String: String]?
    /// Run `build` before launching, relative to the plan file's directory.
    var build: [String]?

    // iOS Simulator
    var bundleId: String?
    /// Simulator name or UDID. Defaults to the booted one, else the newest iPhone.
    var device: String?
    /// An .app to install first, relative to the plan file.
    var install: String?
    var args: [String]?
    /// Deep-link scheme for state commands: `<scheme>://demo?cmd=<command>`.
    var urlScheme: String?
    /// "light" or "dark".
    var appearance: String?
    /// Override the status bar to 9:41, full battery and signal. Default true.
    var cleanStatusBar: Bool?
}

struct OutputSpec: Decodable {
    /// Base path without extension, relative to the plan file. Default `out/<name>`.
    var path: String?
    /// mov, mp4, gif, webm. Default mov, mp4 on macOS; mp4 on iOS.
    var formats: [String]?
    var background: String?
    var padding: Double?
    /// "vtt", "burn", "both" or "none". Default vtt when there are captions.
    var captions: String?
    var gifWidth: Int?
    var gifFPS: Int?
    var fps: Int?
    /// Draw a circle where each tap lands (default true on iOS).
    var touches: Bool?
}

struct PointerSpec: Decodable {
    /// Show the pointer in macOS recordings. Default true when the plan moves it.
    var show: Bool?
    /// Seconds to glide to each target. Default 0.55.
    var travel: Double?
    /// Where the pointer waits before the first move: [x, y] points from the top-left of
    /// the app's first window. Default just below the window's centre.
    var start: [Double]?
    /// macOS: show help tags when the pointer rests on a control. false (default) hides them,
    /// true shows them after 0.5 s, a number after that many seconds.
    var tooltips: Tooltips?
}

/// `false`, `true` or seconds of rest before a tooltip shows.
struct Tooltips: Decodable {
    /// nil hides tooltips.
    var delay: Double?

    init(delay: Double?) { self.delay = delay }

    /// "off", "on" or seconds, as given to `--tooltips`.
    init?(_ text: String) {
        switch text.lowercased() {
        case "off", "false", "no": delay = nil
        case "on", "true", "yes": delay = 0.5
        default:
            guard let seconds = Double(text), seconds >= 0 else { return nil }
            delay = seconds
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let show = try? container.decode(Bool.self) {
            delay = show ? 0.5 : nil
        } else {
            delay = try container.decode(Double.self)
        }
    }

    /// AppKit argument-domain defaults that set the delay; an hour stands in for never.
    var launchArguments: [String] {
        ["-NSInitialToolTipDelay", String(Int(((delay ?? 3600) * 1000).rounded()))]
    }
}

struct DragSpec: Decodable {
    var from: Target
    var to: Target
}

struct SwipeSpec: Decodable {
    /// Where the swipe starts. Default the middle of the screen or window.
    var on: Target?
    /// up, down, left or right: the way the finger moves.
    var direction: String
    /// Points. Default 300.
    var distance: Double?
}

struct ScrollSpec: Decodable {
    var on: Target?
    /// Lines; positive scrolls content up (like moving down the page).
    var lines: Int
}

struct Step: Decodable {
    /// Seconds from the start of the recording. Accepts 3, 3.5, "0:03" or "1:02.5".
    var at: Double
    var state: String?
    var click: Target?
    var doubleClick: Target?
    var rightClick: Target?
    var hover: Target?
    var tap: Target?
    var drag: DragSpec?
    var swipe: SwipeSpec?
    var scroll: ScrollSpec?
    var type: String?
    var key: String?
    /// Passes when a matching element is on screen by `at + within`.
    var expect: Target?
    /// Passes when no matching element is on screen by `at + within`.
    var expectGone: Target?
    /// Seconds to wait for an expectation, or for a target to appear. Default 2.
    var within: Double?
    /// Seconds to glide the pointer for this step, overriding the plan's travel.
    var travel: Double?
    /// Shown from `at` until the next caption or `captionFor` seconds.
    var caption: String?
    var captionFor: Double?
    var end: Bool?
    /// The script line this step came from, for the take log.
    var note: String?

    var action: String {
        if state != nil { return "state" }
        if click != nil { return "click" }
        if doubleClick != nil { return "doubleClick" }
        if rightClick != nil { return "rightClick" }
        if hover != nil { return "hover" }
        if tap != nil { return "tap" }
        if drag != nil { return "drag" }
        if swipe != nil { return "swipe" }
        if scroll != nil { return "scroll" }
        if type != nil { return "type" }
        if key != nil { return "key" }
        if expect != nil { return "expect" }
        if expectGone != nil { return "expectGone" }
        if end == true { return "end" }
        return caption != nil ? "caption" : "none"
    }

    /// Steps that glide the pointer start early so the action lands at `at`.
    var movesPointer: Bool { ["click", "doubleClick", "rightClick", "hover", "tap", "drag", "swipe", "scroll"].contains(action) }

    private enum CodingKeys: String, CodingKey {
        case at, state, click, doubleClick, rightClick, hover, tap, drag, swipe, scroll, type, key, expect, expectGone, within, travel, caption, captionFor, end, note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let seconds = try? container.decode(Double.self, forKey: .at) {
            at = seconds
        } else {
            let text = try container.decode(String.self, forKey: .at)
            let parts = text.split(separator: ":").compactMap { Double($0) }
            guard !parts.isEmpty, parts.count <= 3 else {
                throw DecodingError.dataCorruptedError(forKey: .at, in: container, debugDescription: "at: wants seconds or m:ss, got \(text)")
            }
            at = parts.reduce(0) { $0 * 60 + $1 }
        }
        state = try container.decodeIfPresent(String.self, forKey: .state)
        click = try container.decodeIfPresent(Target.self, forKey: .click)
        doubleClick = try container.decodeIfPresent(Target.self, forKey: .doubleClick)
        rightClick = try container.decodeIfPresent(Target.self, forKey: .rightClick)
        hover = try container.decodeIfPresent(Target.self, forKey: .hover)
        tap = try container.decodeIfPresent(Target.self, forKey: .tap)
        drag = try container.decodeIfPresent(DragSpec.self, forKey: .drag)
        swipe = try container.decodeIfPresent(SwipeSpec.self, forKey: .swipe)
        scroll = try container.decodeIfPresent(ScrollSpec.self, forKey: .scroll)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        expect = try container.decodeIfPresent(Target.self, forKey: .expect)
        expectGone = try container.decodeIfPresent(Target.self, forKey: .expectGone)
        within = try container.decodeIfPresent(Double.self, forKey: .within)
        travel = try container.decodeIfPresent(Double.self, forKey: .travel)
        caption = try container.decodeIfPresent(String.self, forKey: .caption)
        captionFor = try container.decodeIfPresent(Double.self, forKey: .captionFor)
        end = try container.decodeIfPresent(Bool.self, forKey: .end)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }
}

func loadPlan(_ url: URL) -> Plan {
    var data: Data
    do { data = try Data(contentsOf: url) } catch { fail("can't read \(url.path): \(error.localizedDescription)") }
    if ["yaml", "yml"].contains(url.pathExtension.lowercased()) {
        let converted = run("/usr/bin/env", ["python3", "-c", "import sys, json, yaml; json.dump(yaml.safe_load(open(sys.argv[1])), sys.stdout)", url.path])
        guard converted.status == 0 else { fail("couldn't parse \(url.lastPathComponent) as YAML (needs python3 with PyYAML: pip3 install pyyaml)") }
        data = Data(converted.output.utf8)
    }
    let plan: Plan
    do {
        plan = try JSONDecoder().decode(Plan.self, from: data)
    } catch let DecodingError.keyNotFound(key, context) {
        fail("plan: missing \(key.stringValue) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
    } catch let DecodingError.typeMismatch(_, context), let DecodingError.dataCorrupted(context) {
        fail("plan: \(context.debugDescription) at \(context.codingPath.map(\.stringValue).joined(separator: "."))")
    } catch {
        fail("plan: \(error)")
    }
    guard ["macos", "ios"].contains(plan.platform) else { fail("plan: platform must be macos or ios") }
    for (index, step) in plan.steps.enumerated() where step.action == "none" {
        fail("plan: step \(index + 1) (at \(step.at)) has no action")
    }
    if plan.platform == "macos", plan.app.launch == nil { fail("plan: app.launch is required on macOS") }
    if plan.platform == "ios", plan.app.bundleId == nil { fail("plan: app.bundleId is required on iOS") }
    return plan
}
