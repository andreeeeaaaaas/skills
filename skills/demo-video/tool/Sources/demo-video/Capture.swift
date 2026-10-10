import AVFoundation
import Foundation
import ScreenCaptureKit
import VideoToolbox

/// Menu bar and status item window levels. Left out unless asked for.
let menuBarLayers: Set<Int> = [24, 25]

/// The root PID and everything it spawned, so wrappers like `swift run` or `npm` still find the app.
func processTree(_ root: pid_t) -> Set<pid_t> {
    var children: [pid_t: [pid_t]] = [:]
    for line in run("/bin/ps", ["-axo", "pid=,ppid="]).output.split(separator: "\n") {
        let fields = line.split(separator: " ").compactMap { pid_t($0) }
        if fields.count == 2 { children[fields[1], default: []].append(fields[0]) }
    }
    var result: Set<pid_t> = [root]
    var queue = [root]
    while let next = queue.popLast() {
        for child in children[next] ?? [] where result.insert(child).inserted { queue.append(child) }
    }
    return result
}

/// On-screen window frames owned by `pids`, in global top-left-origin points.
func windowFrames(of pids: Set<pid_t>, includeMenuBar: Bool) -> [CGRect] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info in
        guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(owner),
              let layer = info[kCGWindowLayer as String] as? Int,
              includeMenuBar || !menuBarLayers.contains(layer),
              (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds),
              rect.width > 2, rect.height > 2
        else { return nil }
        return rect
    }
}

func requireScreenRecording() {
    guard CGPreflightScreenCaptureAccess() else {
        fail("needs Screen Recording permission for this terminal: System Settings > Privacy & Security > Screen & System Audio Recording")
    }
}

struct CaptureSettings {
    var fps = 60
    var cursor = false
    var includeMenuBar = false
}

/// Records one app's windows over a clear background: the whole display, keeping only that
/// app, written to an intermediate HEVC-with-alpha movie. Tracks where the windows went so
/// the export can crop to them.
final class WindowRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    let root: pid_t
    let settings: CaptureSettings
    let raw: URL

    private(set) var pids: Set<pid_t>
    private(set) var display: SCDisplay?
    private(set) var scale: CGFloat = 2
    private(set) var pixelSize = CGSize.zero
    /// Union of the app's window frames seen while recording, in global points.
    private(set) var covered = CGRect.null
    /// Host-clock time of every written frame, and whether it was empty.
    private(set) var frames: [(time: Double, empty: Bool)] = []
    private(set) var dropped = 0
    private(set) var error: Error?

    private let queue = DispatchQueue(label: "demo-video.capture")
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var started = false
    private var stopped = false
    private var firstFrame: CheckedContinuation<Double, Never>?
    private var tracker: Task<Void, Never>?

    init(root: pid_t, settings: CaptureSettings, raw: URL) {
        self.root = root
        self.settings = settings
        self.raw = raw
        pids = [root]
    }

    /// Waits for the app's first window, starts capturing, and returns the host time of the
    /// first frame: time zero for anything scheduled against the recording.
    func start(timeout: Double = 30, isAlive: () -> Bool) async throws -> Double {
        requireScreenRecording()
        let deadline = Date() + timeout
        var target: (SCDisplay, [SCRunningApplication], [SCWindow])?
        while target == nil {
            guard isAlive() else { fail("the app exited before showing a window") }
            guard Date() < deadline else { fail("no window from pid \(root) within \(Int(timeout)) s") }
            pids = processTree(root)
            // The display list is briefly empty at times (display changes, sleep); just retry.
            if let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true), !content.displays.isEmpty {
                let owned = content.windows.filter { pids.contains($0.owningApplication?.processID ?? -1) }
                let visible = owned.filter { (settings.includeMenuBar || !menuBarLayers.contains($0.windowLayer)) && $0.frame.width > 2 }
                if let first = visible.first {
                    let display = content.displays.first { $0.frame.intersects(first.frame) } ?? content.displays[0]
                    let apps = content.applications.filter { pids.contains($0.processID) }
                    let excluded = settings.includeMenuBar ? [] : owned.filter { menuBarLayers.contains($0.windowLayer) }
                    target = (display, apps, excluded)
                    break
                }
            }
            await sleep(seconds: 0.1)
        }
        let (display, apps, excluded) = target!
        self.display = display
        let mode = CGDisplayCopyDisplayMode(display.displayID)
        scale = mode.map { CGFloat($0.pixelWidth) / CGFloat($0.width) } ?? 2
        pixelSize = CGSize(width: (CGFloat(display.width) * scale).rounded(), height: (CGFloat(display.height) * scale).rounded())

        let configuration = SCStreamConfiguration()
        configuration.width = Int(pixelSize.width)
        configuration.height = Int(pixelSize.height)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.backgroundColor = .clear
        configuration.showsCursor = settings.cursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        configuration.queueDepth = 8
        configuration.ignoreShadowsDisplay = false

        try? FileManager.default.removeItem(at: raw)
        let writer = try AVAssetWriter(outputURL: raw, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: hevcAlphaSettings(width: Int(pixelSize.width), height: Int(pixelSize.height), quality: 0.95))
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        self.writer = writer
        self.input = input

        let stream = SCStream(filter: SCContentFilter(display: display, including: apps, exceptingWindows: excluded), configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        let zero = await withCheckedContinuation { continuation in
            queue.sync { firstFrame = continuation }
            Task {
                do { try await stream.startCapture() } catch { fail("couldn't start capture: \(error)") }
            }
        }
        tracker = Task { [weak self] in
            var lastTree = Date()
            while !Task.isCancelled, let self {
                if Date().timeIntervalSince(lastTree) > 1 {
                    self.pids = processTree(self.root)
                    lastTree = Date()
                }
                for frame in windowFrames(of: self.pids, includeMenuBar: self.settings.includeMenuBar) {
                    self.covered = self.covered.union(frame)
                }
                await sleep(seconds: 0.05)
            }
        }
        return zero
    }

    func stop() async {
        tracker?.cancel()
        try? await stream?.stopCapture()
        queue.sync { stopped = true }
        guard let writer, let input else { return }
        guard started else { writer.cancelWriting(); return }
        input.markAsFinished()
        await writer.finishWriting()
    }

    /// The area to export, in top-left-origin pixels of the raw capture: everywhere the
    /// windows went, plus `padding` points, clamped to the display, with even dimensions.
    func crop(padding: CGFloat) -> CGRect? {
        guard let display, !covered.isNull else { return nil }
        let local = covered.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        var crop = CGRect(x: (local.minX * scale).rounded(.down), y: (local.minY * scale).rounded(.down),
                          width: (local.width * scale).rounded(.up), height: (local.height * scale).rounded(.up))
        crop.size.width -= crop.width.truncatingRemainder(dividingBy: 2)
        crop.size.height -= crop.height.truncatingRemainder(dividingBy: 2)
        return crop
    }

    /// Converts a global point to pixels within `crop`.
    func pixel(_ point: CGPoint, in crop: CGRect) -> CGPoint? {
        guard let display else { return nil }
        return CGPoint(x: (point.x - display.frame.minX) * scale - crop.minX, y: (point.y - display.frame.minY) * scale - crop.minY)
    }

    // MARK: SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !stopped, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixels = sampleBuffer.imageBuffer, let writer, let input, let adaptor
        else { return }
        let time = sampleBuffer.presentationTimeStamp
        if !started {
            writer.startSession(atSourceTime: time)
            started = true
            firstFrame?.resume(returning: time.seconds)
            firstFrame = nil
        }
        guard input.isReadyForMoreMediaData else { dropped += 1; return }
        if adaptor.append(pixels, withPresentationTime: time) {
            frames.append((time.seconds, isTransparent(pixels)))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.error = error
    }
}

/// True when a sparse grid of the frame is fully transparent: nothing of the app on screen.
func isTransparent(_ buffer: CVPixelBuffer) -> Bool {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return false }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    for y in stride(from: 0, to: height, by: 6) {
        let row = bytes + y * rowBytes
        for x in stride(from: 0, to: width, by: 6) where row[x * 4 + 3] > 3 {
            return false
        }
    }
    return true
}

func hevcAlphaSettings(width: Int, height: Int, quality: Double) -> [String: Any] {
    [
        AVVideoCodecKey: AVVideoCodecType.hevcWithAlpha,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoQualityKey: quality,
            kVTCompressionPropertyKey_TargetQualityForAlpha as String: quality,
            kVTCompressionPropertyKey_AlphaChannelMode as String: kVTAlphaChannelMode_PremultipliedAlpha,
        ] as [String: Any],
    ]
}
