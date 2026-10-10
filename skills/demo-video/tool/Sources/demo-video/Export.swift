import AVFoundation
import CoreImage
import CoreText
import Foundation

/// A caption shown from `start` to `end`, in seconds from the start of the kept range.
struct Cue {
    var start: Double
    var end: Double
    var text: String
}

/// A tap to draw, at a pixel position in the cropped frame (top-left origin).
struct Touch {
    var time: Double
    var point: CGPoint
}

struct ExportJob {
    var source: URL
    /// Top-left-origin pixels of the source; nil keeps the whole frame.
    var crop: CGRect?
    /// Seconds from the source's first frame.
    var keep: ClosedRange<Double>
    var mov: URL?
    var mp4: URL?
    /// ProRes 4444 with alpha, for webm conversion.
    var prores: URL?
    var background: CIColor
    var cues: [Cue] = []
    var burnCaptions = false
    var touches: [Touch] = []
    /// Points to pixels, for sizing captions and touches.
    var scale: CGFloat = 2
    var fps = 60
}

private struct Writer {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let flatten: Bool

    init(url: URL, type: AVFileType, settings: [String: Any], size: CGSize, flatten: Bool) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: type)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        self.flatten = flatten
    }
}

func h264Settings(width: Int, height: Int) -> [String: Any] {
    [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: max(width * height * 6, 4_000_000),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ] as [String: Any],
    ]
}

/// Crops, trims and decorates `job.source`, writing each requested file. Returns the duration.
@discardableResult
func export(_ job: ExportJob) async throws -> Double {
    let asset = AVURLAsset(url: job.source)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { fail("\(job.source.lastPathComponent) has no video") }
    let natural = try await track.load(.naturalSize)
    let reader = try AVAssetReader(asset: asset)
    let source = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    source.alwaysCopiesSampleData = false
    reader.add(source)

    let crop = job.crop ?? CGRect(origin: .zero, size: natural)
    // Burned captions sit in a band below the content, so they never cover the UI.
    let captionBand = job.burnCaptions && !job.cues.isEmpty ? (52 * job.scale).rounded() : 0
    let size = CGSize(width: crop.width, height: crop.height + captionBand)

    var writers: [Writer] = []
    if let mov = job.mov {
        writers.append(try Writer(url: mov, type: .mov, settings: hevcAlphaSettings(width: Int(size.width), height: Int(size.height), quality: 0.85), size: size, flatten: false))
    }
    if let mp4 = job.mp4 {
        writers.append(try Writer(url: mp4, type: .mp4, settings: h264Settings(width: Int(size.width), height: Int(size.height)), size: size, flatten: true))
    }
    if let prores = job.prores {
        writers.append(try Writer(url: prores, type: .mov, settings: [
            AVVideoCodecKey: AVVideoCodecType.proRes4444, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
        ], size: size, flatten: false))
    }
    for output in writers {
        guard output.writer.startWriting() else { throw output.writer.error ?? CocoaError(.fileWriteUnknown) }
        output.writer.startSession(atSourceTime: .zero)
    }
    guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

    // No colour management: pixels pass through as captured.
    let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
    let ciCrop = CGRect(x: crop.minX, y: natural.height - crop.maxY, width: crop.width, height: crop.height)
    let bounds = CGRect(origin: .zero, size: size)
    let backdrop = CIImage(color: job.background).cropped(to: bounds)
    let captions = job.burnCaptions ? CaptionRenderer(scale: job.scale) : nil
    let touchImage = job.touches.isEmpty ? nil : TouchRenderer.image(scale: job.scale)

    // Resample to a constant frame rate, holding the latest source frame: recorders only
    // deliver frames when something changes, but captions and touches animate regardless.
    let frameDuration = 1 / Double(job.fps)
    let length = job.keep.upperBound - job.keep.lowerBound
    var pending = source.copyNextSampleBuffer()
    let base = pending?.presentationTimeStamp ?? .zero
    var current: CIImage?
    var count = 0
    while true {
        let time = Double(count) * frameDuration
        if time > length + frameDuration / 2 { break }
        while let sample = pending, (sample.presentationTimeStamp - base).seconds <= time + job.keep.lowerBound + 0.0005 {
            if let pixels = sample.imageBuffer {
                current = CIImage(cvPixelBuffer: pixels)
                    .cropped(to: ciCrop)
                    .transformed(by: CGAffineTransform(translationX: -ciCrop.minX, y: -ciCrop.minY + captionBand))
            }
            pending = source.copyNextSampleBuffer()
        }
        count += 1
        guard var image = current else { continue }
        if let touchImage {
            for touch in job.touches {
                if let overlay = TouchRenderer.overlay(touchImage, touch: touch, at: time, height: crop.height, band: captionBand) {
                    image = overlay.composited(over: image)
                }
            }
        }
        if let captions, let cue = job.cues.first(where: { time >= $0.start && time < $0.end }) {
            image = captions.overlay(cue, at: time, width: size.width, band: captionBand).composited(over: image)
        }
        let presentation = CMTime(seconds: time, preferredTimescale: 6000)
        for output in writers {
            while !output.input.isReadyForMoreMediaData { await sleep(seconds: 0.002) }
            guard let pool = output.adaptor.pixelBufferPool else { throw output.writer.error ?? CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { continue }
            context.render(output.flatten ? image.composited(over: backdrop) : image, to: buffer, bounds: bounds, colorSpace: nil)
            output.adaptor.append(buffer, withPresentationTime: presentation)
        }
    }
    reader.cancelReading()
    guard current != nil else { fail("no frames in the kept range of \(job.source.lastPathComponent)") }
    let end = Double(count) * frameDuration
    for output in writers {
        output.input.markAsFinished()
        output.writer.endSession(atSourceTime: CMTime(seconds: end, preferredTimescale: 6000))
        await output.writer.finishWriting()
        if output.writer.status != .completed { throw output.writer.error ?? CocoaError(.fileWriteUnknown) }
    }
    return end
}

/// Draws captions as a dark pill, centred in the band below the content, or near the
/// bottom of the frame when there's no band.
final class CaptionRenderer {
    let scale: CGFloat
    private var cache: [String: CIImage] = [:]

    init(scale: CGFloat) { self.scale = scale }

    func overlay(_ cue: Cue, at time: Double, width: CGFloat, band: CGFloat) -> CIImage {
        let pill = image(for: cue.text)
        let fade = min(1, min(time - cue.start, cue.end - time) / 0.18)
        let x = ((width - pill.extent.width) / 2).rounded()
        let y = band > 0 ? ((band - pill.extent.height) / 2).rounded() : (28 * scale).rounded()
        return pill
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, fade))])
            .transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private func image(for text: String) -> CIImage {
        if let cached = cache[text] { return cached }
        let font = CTFontCreateUIFontForLanguage(.system, 15 * scale, nil) ?? CTFontCreateWithName("Helvetica" as CFString, 15 * scale, nil)
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let padX = 14 * scale, padY = 7 * scale
        let size = CGSize(width: (textWidth + padX * 2).rounded(.up), height: (ascent + descent + padY * 2).rounded(.up))
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let path = CGPath(roundedRect: CGRect(origin: .zero, size: size), cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil)
        context.addPath(path)
        context.setFillColor(CGColor(gray: 0.08, alpha: 0.82))
        context.fillPath()
        context.textPosition = CGPoint(x: padX, y: padY + descent)
        CTLineDraw(line, context)
        let image = CIImage(cgImage: context.makeImage()!)
        cache[text] = image
        return image
    }
}

/// A soft circle that appears at a tap and grows as it fades.
enum TouchRenderer {
    static let duration = 0.45

    static func image(scale: CGFloat) -> CIImage {
        let diameter = (44 * scale).rounded()
        let context = CGContext(data: nil, width: Int(diameter), height: Int(diameter), bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: diameter, height: diameter).insetBy(dx: 2 * scale, dy: 2 * scale)
        // Grey with a white ring, so it reads on light and dark UIs alike.
        context.setFillColor(CGColor(gray: 0.3, alpha: 0.32))
        context.fillEllipse(in: rect)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.75))
        context.setLineWidth(2 * scale)
        context.strokeEllipse(in: rect)
        return CIImage(cgImage: context.makeImage()!)
    }

    static func overlay(_ image: CIImage, touch: Touch, at time: Double, height: CGFloat, band: CGFloat) -> CIImage? {
        let age = time - touch.time
        guard age >= -0.06, age < duration else { return nil }
        let progress = max(0, age) / duration
        let grow = 1 + 0.35 * progress
        let alpha = 1 - progress * progress
        let size = image.extent.width * grow
        let x = touch.point.x - size / 2
        let y = height - touch.point.y - size / 2 + band
        return image
            .transformed(by: CGAffineTransform(scaleX: grow, y: grow))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
            .transformed(by: CGAffineTransform(translationX: x, y: y))
    }
}

func writeVTT(_ cues: [Cue], to url: URL) throws {
    func stamp(_ seconds: Double) -> String {
        let total = max(0, seconds)
        return String(format: "%02d:%02d:%06.3f", Int(total) / 3600, Int(total) / 60 % 60, total.truncatingRemainder(dividingBy: 60))
    }
    var text = "WEBVTT\n"
    for (index, cue) in cues.enumerated() {
        text += "\n\(index + 1)\n\(stamp(cue.start)) --> \(stamp(cue.end))\n\(cue.text)\n"
    }
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func makeGIF(from mp4: URL, to gif: URL, width: Int, fps: Int) -> Bool {
    guard let ffmpeg = ffmpegPath() else { log("ffmpeg not found, skipping gif (brew install ffmpeg)"); return false }
    return run(ffmpeg, [
        "-y", "-loglevel", "error", "-i", mp4.path,
        "-vf", "fps=\(fps),scale=\(width):-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a",
        gif.path,
    ], quiet: false).status == 0
}

/// VP9 with alpha, for Chrome and Firefox (Safari plays the HEVC .mov).
func makeWebM(from prores: URL, to webm: URL) -> Bool {
    guard let ffmpeg = ffmpegPath() else { log("ffmpeg not found, skipping webm (brew install ffmpeg)"); return false }
    return run(ffmpeg, [
        "-y", "-loglevel", "error", "-i", prores.path,
        "-c:v", "libvpx-vp9", "-pix_fmt", "yuva420p", "-b:v", "0", "-crf", "30", "-row-mt", "1", "-auto-alt-ref", "0",
        webm.path,
    ], quiet: false).status == 0
}

/// Output files for a base path and a set of formats.
struct Outputs {
    let base: URL
    let formats: Set<String>
    let scratch: URL

    var mov: URL? { formats.contains("mov") ? base.appendingPathExtension("mov") : nil }
    /// Written when asked for, or as the source of a gif.
    var mp4: URL? { formats.contains("mp4") || formats.contains("gif") ? (formats.contains("mp4") ? base.appendingPathExtension("mp4") : scratch.appendingPathComponent("flat.mp4")) : nil }
    var prores: URL? { formats.contains("webm") ? scratch.appendingPathComponent("alpha.mov") : nil }

    /// Makes gif and webm from the intermediates, then lists everything written.
    func finish(gifWidth: Int, gifFPS: Int, frameWidth: Int) -> [URL] {
        var written = [mov, formats.contains("mp4") ? mp4 : nil].compactMap { $0 }
        if formats.contains("webm"), let prores {
            let webm = base.appendingPathExtension("webm")
            if makeWebM(from: prores, to: webm) { written.append(webm) }
        }
        if formats.contains("gif"), let mp4 {
            let gif = base.appendingPathExtension("gif")
            if makeGIF(from: mp4, to: gif, width: min(gifWidth, frameWidth), fps: gifFPS) { written.append(gif) }
        }
        try? FileManager.default.removeItem(at: scratch)
        return written
    }

    static func make(base: URL, formats: Set<String>) -> Outputs {
        let unknown = formats.subtracting(["mov", "mp4", "gif", "webm"])
        guard unknown.isEmpty else { fail("unknown format \(unknown.sorted().joined(separator: ",")) (use mov, mp4, gif, webm)") }
        try? FileManager.default.createDirectory(at: base.deletingLastPathComponent(), withIntermediateDirectories: true)
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("demo-video-\(getpid())")
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        return Outputs(base: base, formats: formats, scratch: scratch)
    }
}
