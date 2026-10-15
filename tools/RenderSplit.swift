// The payment and the gateway's answers in one frame, at once.
//
//   swift tools/RenderSplit.swift out.mp4 -phone sim.mp4 -in 12.4 -charge 15.6 -receipt 17.8
//
// Left: the recording, playing. Right: what the gateway says while it happens.
// One canvas, fixed at 1080x1350 from the first line — nothing is fitted afterwards.

import AVFoundation
import AppKit

// MARK: - Arguments

func number(_ name: String, _ fallback: Double) -> Double {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count,
          let v = Double(CommandLine.arguments[i + 1]) else { return fallback }
    return v
}
func text(_ name: String, _ fallback: String) -> String {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count
    else { return fallback }
    return CommandLine.arguments[i + 1]
}

let outPath   = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-")
                ? CommandLine.arguments[1] : "split.mp4"
let phonePath = text("-phone", "")
let clipIn    = number("-in", 0)        // where the clip starts being interesting
let chargeAt  = number("-charge", 0)    // when the gateway takes the money, in the clip
let receiptAt = number("-receipt", 0)   // when the receipt lands, in the clip
let tail      = number("-tail", 3.2)    // how long to hold on the finished frame
let gap       = 0.843                   // the real pause between the two requests

guard !phonePath.isEmpty else { print("need -phone <file>"); exit(1) }

// MARK: - Canvas

let W = 1080, H = 1350
let fps: Int32 = 30

let bg     = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.055, alpha: 1)
let ink    = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink2   = NSColor(srgbRed: 0.549, green: 0.553, blue: 0.561, alpha: 1)
let ink3   = NSColor(srgbRed: 0.353, green: 0.361, blue: 0.376, alpha: 1)
let rule   = NSColor(srgbRed: 0.125, green: 0.137, blue: 0.157, alpha: 1)
let accent = NSColor(srgbRed: 0.498, green: 0.659, blue: 0.769, alpha: 1)
let rose   = NSColor(srgbRed: 0.788, green: 0.557, blue: 0.608, alpha: 1)

// The two columns, decided once, here.
let phoneX: CGFloat = 56, phoneW: CGFloat = 440, phoneTop: CGFloat = 196
let panelX: CGFloat = 556, panelRight: CGFloat = 1024
let panelTop: CGFloat = 214, lineStep: CGFloat = 96
let tallyRule: CGFloat = 1192

func y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }
func sans(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.monospacedSystemFont(ofSize: s, weight: w) }
func serif(_ s: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: s, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: s) { return f }
    return base
}
func fade(_ t: Double, _ from: Double, _ over: Double) -> CGFloat {
    CGFloat(min(1, max(0, (t - from) / over)))
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(max(0, min(1, t))) }

func draw(_ string: String, at p: CGPoint, font f: NSFont, colour: NSColor,
          align: NSTextAlignment = .left, alpha: CGFloat = 1, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = align
    let a = NSAttributedString(string: string, attributes: [
        .font: f, .foregroundColor: colour.withAlphaComponent(alpha),
        .kern: tracking, .paragraphStyle: style
    ])
    let size = a.size()
    var origin = p
    if align == .center { origin.x -= size.width / 2 }
    if align == .right { origin.x -= size.width }
    a.draw(in: CGRect(origin: origin, size: CGSize(width: size.width + 6, height: size.height + 6)))
}

// MARK: - Reading the recording

final class Clip {
    private let output: AVAssetReaderTrackOutput
    private var current: (image: CGImage, time: Double)?
    private var next: (image: CGImage, time: Double)?
    let size: CGSize

    init(path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let found = try awaitValue { try await asset.loadTracks(withMediaType: .video).first }
        guard let track = found else { throw NSError(domain: "clip", code: 1) }
        size = try awaitValue { try await track.load(.naturalSize) } ?? .zero
        let reader = try AVAssetReader(asset: asset)
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
                            width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                            bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = ctx?.makeImage() else { return nil }
        return (image, time)
    }

    func frame(at time: Double) -> CGImage? {
        while let candidate = next, candidate.time <= time {
            current = candidate
            next = pull()
        }
        return current?.image ?? next?.image
    }
}

/// Bridges AVFoundation's async-only loaders into this straight-line script.
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

let phone = try Clip(path: phonePath)

// MARK: - What the gateway says, and when

/// Output time is the clip's time minus `clipIn`, so a status lines up with the
/// frame that caused it.
let charge = chargeAt - clipIn
let retry = charge + gap
let receipt = max(receiptAt - clipIn, retry + 0.2)
let total = receipt + tail

struct Status {
    let at: Double
    let stamp: String
    let head: String
    let sub: String
    let tint: NSColor
}

let statuses: [Status] = [
    Status(at: charge - 0.25, stamp: "26.821", head: "POST /v1/charges",
           sub: "Idempotency-Key  5b2f2c8c…", tint: accent),
    Status(at: charge, stamp: "26.821", head: "charged",
           sub: "ch_75cf83d618dc", tint: ink),
    Status(at: charge + 0.18, stamp: "26.821", head: "response dropped",
           sub: "the money moved, the phone does not know", tint: rose),
    Status(at: retry, stamp: "27.665", head: "POST /v1/charges",
           sub: "same key", tint: accent),
    Status(at: retry + 0.22, stamp: "27.665", head: "200  replayed",
           sub: "Idempotent-Replayed: true", tint: ink),
    Status(at: receipt, stamp: "", head: "charges = 1",
           sub: "two requests, one charge", tint: ink)
]

// MARK: - One frame

func drawFrame(_ ctx: CGContext, time t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let openIn = fade(t, 0, 0.6)

    // Masthead
    draw("One key, two requests", at: CGPoint(x: phoneX, y: y(104)),
         font: serif(40), colour: ink, alpha: openIn)
    draw("A SINGLE PAYMENT, WATCHED FROM BOTH SIDES", at: CGPoint(x: phoneX, y: y(142)),
         font: sans(15, .medium), colour: ink3, alpha: openIn, tracking: 3)

    // The recording, with the slowest of pushes so the frame stays alive
    let clipTime = clipIn + min(t, receipt + 0.2)
    if let image = phone.frame(at: clipTime) {
        let zoom = lerp(1.0, 1.045, t / max(1, total))
        let w = phoneW * zoom
        let h = w * CGFloat(image.height) / CGFloat(image.width)
        let cx = phoneX + phoneW / 2
        let cy = y(phoneTop) - (phoneW * CGFloat(image.height) / CGFloat(image.width)) / 2
        ctx.saveGState()
        ctx.setAlpha(openIn)
        ctx.draw(image, in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
        ctx.restoreGState()
    }

    // A rule between the columns
    ctx.setStrokeColor(rule.withAlphaComponent(openIn).cgColor)
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: panelX - 32, y: y(196)))
    ctx.addLine(to: CGPoint(x: panelX - 32, y: y(1120)))
    ctx.strokePath()

    draw("GATEWAY", at: CGPoint(x: panelX, y: y(172)), font: sans(20, .medium),
         colour: ink2, alpha: openIn, tracking: 4)

    // The statuses, each arriving as its moment does
    for (index, status) in statuses.enumerated() {
        let on = fade(t, status.at, 0.3)
        guard on > 0.01 else { continue }
        let slide = lerp(14, 0, (t - status.at) / 0.35)
        let top = panelTop + CGFloat(index) * lineStep + slide

        if !status.stamp.isEmpty {
            draw(status.stamp, at: CGPoint(x: panelX, y: y(top + 22)),
                 font: mono(17), colour: ink3, alpha: on * 0.9)
        }
        draw(status.head, at: CGPoint(x: panelX + 108, y: y(top + 24)),
             font: mono(21, .medium), colour: status.tint, alpha: on)
        draw(status.sub, at: CGPoint(x: panelX + 108, y: y(top + 52)),
             font: sans(17), colour: ink3, alpha: on * 0.95)
    }

    // The pause, counted while it lasts
    if t >= charge + 0.45, t < retry + 0.3 {
        let shown = min(fade(t, charge + 0.45, 0.25), 1 - fade(t, retry, 0.3))
        let counted = Int(min(1, max(0, (t - charge - 0.2) / gap)) * 843)
        draw("\(counted) ms with no answer", at: CGPoint(x: panelX + 108, y: y(panelTop + 3 * lineStep - 20)),
             font: mono(24, .medium), colour: rose, alpha: shown)
    }

    // The tally, moving as the payment does
    let tallyIn = fade(t, 0.5, 0.7)
    ctx.setStrokeColor(rule.withAlphaComponent(tallyIn).cgColor)
    ctx.move(to: CGPoint(x: phoneX, y: y(tallyRule)))
    ctx.addLine(to: CGPoint(x: panelRight, y: y(tallyRule)))
    ctx.strokePath()

    let requests = t >= retry ? 2 : (t >= charge - 0.25 ? 1 : 0)
    let charged = t >= charge ? 1 : 0
    let elapsed = Int(min(1, max(0, (t - charge - 0.2) / gap)) * 843)
    let items = [("\(requests)", "REQUESTS"), ("\(charged)", "CHARGE"),
                 ("\(elapsed)", "MS"), ("1", "KEY")]
    let step = (panelRight - phoneX) / CGFloat(items.count)
    for (index, item) in items.enumerated() {
        let x = phoneX + step * (CGFloat(index) + 0.5)
        draw(item.0, at: CGPoint(x: x, y: y(1262)), font: serif(48), colour: ink,
             align: .center, alpha: tallyIn)
        draw(item.1, at: CGPoint(x: x, y: y(1294)), font: sans(15, .medium), colour: ink3,
             align: .center, alpha: tallyIn, tracking: 2.4)
        if index > 0 {
            ctx.setStrokeColor(rule.withAlphaComponent(tallyIn).cgColor)
            ctx.move(to: CGPoint(x: phoneX + step * CGFloat(index), y: y(1282)))
            ctx.addLine(to: CGPoint(x: phoneX + step * CGFloat(index), y: y(1222)))
            ctx.strokePath()
        }
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Encode

let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

func render(at t: Double) -> CGImage {
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
    else { fatalError("no context") }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    drawFrame(ctx, time: t)
    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--png" {
    let image = render(at: Double(CommandLine.arguments[2]) ?? 0)
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    print("wrote \(CommandLine.arguments[3])")
    exit(0)
}

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
    let image = render(at: Double(frame) / Double(fps))
    guard let pool = adaptor.pixelBufferPool else { fatalError("no pool") }
    var maybe: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybe)
    guard let buffer = maybe else { fatalError("no buffer") }
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
