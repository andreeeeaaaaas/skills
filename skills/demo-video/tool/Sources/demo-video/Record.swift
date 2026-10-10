import AVFoundation
import AppKit
import Foundation
import ScreenCaptureKit

let recordUsage = """
Usage:
  demo-video record --out <path> [options] -- <command> [args...]   launch, record until it exits
  demo-video record --out <path> [options] --pid <pid>              attach, record until Ctrl-C or --duration
  demo-video record --out <path> [options] --app <name|bundle-id>   same, by app name

Records one macOS app's windows with transparency and shadows, cropped to where they went.
<path> is a base name; extensions come from --formats.

Options:
  --formats <list>     mov,mp4,gif,webm (default mov,mp4)
  --background <hex>   flatten colour for mp4 and gif (default ececec)
  --padding <pt>       margin around the windows (default 40)
  --fps <n>            capture rate (default 60)
  --gif-width <px>     default 960; --gif-fps <n> default 30
  --duration <s>       stop after this many seconds
  --cursor             show the pointer
  --include-menubar    also capture the app's menu bar extras
"""

func recordCommand(_ arguments: [String]) async {
    let args = Arguments(arguments, flags: ["cursor", "include-menubar", "help"])
    if args.has("help") || arguments.isEmpty { print(recordUsage); exit(0) }
    guard let out = args["out"] else { fail("--out is required\n\n\(recordUsage)") }
    let outputs = Outputs.make(base: URL(fileURLWithPath: out).deletingPathExtension(), formats: Set((args["formats"] ?? "mov,mp4").split(separator: ",").map(String.init)))
    var background = CIColor(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEC / 255)
    if let value = args["background"] {
        guard let color = parseColor(value) else { fail("--background wants a hex colour like ececec") }
        background = color
    }
    let fps = args.int("fps") ?? 60

    var child: Process?
    let root: pid_t
    if !args.command.isEmpty {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args.command
        do { try process.run() } catch { fail("couldn't launch \(args.command[0]): \(error)") }
        child = process
        root = process.processIdentifier
    } else if let pid = args.int("pid") {
        root = pid_t(pid)
    } else if let name = args["app"] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name || $0.bundleIdentifier == name }) else { fail("no running app named \(name)") }
        root = app.processIdentifier
    } else {
        fail("give a command after --, or --pid / --app\n\n\(recordUsage)")
    }

    var stopRequested = false
    signal(SIGINT, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    interrupt.setEventHandler { stopRequested = true }
    interrupt.resume()

    let recorder = WindowRecorder(root: root, settings: CaptureSettings(fps: fps, cursor: args.has("cursor"), includeMenuBar: args.has("include-menubar")),
                                  raw: outputs.scratch.appendingPathComponent("raw.mov"))
    let isAlive = { child.map(\.isRunning) ?? (kill(root, 0) == 0) }
    let zero: Double
    do { zero = try await recorder.start(isAlive: isAlive) } catch { fail("couldn't record: \(error)") }
    log("recording\(child == nil ? " (Ctrl-C to stop)" : "")")
    while !stopRequested, isAlive() {
        if let duration = args.double("duration"), hostSeconds() - zero >= duration { break }
        await sleep(seconds: 0.05)
    }
    await recorder.stop()
    if let child, child.isRunning { child.terminate() }

    guard let first = recorder.frames.first(where: { !$0.empty }), let last = recorder.frames.last(where: { !$0.empty }),
          let crop = recorder.crop(padding: CGFloat(args.double("padding") ?? 40)) else {
        fail("captured nothing visible (\(recorder.frames.count) frames)")
    }
    let start = recorder.frames[0].time
    let job = ExportJob(source: recorder.raw, crop: crop, keep: (first.time - start)...(last.time - start),
                        mov: outputs.mov, mp4: outputs.mp4, prores: outputs.prores, background: background, scale: recorder.scale, fps: fps)
    let duration: Double
    do { duration = try await export(job) } catch { fail("export failed: \(error)") }
    let written = outputs.finish(gifWidth: args.int("gif-width") ?? 960, gifFPS: args.int("gif-fps") ?? 30, frameWidth: Int(crop.width))
    log(String(format: "%.1f s, %d×%d px, %d dropped frames", duration, Int(crop.width), Int(crop.height), recorder.dropped))
    for url in written { print(url.path) }
}

// MARK: - Frames

let framesUsage = """
Usage: demo-video frames <video> [--at 0,1.5,3 | --every <s>] [--width <px>] --out <sheet.png>

A contact sheet of frames, each labelled with its time, for checking a take.
Transparent videos are shown on a checkerboard.
"""

func framesCommand(_ arguments: [String]) async {
    let args = Arguments(arguments, flags: ["help"])
    guard !args.has("help"), let path = args.positional.first, let out = args["out"] else { print(framesUsage); exit(args.has("help") ? 0 : 1) }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let duration = (try? await asset.load(.duration).seconds) ?? 0
    guard duration > 0 else { fail("can't read \(path)") }
    var times: [Double]
    if let list = args["at"] {
        times = list.split(separator: ",").compactMap { Double($0) }
    } else {
        let every = args.double("every") ?? max(duration / 8, 0.5)
        times = Array(stride(from: 0, to: duration, by: every))
    }
    times = times.map { min($0, max(duration - 0.05, 0)) }

    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    generator.appliesPreferredTrackTransform = true
    let width = CGFloat(args.int("width") ?? 900)
    var images: [(Double, CGImage)] = []
    for time in times {
        if let image = try? await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image {
            images.append((time, image))
        }
    }
    guard let firstImage = images.first?.1 else { fail("no frames read from \(path)") }
    let rowHeight = (width * CGFloat(firstImage.height) / CGFloat(firstImage.width)).rounded()
    let label: CGFloat = 26, gap: CGFloat = 10
    let height = CGFloat(images.count) * (rowHeight + label + gap) + gap
    let context = CGContext(data: nil, width: Int(width + gap * 2), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width + gap * 2, height: height))
    for (index, (time, image)) in images.enumerated() {
        let top = height - gap - CGFloat(index) * (rowHeight + label + gap)
        let rect = CGRect(x: gap, y: top - label - rowHeight, width: width, height: rowHeight)
        // Checkerboard behind transparent frames.
        let tile: CGFloat = 12
        for row in 0..<Int(rowHeight / tile + 1) {
            for column in 0..<Int(width / tile + 1) {
                context.setFillColor(CGColor(gray: (row + column) % 2 == 0 ? 0.86 : 0.76, alpha: 1))
                context.fill(CGRect(x: rect.minX + CGFloat(column) * tile, y: rect.minY + CGFloat(row) * tile, width: tile, height: tile).intersection(rect))
            }
        }
        context.draw(image, in: rect)
        let text = NSAttributedString(string: String(format: "%.2f s", time), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.black,
        ])
        context.textPosition = CGPoint(x: gap, y: top - label + 7)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)
    }
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    do { try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out)) } catch { fail("can't write \(out): \(error)") }
    print(out)
}
