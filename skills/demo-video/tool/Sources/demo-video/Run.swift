import AVFoundation
import AppKit
import CoreImage
import Foundation
import ImageIO

let runUsage = """
Usage: demo-video run <plan.yaml|plan.json> [--out <base>] [--formats mov,mp4,gif,webm]
                     [--tooltips on|off|<seconds>] [--dry-run]

Launches the plan's app, performs its steps at their timestamps while recording, then
exports the take and a take log (<base>.take.json). Exits 2 if any expectation failed.
--formats and --tooltips override the plan's output.formats and pointer.tooltips.
--dry-run performs the steps without recording, to check targets resolve.
"""

/// What the runner needs from a platform.
protocol Backend: AnyObject {
    /// Builds, installs and launches the app, and waits for its window.
    func prepare() async
    /// Starts recording; returns the host time of the first frame (time zero).
    func startRecording() async -> Double
    func stopRecording() async
    func sendState(_ command: String) -> Bool
    /// The accessibility tree to search for targets.
    func nodes() -> [AXNode]
    /// The app's window (macOS) or device screen (iOS) in global points.
    func area() -> CGRect
    func teardown() async
    /// Writes the outputs; returns the files and duration.
    func export(end: Double, cues: [Cue], touches: [(time: Double, point: CGPoint)], outputs: Outputs, settings: OutputSpec) async -> (files: [URL], duration: Double)
    var recordsPointer: Bool { get }
    var drawsTouches: Bool { get }
}

struct StepResult: Encodable {
    var at: Double
    var action: String
    var target: String?
    var started: Double?
    var landed: Double?
    var ok: Bool
    var detail: String?
    var note: String?
}

func runCommand(_ arguments: [String]) async {
    let args = Arguments(arguments, flags: ["dry-run", "help"])
    guard !args.has("help"), let planPath = args.positional.first else { print(runUsage); exit(args.has("help") ? 0 : 1) }
    let planURL = URL(fileURLWithPath: planPath).standardizedFileURL
    let plan = loadPlan(planURL)
    let directory = planURL.deletingLastPathComponent()
    let name = plan.name ?? planURL.deletingPathExtension().deletingPathExtension().lastPathComponent
    let settings = plan.output ?? OutputSpec()
    let base = args["out"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: settings.path ?? "out/\(name)", relativeTo: directory)
    let defaultFormats = plan.platform == "ios" ? ["mp4"] : ["mov", "mp4"]
    let formats = Set(args["formats"].map { $0.split(separator: ",").map(String.init) } ?? settings.formats ?? defaultFormats)
    let outputs = Outputs.make(base: base.standardizedFileURL.deletingPathExtension(), formats: formats)
    let dryRun = args.has("dry-run")
    let tooltips: Tooltips
    if let flag = args["tooltips"] {
        guard let parsed = Tooltips(flag) else { fail("--tooltips wants on, off or seconds, got \(flag)") }
        tooltips = parsed
    } else {
        tooltips = plan.pointer?.tooltips ?? Tooltips(delay: nil)
    }

    // Stable: steps at the same time keep their written order.
    let steps = plan.steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    let usesUI = steps.contains { $0.movesPointer || ["type", "key", "expect", "expectGone"].contains($0.action) }
    if usesUI { requireAccessibility() }
    if !dryRun { requireScreenRecording() }

    let backend: Backend = plan.platform == "ios"
        ? IOSBackend(plan: plan, directory: directory, scratch: outputs.scratch)
        : MacBackend(plan: plan, directory: directory, scratch: outputs.scratch, showPointer: plan.pointer?.show ?? steps.contains(where: \.movesPointer), tooltips: tooltips)
    let travelDefault = plan.pointer?.travel ?? (backend.recordsPointer ? 0.55 : 0.2)
    let userPointer = Input.location

    await backend.prepare()
    if usesUI {
        // The first accessibility query is slow while the app builds its tree; do it now,
        // not during the first timed step.
        _ = backend.nodes()
        let area = backend.area()
        let start = plan.pointer?.start.map { CGPoint(x: area.minX + $0[0], y: area.minY + $0[1]) }
            ?? CGPoint(x: area.midX, y: area.maxY + 28)
        Input.warp(to: start)
    }
    // With no pointer steps the real pointer stays put; park it off the windows so it
    // doesn't leave a hover state on (the app is frontmost now, so hovers register).
    var parked = false
    if !usesUI, plan.platform == "macos" {
        let area = backend.area()
        if area.insetBy(dx: -40, dy: -40).contains(userPointer) {
            Input.warp(to: CGPoint(x: area.midX, y: area.maxY + 80))
            parked = true
        }
    }

    var interrupted = false
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { interrupted = true }
    interrupt.resume()

    let zero = dryRun ? hostSeconds() : await backend.startRecording()
    log(dryRun ? "dry run: \(name)" : "recording \(name), hands off the mouse and keyboard")
    var results: [StepResult] = []
    /// Expectations run alongside the timeline, so a slow one never delays later steps.
    var checks: [Task<StepResult, Never>] = []
    var touches: [(time: Double, point: CGPoint)] = []
    var endTime = (steps.last?.at ?? 0) + 1.5

    func now() -> Double { ((hostSeconds() - zero) * 1000).rounded() / 1000 }

    /// Polls for a target until it appears or `within` runs out.
    func find(_ target: Target, within: Double) async -> CGPoint? {
        if let point = target.point {
            let area = backend.area()
            return CGPoint(x: area.minX + point[0], y: area.minY + point[1])
        }
        let deadline = hostSeconds() + within
        repeat {
            let matches = target.matches(in: backend.nodes())
            let index = target.index ?? 0
            if matches.count > index {
                let center = matches[index].center
                return CGPoint(x: center.x + (target.offset?[0] ?? 0), y: center.y + (target.offset?[1] ?? 0))
            }
            await sleep(seconds: 0.1)
        } while hostSeconds() < deadline
        return nil
    }

    for step in steps {
        if interrupted { break }
        if step.end == true {
            endTime = step.at
            break
        }
        let travel = step.travel ?? travelDefault
        let lead = step.movesPointer ? travel : 0
        // Look up the step's main target a little before the glide starts, since a lookup
        // walks the whole accessibility tree; then glide on schedule.
        var found: CGPoint?
        let mainTarget = step.click ?? step.doubleClick ?? step.rightClick ?? step.tap ?? step.hover ?? step.drag?.from ?? step.swipe?.on ?? step.scroll?.on
        if let mainTarget {
            await sleep(until: zero + step.at - lead - 0.4)
            found = await find(mainTarget, within: step.within ?? 2)
        }
        func resolve(_ target: Target, within: Double) async -> CGPoint? {
            if let found, target.description == mainTarget?.description { return found }
            return await find(target, within: within)
        }
        await sleep(until: zero + step.at - lead)
        var result = StepResult(at: step.at, action: step.action, started: now(), ok: true, note: step.note)
        let within = step.within ?? 2

        func land() { result.landed = now() }
        func missing(_ target: Target) {
            result.ok = false
            result.detail = "no element matched \(target)"
        }

        switch step.action {
        case "state":
            result.target = step.state
            if !backend.sendState(step.state!) { result.ok = false; result.detail = "app has no state channel" }
            land()
        case "click", "doubleClick", "rightClick", "tap", "hover":
            let target = step.click ?? step.doubleClick ?? step.rightClick ?? step.tap ?? step.hover!
            result.target = target.description
            guard let point = await resolve(target, within: within) else { missing(target); break }
            await Input.move(to: point, duration: max(0, zero + step.at - hostSeconds()))
            land()
            if step.action != "hover" {
                touches.append((now(), point))
                await Input.click(at: point, count: step.action == "doubleClick" ? 2 : 1, right: step.action == "rightClick")
            }
        case "drag":
            let drag = step.drag!
            result.target = "\(drag.from) → \(drag.to)"
            guard let from = await resolve(drag.from, within: within) else { missing(drag.from); break }
            await Input.move(to: from, duration: max(0, zero + step.at - hostSeconds()))
            land()
            touches.append((now(), from))
            Input.press(at: from)
            guard let to = await resolve(drag.to, within: within) else { Input.release(at: from); missing(drag.to); break }
            await Input.move(to: to, duration: max(0.35, travel), dragging: true)
            Input.release(at: to)
        case "swipe":
            let swipe = step.swipe!
            let area = backend.area()
            var from = CGPoint(x: area.midX, y: area.midY)
            if let on = swipe.on {
                guard let point = await resolve(on, within: within) else { missing(on); break }
                from = point
            }
            let distance = swipe.distance ?? 300
            let vector: CGPoint
            switch swipe.direction.lowercased() {
            case "up": vector = CGPoint(x: 0, y: -distance)
            case "down": vector = CGPoint(x: 0, y: distance)
            case "left": vector = CGPoint(x: -distance, y: 0)
            case "right": vector = CGPoint(x: distance, y: 0)
            default: result.ok = false; result.detail = "swipe direction must be up, down, left or right"; vector = .zero
            }
            guard result.ok else { break }
            result.target = "\(swipe.direction) \(Int(distance))pt"
            await Input.move(to: from, duration: max(0, zero + step.at - hostSeconds()))
            land()
            touches.append((now(), from))
            Input.press(at: from)
            let to = CGPoint(x: from.x + vector.x, y: from.y + vector.y)
            await Input.move(to: to, duration: 0.28, dragging: true)
            Input.release(at: to)
        case "scroll":
            let scroll = step.scroll!
            var point = CGPoint(x: backend.area().midX, y: backend.area().midY)
            if let on = scroll.on {
                guard let found = await resolve(on, within: within) else { missing(on); break }
                point = found
            }
            await Input.move(to: point, duration: max(0, zero + step.at - hostSeconds()))
            land()
            await Input.scroll(by: scroll.lines, at: point)
        case "type":
            result.target = step.type
            land()
            await Input.type(step.type!)
        case "key":
            result.target = step.key
            land()
            await Input.key(step.key!)
        case "expect", "expectGone":
            let target = step.expect ?? step.expectGone!
            let wantsGone = step.action == "expectGone"
            result.target = target.description
            checks.append(Task.detached { [backend, result] in
                var result = result
                let deadline = hostSeconds() + within
                var satisfied = false
                repeat {
                    let found = !target.matches(in: backend.nodes()).isEmpty
                    if found != wantsGone { satisfied = true; break }
                    await sleep(seconds: 0.1)
                } while hostSeconds() < deadline
                result.landed = ((hostSeconds() - zero) * 1000).rounded() / 1000
                if !satisfied {
                    result.ok = false
                    result.detail = wantsGone ? "still on screen after \(within) s" : "not on screen within \(within) s"
                }
                log(String(format: "%6.2f %@ %@ %@ at %.2f%@", result.at, result.ok ? "✓" : "✗", result.action, result.target ?? "", result.landed ?? 0,
                           result.detail.map { "  (\($0))" } ?? ""))
                return result
            })
            continue
        default:
            land()
        }
        results.append(result)
        let mark = result.ok ? "✓" : "✗"
        log(String(format: "%6.2f %@ %@ %@%@", step.at, mark, step.action, result.target ?? step.caption ?? "", result.detail.map { "  (\($0))" } ?? ""))
    }

    if !interrupted { await sleep(until: zero + endTime) }
    for check in checks { results.append(await check.value) }
    results = results.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
    if !dryRun { await backend.stopRecording() }
    if usesUI || parked { Input.warp(to: userPointer) }
    await backend.teardown()

    // Captions run until the next caption, captionFor, or 3.5 s.
    let captioned = steps.filter { $0.caption != nil && $0.at < endTime }
    let cues: [Cue] = captioned.enumerated().map { index, step in
        let next = index + 1 < captioned.count ? captioned[index + 1].at : endTime
        return Cue(start: step.at, end: min(step.at + (step.captionFor ?? 3.5), next, endTime), text: step.caption!)
    }

    let failures = results.filter { !$0.ok }
    if dryRun {
        try? FileManager.default.removeItem(at: outputs.scratch)
        log(failures.isEmpty ? "dry run passed" : "\(failures.count) step(s) failed")
        exit(failures.isEmpty ? 0 : 2)
    }

    let (files, duration) = await backend.export(end: endTime, cues: cues, touches: touches, outputs: outputs, settings: settings)
    var written = files
    let captionMode = settings.captions ?? (cues.isEmpty ? "none" : "vtt")
    if !cues.isEmpty, ["vtt", "both"].contains(captionMode) {
        let vtt = outputs.base.appendingPathExtension("vtt")
        try? writeVTT(cues, to: vtt)
        written.append(vtt)
    }

    struct TakeLog: Encodable {
        var plan: String
        var recorded: String
        var duration: Double
        var files: [String]
        var failures: Int
        var steps: [StepResult]
    }
    let logURL = outputs.base.appendingPathExtension("take.json")
    let take = TakeLog(plan: planURL.path, recorded: ISO8601DateFormatter().string(from: Date()), duration: duration,
                       files: written.map(\.path), failures: failures.count, steps: results)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try? encoder.encode(take).write(to: logURL)

    log(String(format: "%.1f s take, %d step(s), %d failed", duration, results.count, failures.count))
    for url in written + [logURL] { print(url.path) }
    exit(failures.isEmpty ? 0 : 2)
}

// MARK: - macOS

final class MacBackend: Backend {
    let plan: Plan
    let directory: URL
    let scratch: URL
    let showPointer: Bool
    let tooltips: Tooltips
    private var process: Process?
    private var stdin: Pipe?
    private var recorder: WindowRecorder?
    private var zero = 0.0

    init(plan: Plan, directory: URL, scratch: URL, showPointer: Bool, tooltips: Tooltips) {
        self.plan = plan
        self.directory = directory
        self.scratch = scratch
        self.showPointer = showPointer
        self.tooltips = tooltips
    }

    var recordsPointer: Bool { showPointer }
    var drawsTouches: Bool { plan.output?.touches ?? false }

    private var workingDirectory: URL {
        plan.app.cwd.map { URL(fileURLWithPath: $0, relativeTo: directory).standardizedFileURL } ?? directory
    }

    func prepare() async {
        if let build = plan.app.build, !build.isEmpty {
            log("building: \(build.joined(separator: " "))")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = build
            task.currentDirectoryURL = workingDirectory
            task.standardOutput = FileHandle.standardError
            do { try task.run() } catch { fail("build failed to start: \(error)") }
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { fail("build failed (exit \(task.terminationStatus))") }
        }
        let launch = plan.app.launch!
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        // AppKit reads these from the arguments, so the app's own defaults stay untouched.
        process.arguments = launch + tooltips.launchArguments
        process.currentDirectoryURL = workingDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["DEMO"] = "1"
        for (key, value) in plan.app.env ?? [:] { environment[key] = value }
        process.environment = environment
        let pipe = Pipe()
        process.standardInput = pipe
        do { try process.run() } catch { fail("couldn't launch \(launch[0]): \(error)") }
        self.process = process
        stdin = pipe

        let deadline = Date() + 30
        while windowFrames(of: processTree(process.processIdentifier), includeMenuBar: false).isEmpty {
            guard process.isRunning else { fail("\(launch[0]) exited before showing a window") }
            guard Date() < deadline else { fail("no window from \(launch[0]) within 30 s") }
            await sleep(seconds: 0.1)
        }
        for pid in processTree(process.processIdentifier) {
            makeFrontmost(pid)
        }
        await sleep(seconds: 0.3)
    }

    func startRecording() async -> Double {
        let settings = plan.output ?? OutputSpec()
        let recorder = WindowRecorder(root: process!.processIdentifier,
                                      settings: CaptureSettings(fps: settings.fps ?? 60, cursor: showPointer),
                                      raw: scratch.appendingPathComponent("raw.mov"))
        self.recorder = recorder
        do { zero = try await recorder.start(isAlive: { [process] in process?.isRunning ?? false }) } catch { fail("couldn't record: \(error)") }
        return zero
    }

    func stopRecording() async {
        await recorder?.stop()
    }

    func sendState(_ command: String) -> Bool {
        guard let stdin, process?.isRunning == true else { return false }
        stdin.fileHandleForWriting.write(Data((command + "\n").utf8))
        return true
    }

    func nodes() -> [AXNode] {
        guard let process else { return [] }
        // The recorder keeps the process tree current; don't spawn ps on every poll.
        return accessibilityTree(of: recorder?.pids ?? processTree(process.processIdentifier))
    }

    func area() -> CGRect {
        guard let process else { return .zero }
        return windowFrames(of: processTree(process.processIdentifier), includeMenuBar: false).first ?? .zero
    }

    func teardown() async {
        // Closing stdin asks a demo-aware app to quit; anything else gets SIGTERM.
        try? stdin?.fileHandleForWriting.close()
        let deadline = Date() + 1.5
        while process?.isRunning == true, Date() < deadline { await sleep(seconds: 0.05) }
        if process?.isRunning == true { process?.terminate() }
    }

    func export(end: Double, cues: [Cue], touches: [(time: Double, point: CGPoint)], outputs: Outputs, settings: OutputSpec) async -> (files: [URL], duration: Double) {
        guard let recorder, let crop = recorder.crop(padding: CGFloat(settings.padding ?? 40)), let first = recorder.frames.first else {
            fail("captured nothing visible")
        }
        let offset = zero - first.time
        let captionMode = settings.captions ?? "vtt"
        var job = ExportJob(source: recorder.raw, crop: crop, keep: 0...max(end + offset, 0.1), mov: outputs.mov, mp4: outputs.mp4, prores: outputs.prores,
                            background: settings.background.flatMap(parseColor) ?? CIColor(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEC / 255),
                            cues: cues, burnCaptions: ["burn", "both"].contains(captionMode), scale: recorder.scale, fps: settings.fps ?? 60)
        if drawsTouches {
            job.touches = touches.compactMap { touch in recorder.pixel(touch.point, in: crop).map { Touch(time: touch.time, point: $0) } }
        }
        let duration: Double
        do { duration = try await demo_video.export(job) } catch { fail("export failed: \(error)") }
        if recorder.dropped > 0 { log("\(recorder.dropped) frames dropped while recording") }
        return (outputs.finish(gifWidth: settings.gifWidth ?? 960, gifFPS: settings.gifFPS ?? 30, frameWidth: Int(crop.width)), duration)
    }
}

// MARK: - iOS Simulator

final class IOSBackend: Backend {
    let plan: Plan
    let directory: URL
    let scratch: URL
    private var udid = ""
    private var deviceName = ""
    private var recording: Process?
    private var raw: URL { scratch.appendingPathComponent("raw.mp4") }
    private var screen = CGRect.zero

    init(plan: Plan, directory: URL, scratch: URL) {
        self.plan = plan
        self.directory = directory
        self.scratch = scratch
    }

    var recordsPointer: Bool { false }
    var drawsTouches: Bool { plan.output?.touches ?? true }

    @discardableResult
    private func simctl(_ arguments: [String], environment: [String: String] = [:]) -> (status: Int32, output: String) {
        if environment.isEmpty { return run("/usr/bin/xcrun", ["simctl"] + arguments) }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["simctl"] + arguments
        task.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try? task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The plan's device, the booted one, or the newest iPhone.
    private func chooseDevice() -> (udid: String, name: String, booted: Bool) {
        struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
        struct List: Decodable { let devices: [String: [Device]] }
        guard let list = try? JSONDecoder().decode(List.self, from: Data(simctl(["list", "devices", "available", "-j"]).output.utf8)) else {
            fail("couldn't list simulators (is Xcode installed?)")
        }
        let runtimes = list.devices.keys.filter { $0.contains("iOS") }.sorted { a, b in
            a.compare(b, options: .numeric) == .orderedDescending
        }
        let devices = runtimes.flatMap { list.devices[$0] ?? [] }
        if let wanted = plan.app.device {
            if let device = devices.first(where: { $0.udid == wanted || $0.name == wanted }) {
                return (device.udid, device.name, device.state == "Booted")
            }
            return create(named: wanted)
        }
        if let booted = devices.first(where: { $0.state == "Booted" }) { return (booted.udid, booted.name, true) }
        let phones = devices.filter { $0.name.hasPrefix("iPhone") }
        if let device = phones.first(where: { $0.name.hasSuffix("Pro") }) ?? phones.first { return (device.udid, device.name, false) }
        return create(named: nil)
    }

    /// Creates a simulator on the newest iOS runtime: the named model, or the newest iPhone Pro.
    private func create(named wanted: String?) -> (udid: String, name: String, booted: Bool) {
        struct DeviceType: Decodable { let name: String; let identifier: String }
        struct Runtime: Decodable { let identifier: String; let name: String; let isAvailable: Bool; let supportedDeviceTypes: [DeviceType]? }
        struct List: Decodable { let runtimes: [Runtime] }
        guard let list = try? JSONDecoder().decode(List.self, from: Data(simctl(["list", "runtimes", "-j"]).output.utf8)),
              let runtime = list.runtimes.filter({ $0.isAvailable && $0.name.hasPrefix("iOS") })
                  .max(by: { $0.name.compare($1.name, options: .numeric) == .orderedAscending }) else {
            fail("no iOS simulator runtime installed (Xcode > Settings > Components)")
        }
        let types = (runtime.supportedDeviceTypes ?? []).filter { $0.name.hasPrefix("iPhone") }
        let type = wanted.map { name in types.first { $0.name == name } } ?? types.first { $0.name.hasSuffix("Pro") } ?? types.first
        guard let type else {
            fail("no simulator model named \(wanted ?? "iPhone") on \(runtime.name). Models: \(types.map(\.name).joined(separator: ", "))")
        }
        let created = simctl(["create", type.name, type.identifier, runtime.identifier])
        let udid = created.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard created.status == 0, !udid.isEmpty else { fail("couldn't create a \(type.name) simulator") }
        log("created simulator \(type.name) (\(runtime.name))")
        return (udid, type.name, false)
    }

    func prepare() async {
        let device = chooseDevice()
        udid = device.udid
        deviceName = device.name
        log("simulator: \(deviceName)")
        if !device.booted { simctl(["boot", udid]) }
        simctl(["bootstatus", udid, "-b"])
        if let appearance = plan.app.appearance { simctl(["ui", udid, "appearance", appearance]) }
        if plan.app.cleanStatusBar ?? true {
            simctl(["status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active", "--wifiBars", "3",
                    "--cellularMode", "active", "--cellularBars", "4", "--batteryState", "charged", "--batteryLevel", "100"])
        }
        if let install = plan.app.install {
            let path = URL(fileURLWithPath: install, relativeTo: directory).standardizedFileURL.path
            guard simctl(["install", udid, path]).status == 0 else { fail("couldn't install \(path)") }
        }
        let bundle = plan.app.bundleId!
        simctl(["terminate", udid, bundle])
        var environment = ["SIMCTL_CHILD_DEMO": "1"]
        for (key, value) in plan.app.env ?? [:] { environment["SIMCTL_CHILD_" + key] = value }
        guard simctl(["launch", udid, bundle] + (plan.app.args ?? []), environment: environment).status == 0 else {
            fail("couldn't launch \(bundle) on \(deviceName)")
        }
        await waitUntilDrawn()
        if needsHost {
            await showDevice()
            guard screen.width > 0 else {
                fail("couldn't find \(deviceName)'s screen in \(hostName). Keep its window open and visible, then retry.")
            }
        }
    }

    /// Taps, swipes, typing and expectations go through the app that shows the device.
    private var needsHost: Bool {
        plan.steps.contains { $0.movesPointer || ["type", "key", "expect", "expectGone"].contains($0.action) }
    }

    /// Waits until the device screen shows something and has stopped changing, so the take
    /// doesn't open on a black launch screen. A fresh simulator's first launch can take a while.
    private func waitUntilDrawn() async {
        let shot = scratch.appendingPathComponent("ready.png")
        var previous: [UInt8] = []
        let deadline = Date() + 45
        while Date() < deadline {
            simctl(["io", udid, "screenshot", "--type=png", shot.path])
            if let source = CGImageSourceCreateWithURL(shot as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                // A tiny greyscale thumbnail is enough to tell "drawn" and "settled".
                var pixels = [UInt8](repeating: 0, count: 24 * 48)
                let context = CGContext(data: &pixels, width: 24, height: 48, bitsPerComponent: 8, bytesPerRow: 24,
                                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
                context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 48))
                let lit = pixels.filter { $0 > 40 }.count
                let settled = previous.count == pixels.count && zip(previous, pixels).allSatisfy { abs(Int($0) - Int($1)) < 6 }
                screenPixels = CGSize(width: image.width, height: image.height)
                if lit > pixels.count / 50, settled { break }
                previous = pixels
            }
            await sleep(seconds: 0.4)
        }
        await sleep(seconds: 0.4)
    }

    /// Pixel size of the device screen, from the readiness screenshots.
    private var screenPixels = CGSize.zero

    /// Simulator.app before Xcode 27, Device Hub from Xcode 27. Both expose the running iOS
    /// app's accessibility tree inside their device window.
    private static let hosts = [(bundle: "com.apple.iphonesimulator", executable: "Simulator", name: "Simulator"),
                                (bundle: "com.apple.dt.Devices", executable: "DeviceHub", name: "Device Hub")]
    private var hostName = "Simulator"
    private var hostBundle: String?

    /// From the process table: NSRunningApplication reports Device Hub's PID as -1.
    private var hostPID: pid_t? {
        let processes = run("/bin/ps", ["-axo", "pid=,comm="]).output.split(separator: "\n")
        for host in Self.hosts {
            if let line = processes.first(where: { $0.hasSuffix("/Contents/MacOS/\(host.executable)") }),
               let pid = pid_t(line.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") {
                hostName = host.name
                hostBundle = host.bundle
                return pid
            }
        }
        return nil
    }

    /// Opens the host app on the device, brings it forward, and finds the device's screen.
    private func showDevice() async {
        if hostPID == nil {
            if run("/usr/bin/open", ["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid]).status != 0 {
                let developer = run("/usr/bin/xcode-select", ["-p"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
                let hub = URL(fileURLWithPath: developer).deletingLastPathComponent().appendingPathComponent("Applications/DeviceHub.app")
                guard run("/usr/bin/open", [hub.path]).status == 0 else { fail("couldn't open Simulator or Device Hub") }
            }
        }
        let deadline = Date() + 20
        while Date() < deadline {
            if let pid = hostPID, let bundle = hostBundle {
                run("/usr/bin/open", ["-b", bundle])
                let nodes = accessibilityTree(of: [pid])
                // Device Hub shows one device at a time: pick ours in the sidebar if needed.
                if let window = nodes.first(where: { $0.role == "AXWindow" }), !window.title.contains(deviceName),
                   let row = nodes.first(where: { $0.identifier == "TableRow.Device.\(udid)" }) {
                    await Input.click(at: row.center)
                    await sleep(seconds: 1)
                    continue
                }
                if let found = findScreen(in: nodes) {
                    screen = found
                    return
                }
            }
            await sleep(seconds: 0.5)
        }
    }

    /// The device's screen: the largest element shaped like the recording.
    private func findScreen(in nodes: [AXNode]) -> CGRect? {
        guard screenPixels.width > 0 else { return nil }
        let aspect = screenPixels.width / screenPixels.height
        return nodes
            .filter { $0.frame.width > 100 && abs($0.frame.width / $0.frame.height - aspect) < aspect * 0.015 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }?
            .frame
    }

    func startRecording() async -> Double {
        try? FileManager.default.removeItem(at: raw)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = ["simctl", "io", udid, "recordVideo", "--codec=h264", "--force", raw.path]
        let errors = Pipe()
        task.standardError = errors
        task.standardOutput = FileHandle.nullDevice
        do { try task.run() } catch { fail("couldn't start simctl recordVideo: \(error)") }
        recording = task
        var seen = ""
        let deadline = Date() + 10
        while !seen.contains("Recording started"), Date() < deadline {
            let chunk = errors.fileHandleForReading.availableData
            if chunk.isEmpty { await sleep(seconds: 0.05) } else { seen += String(decoding: chunk, as: UTF8.self) }
        }
        guard seen.contains("Recording started") else { fail("simctl recordVideo didn't start: \(seen)") }
        return hostSeconds()
    }

    func stopRecording() async {
        guard let recording else { return }
        recording.interrupt()
        while recording.isRunning { await sleep(seconds: 0.05) }
    }

    func sendState(_ command: String) -> Bool {
        guard let scheme = plan.app.urlScheme else { return false }
        var components = URLComponents()
        components.scheme = scheme
        components.host = "demo"
        components.queryItems = [URLQueryItem(name: "cmd", value: command)]
        guard let url = components.url else { return false }
        return simctl(["openurl", udid, url.absoluteString]).status == 0
    }

    func nodes() -> [AXNode] {
        guard let pid = hostPID else { return [] }
        let screen = area()
        return accessibilityTree(of: [pid]).filter { screen.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) && $0.frame != screen }
    }

    func area() -> CGRect { screen }

    func teardown() async {
        if plan.app.cleanStatusBar ?? true { simctl(["status_bar", udid, "clear"]) }
    }

    func export(end: Double, cues: [Cue], touches: [(time: Double, point: CGPoint)], outputs: Outputs, settings: OutputSpec) async -> (files: [URL], duration: Double) {
        guard let track = try? await AVURLAsset(url: raw).loadTracks(withMediaType: .video).first,
              let asset = try? await track.load(.naturalSize) else { fail("simulator recording is unreadable: \(raw.path)") }
        let captionMode = settings.captions ?? "vtt"
        // Points on the Mac screen to pixels in the device recording.
        let factor = screen.width > 0 ? asset.width / screen.width : 1
        // Captions are sized in device points; iPhones are about 400 pt wide.
        var job = ExportJob(source: raw, crop: nil, keep: 0...max(end, 0.1), mov: outputs.mov, mp4: outputs.mp4, prores: outputs.prores,
                            background: settings.background.flatMap(parseColor) ?? CIColor(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEC / 255),
                            cues: cues, burnCaptions: ["burn", "both"].contains(captionMode),
                            scale: (asset.width / 402).rounded(), fps: settings.fps ?? 60)
        if drawsTouches, screen.width > 0 {
            job.touches = touches.map { Touch(time: $0.time, point: CGPoint(x: ($0.point.x - screen.minX) * factor, y: ($0.point.y - screen.minY) * factor)) }
        }
        let duration: Double
        do { duration = try await demo_video.export(job) } catch { fail("export failed: \(error)") }
        return (outputs.finish(gifWidth: settings.gifWidth ?? 480, gifFPS: settings.gifFPS ?? 30, frameWidth: Int(asset.width)), duration)
    }
}
