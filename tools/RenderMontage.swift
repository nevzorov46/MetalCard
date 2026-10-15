// Cuts the phone recording together with the rendered walkthrough.
//
//   swift tools/RenderMontage.swift out.mp4 \
//     -phone sim.mp4 -in 12.4 -receipt 17.6 \
//     -diagram docs/post.mp4
//
// Three movements: the phone plays with a slow push, the camera drives into the
// receipt, and the walkthrough takes over. Everything is drawn into one canvas and
// encoded once, so there is no generation loss and no editor to install.

import AVFoundation
import AppKit

// MARK: - Arguments

func argument(_ name: String, _ fallback: Double) -> Double {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count,
          let value = Double(CommandLine.arguments[i + 1]) else { return fallback }
    return value
}
func path(_ name: String, _ fallback: String) -> String {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count
    else { return fallback }
    return CommandLine.arguments[i + 1]
}

let outPath   = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-")
                ? CommandLine.arguments[1] : "montage.mp4"
let phonePath = path("-phone", "")
let diagramPath = path("-diagram", "docs/post.mp4")
let phoneIn   = argument("-in", 0)            // where the phone clip starts being interesting
let receiptAt = argument("-receipt", 0)        // where the receipt lands, in the phone clip
let holdAfter = argument("-hold", 2.4)         // how long to sit on the receipt

guard !phonePath.isEmpty else {
    print("need -phone <file>")
    exit(1)
}

// MARK: - Canvas

let W = 1080, H = 1350
let fps: Int32 = 30
let bg   = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.055, alpha: 1)
let ink  = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink3 = NSColor(srgbRed: 0.353, green: 0.361, blue: 0.376, alpha: 1)

func serif(_ size: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}
func sans(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: size, weight: w) }

func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func fade(_ t: Double, _ from: Double, _ over: Double) -> CGFloat {
    CGFloat(min(1, max(0, (t - from) / over)))
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(max(0, min(1, t))) }

// MARK: - Reading a clip frame by frame

/// Pulls frames in order and hands back the one that belongs at a given time.
/// Sequential because the montage never goes backwards.
final class Clip {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var current: (image: CGImage, time: Double)?
    private var next: (image: CGImage, time: Double)?
    let size: CGSize
    let duration: Double

    init(path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let track = try awaitValue { try await asset.loadTracks(withMediaType: .video).first }
        guard let track else { throw NSError(domain: "clip", code: 1) }
        size = try awaitValue { try await track.load(.naturalSize) } ?? .zero
        duration = try awaitValue { try await asset.load(.duration) }.map(CMTimeGetSeconds) ?? 0
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
        reader.add(output)
        reader.startReading()
        next = pull()
    }

    private func pull() -> (CGImage, Double)? {
        guard let sample = output.copyNextSampleBuffer(),
              let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                            width: CVPixelBufferGetWidth(buffer),
                            height: CVPixelBufferGetHeight(buffer),
                            bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = ctx?.makeImage() else { return nil }
        return (image, time)
    }

    /// The frame showing at `time`, or the last one if the clip has run out.
    func frame(at time: Double) -> CGImage? {
        while let candidate = next, candidate.time <= time {
            current = candidate
            next = pull()
        }
        return current?.image ?? next?.image
    }
}

/// Bridges the async-only AVFoundation loaders into this straight-line script.
func awaitValue<T>(_ body: @escaping () async throws -> T?) throws -> T? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?
    var failure: Error?
    Task {
        do { result = try await body() } catch { failure = error }
        semaphore.signal()
    }
    semaphore.wait()
    if let failure { throw failure }
    return result
}

// MARK: - Placing a source frame on the canvas

/// Draws `image` so that `focus` (in 0...1 of the source) sits at the canvas centre,
/// scaled so the source fits the canvas height and then zoomed by `zoom`.
func place(_ image: CGImage, in ctx: CGContext, zoom: CGFloat,
           focus: CGPoint = CGPoint(x: 0.5, y: 0.5), alpha: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    let base = CGFloat(H) / CGFloat(image.height)
    let w = CGFloat(image.width) * base * zoom
    let h = CGFloat(image.height) * base * zoom
    let x = CGFloat(W) / 2 - focus.x * w
    let yy = CGFloat(H) / 2 - (1 - focus.y) * h
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.draw(image, in: CGRect(x: x, y: yy, width: w, height: h))
    ctx.restoreGState()
}

func draw(_ text: String, at point: CGPoint, font f: NSFont, colour: NSColor,
          alpha: CGFloat, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attributed = NSAttributedString(string: text, attributes: [
        .font: f, .foregroundColor: colour.withAlphaComponent(alpha),
        .kern: tracking, .paragraphStyle: style
    ])
    let size = attributed.size()
    attributed.draw(in: CGRect(x: point.x - size.width / 2, y: point.y,
                               width: size.width + 6, height: size.height + 6))
}

// MARK: - The cut

let phone = try Clip(path: phonePath)
let diagram = try Clip(path: diagramPath)

let titleOut: Double = 1.6                       // title card holds until here
let pushEnd = titleOut + max(1.0, receiptAt - phoneIn)   // slow push through the payment
let driveIn = pushEnd + 1.0                      // camera arrives at the receipt
let holdEnd = driveIn + holdAfter
let handover = holdEnd + 0.9                     // crossfade to the walkthrough
let total = handover + diagram.duration - 0.3

func drawFrame(_ ctx: CGContext, time t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Title card
    if t < titleOut + 0.6 {
        let on = min(fade(t, 0.15, 0.5), 1 - fade(t, titleOut - 0.3, 0.45))
        draw("One key, two requests", at: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2 - 10),
             font: serif(62), colour: ink, alpha: on)
        draw("A SINGLE PAYMENT, RECORDED FROM BOTH SIDES",
             at: CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2 - 80),
             font: sans(17, .medium), colour: ink3, alpha: on, tracking: 3.4)
    }

    // The phone, pushed slowly and then driven into the receipt
    if t >= titleOut - 0.3, t < handover + 0.9 {
        let phoneTime = phoneIn + max(0, min(t - titleOut, receiptAt - phoneIn))
            + max(0, t - pushEnd) * 0.0   // the clip pauses once the receipt is up
        let zoom: CGFloat
        let focus: CGPoint
        if t <= pushEnd {
            zoom = lerp(1.02, 1.09, (t - titleOut) / max(0.1, pushEnd - titleOut))
            focus = CGPoint(x: 0.5, y: 0.5)
        } else if t <= driveIn {
            let p = ease((t - pushEnd) / (driveIn - pushEnd))
            zoom = lerp(1.09, 1.78, p)
            focus = CGPoint(x: 0.5, y: lerp(0.5, 0.535, p))
        } else {
            // Then a slow pan down onto the line that says it was charged once.
            let drift = ease(min(1, (t - driveIn) / max(0.1, holdEnd - driveIn)))
            zoom = lerp(1.78, 1.70, drift)
            focus = CGPoint(x: 0.5, y: lerp(0.535, 0.605, drift))
        }
        let appear = min(fade(t, titleOut - 0.3, 0.5), 1 - fade(t, handover, 0.7))
        if let image = phone.frame(at: min(phoneTime, receiptAt + 0.25)) {
            place(image, in: ctx, zoom: zoom, focus: focus, alpha: appear)
        }
    }

    // The walkthrough takes over
    if t >= handover - 0.5 {
        let on = fade(t, handover - 0.5, 0.7)
        let zoom = lerp(1.07, 1.0, (t - handover + 0.5) / 1.1)
        if let image = diagram.frame(at: max(0, t - handover + 0.5)) {
            place(image, in: ctx, zoom: zoom, alpha: on)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Encode

let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 11_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frames = Int(total * Double(fps))
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }

    guard let scratch = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
    else { fatalError("no context") }
    scratch.setShouldAntialias(true)
    scratch.interpolationQuality = .high
    drawFrame(scratch, time: Double(frame) / Double(fps))
    guard let image = scratch.makeImage() else { fatalError("no image") }

    guard let pool = adaptor.pixelBufferPool else { fatalError("no pool") }
    var maybeBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
    guard let buffer = maybeBuffer else { fatalError("no buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H,
                              bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              space: space, bitmapInfo: bitmapInfo) else { fatalError("no ctx") }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.flush()
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    if frame % 90 == 0 { FileHandle.standardError.write("frame \(frame)/\(frames)\n".data(using: .utf8)!) }
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else {
    print("failed: \(writer.error?.localizedDescription ?? "unknown")")
    exit(1)
}
print("wrote \(outPath)  \(String(format: "%.1f", total))s")
