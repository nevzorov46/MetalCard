// The payment as a sequence diagram whose left lifeline is the phone itself.
//
//   swift tools/RenderSequence.swift out.mp4 -phone sim.mp4 -in 12.4 -charge 15.6 -receipt 17.8
//
// The recording opens centred, then slides aside as the gateway's lifeline appears.
// Each message is drawn across the gap the moment it happens: the request leaves the
// phone's edge, the lost answer dies halfway back, the retry crosses with the same
// key, and the replay lands on the phone as the receipt appears on it.

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
                ? CommandLine.arguments[1] : "sequence.mp4"
let phonePath = text("-phone", "")
let clipIn    = number("-in", 0)
let chargeAt  = number("-charge", 0)
let receiptAt = number("-receipt", 0)
let tail      = number("-tail", 3.4)
let gap       = 0.843

guard !phonePath.isEmpty else { print("need -phone <file>"); exit(1) }

// MARK: - Canvas and palette

let W = 1080, H = 1350
let fps: Int32 = 30

let bg     = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.055, alpha: 1)
let ink    = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink2   = NSColor(srgbRed: 0.549, green: 0.553, blue: 0.561, alpha: 1)
let ink3   = NSColor(srgbRed: 0.353, green: 0.361, blue: 0.376, alpha: 1)
let rule   = NSColor(srgbRed: 0.125, green: 0.137, blue: 0.157, alpha: 1)
let accent = NSColor(srgbRed: 0.498, green: 0.659, blue: 0.769, alpha: 1)
let rose   = NSColor(srgbRed: 0.788, green: 0.557, blue: 0.608, alpha: 1)

func y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }
func sans(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.monospacedSystemFont(ofSize: s, weight: w) }
func serif(_ s: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: s, weight: .regular)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: s) { return f }
    return base
}
func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
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

    init(path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let found = try awaitValue { try await asset.loadTracks(withMediaType: .video).first }
        guard let track = found else { throw NSError(domain: "clip", code: 1) }
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

// MARK: - Choreography

let charge  = chargeAt - clipIn
let retry   = charge + gap
let receipt = max(receiptAt - clipIn, retry + 0.25)
let total   = receipt + tail

// The phone opens centred and large, then steps aside for the gateway.
let slideStart = max(0.6, charge - 2.2)
let slideEnd   = slideStart + 0.9

// Where the lanes sit once the phone has moved.
let phoneLeft: CGFloat = 52, phoneWidthAside: CGFloat = 430, phoneTopAside: CGFloat = 230
let phoneWidthCentred: CGFloat = 560, phoneTopCentred: CGFloat = 150
let gatewayX: CGFloat = 930
let lifelineTop: CGFloat = 300, lifelineBottom: CGFloat = 1090

struct Message {
    let row: CGFloat          // y from the top
    let start: Double         // when it leaves
    let dur: Double
    let toGateway: Bool
    let lost: Bool
    let label: String
    let sub: String
    let tint: NSColor
}

let messages: [Message] = [
    Message(row: 500, start: charge - 0.55, dur: 0.5, toGateway: true,  lost: false,
            label: "POST /v1/charges", sub: "Idempotency-Key  5b2f2c8c…", tint: accent),
    Message(row: 600, start: charge + 0.15, dur: 0.45, toGateway: false, lost: true,
            label: "response dropped", sub: "the money moved — the phone does not know", tint: rose),
    Message(row: 800, start: retry - 0.5, dur: 0.5, toGateway: true,  lost: false,
            label: "POST /v1/charges", sub: "same key", tint: accent),
    Message(row: 900, start: retry + 0.05, dur: 0.45, toGateway: false, lost: false,
            label: "200  replayed", sub: "Idempotent-Replayed: true", tint: ink)
]

// MARK: - One frame

func drawFrame(_ ctx: CGContext, time t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    ctx.setLineCap(.round)
    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let openIn = fade(t, 0, 0.6)
    let slide = CGFloat(ease(min(1, max(0, (t - slideStart) / (slideEnd - slideStart)))))

    // Masthead
    draw("One key, two requests", at: CGPoint(x: 52, y: y(96)), font: serif(40), colour: ink, alpha: openIn)
    draw("A SINGLE PAYMENT, WATCHED FROM BOTH SIDES", at: CGPoint(x: 52, y: y(134)),
         font: sans(15, .medium), colour: ink3, alpha: openIn, tracking: 3)

    // The phone: centred, then aside. Its right edge is the left lifeline.
    let width = lerp(phoneWidthCentred, phoneWidthAside, Double(slide))
    let top = lerp(phoneTopCentred, phoneTopAside, Double(slide))
    let centreX = lerp(CGFloat(W) / 2, phoneLeft + phoneWidthAside / 2, Double(slide))
    var phoneRight = centreX + width / 2
    if let image = phone.frame(at: clipIn + min(t, receipt + 0.3)) {
        let push = lerp(1.0, 1.03, t / max(1, total))
        let w = width * push
        let h = w * CGFloat(image.height) / CGFloat(image.width)
        let heightAtRest = width * CGFloat(image.height) / CGFloat(image.width)
        let cy = y(top) - heightAtRest / 2
        ctx.saveGState()
        ctx.setAlpha(openIn)
        ctx.draw(image, in: CGRect(x: centreX - w / 2, y: cy - h / 2, width: w, height: h))
        ctx.restoreGState()
        phoneRight = centreX + w / 2
    }

    // The gateway's lifeline grows down as the phone steps aside.
    let lineIn = CGFloat(ease(Double(slide)))
    draw("PHONE", at: CGPoint(x: phoneLeft, y: y(phoneTopAside - 36)), font: sans(20, .medium),
         colour: ink2, alpha: slide, tracking: 4)
    draw("GATEWAY", at: CGPoint(x: gatewayX, y: y(lifelineTop - 44)), font: sans(20, .medium),
         colour: ink2, align: .center, alpha: slide, tracking: 4)
    ctx.setStrokeColor(rule.withAlphaComponent(slide).cgColor)
    ctx.setLineWidth(1.5)
    ctx.move(to: CGPoint(x: gatewayX, y: y(lifelineTop)))
    ctx.addLine(to: CGPoint(x: gatewayX, y: y(lifelineTop + (lifelineBottom - lifelineTop) * lineIn)))
    ctx.strokePath()

    // The gateway is busy from the charge until it answers the retry.
    if t >= charge - 0.05 {
        let busyTop: CGFloat = 486
        let busyBottom = min(lerp(486, 930, (t - charge + 0.05) / (retry + 0.5 - charge)), 930)
        let on = fade(t, charge - 0.05, 0.25)
        ctx.setFillColor(ink.withAlphaComponent(0.10 * on).cgColor)
        ctx.fill(CGRect(x: gatewayX - 7, y: y(busyBottom), width: 14, height: busyBottom - busyTop))
        ctx.setStrokeColor(ink.withAlphaComponent(0.35 * on).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(CGRect(x: gatewayX - 7, y: y(busyBottom), width: 14, height: busyBottom - busyTop))
    }

    // Messages across the gap
    for m in messages where t >= m.start {
        let p = CGFloat(ease(min(1, (t - m.start) / m.dur)))
        let from = m.toGateway ? phoneRight + 14 : gatewayX - 10
        let fullTo = m.toGateway ? gatewayX - 10 : phoneRight + 14
        let reach = m.lost ? 0.52 : 1.0   // the lost answer dies about halfway back
        let to = from + (fullTo - from) * p * CGFloat(reach)
        let rowY = y(m.row)

        ctx.setStrokeColor(m.tint.withAlphaComponent(m.lost ? 0.85 : 0.55).cgColor)
        ctx.setLineWidth(2)
        if m.lost { ctx.setLineDash(phase: 0, lengths: [7, 9]) }
        ctx.move(to: CGPoint(x: from, y: rowY))
        ctx.addLine(to: CGPoint(x: to, y: rowY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // The packet, while it travels
        if p < 1 {
            ctx.setFillColor(m.tint.cgColor)
            ctx.fillEllipse(in: CGRect(x: to - 8, y: rowY - 8, width: 16, height: 16))
        } else if m.lost {
            // Dies with a cross
            let c = CGPoint(x: to, y: rowY)
            ctx.setStrokeColor(rose.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: c.x - 10, y: c.y - 10)); ctx.addLine(to: CGPoint(x: c.x + 10, y: c.y + 10))
            ctx.move(to: CGPoint(x: c.x + 10, y: c.y - 10)); ctx.addLine(to: CGPoint(x: c.x - 10, y: c.y + 10))
            ctx.strokePath()
        } else {
            // Arrives with an arrowhead
            let dir: CGFloat = m.toGateway ? 1 : -1
            ctx.setStrokeColor(m.tint.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: to - 12 * dir, y: rowY + 8))
            ctx.addLine(to: CGPoint(x: to, y: rowY))
            ctx.addLine(to: CGPoint(x: to - 12 * dir, y: rowY - 8))
            ctx.strokePath()
        }

        // Labels ride above the line, anchored to the phone's side of the gap
        let labelOn = fade(t, m.start + 0.05, 0.3)
        let lx = phoneRight + 22
        draw(m.label, at: CGPoint(x: lx, y: rowY + 14), font: mono(20, .medium),
             colour: m.tint, alpha: labelOn)
        draw(m.sub, at: CGPoint(x: lx, y: rowY - 36), font: sans(16), colour: ink3, alpha: labelOn)
    }

    // The silence, counted out in the empty row between the two requests
    if t >= charge + 0.6, t < retry + 0.35 {
        let shown = min(fade(t, charge + 0.6, 0.25), 1 - fade(t, retry, 0.35))
        let counted = Int(min(1, max(0, (t - charge - 0.2) / gap)) * 843)
        draw("\(counted) ms with no answer", at: CGPoint(x: (phoneRight + gatewayX) / 2, y: y(712)),
             font: mono(26, .medium), colour: rose, align: .center, alpha: shown)
    }

    // The receipt's own line, once it is on the phone
    if t >= receipt {
        let on = fade(t, receipt, 0.4)
        draw("charges = 1", at: CGPoint(x: phoneRight + 22, y: y(1020)),
             font: mono(24, .medium), colour: ink, alpha: on)
        draw("the receipt and the gateway's record carry the same id",
             at: CGPoint(x: phoneRight + 22, y: y(1052)), font: sans(16), colour: ink3, alpha: on)
    }

    // Tally
    let tallyIn = fade(t, slideEnd, 0.6)
    ctx.setStrokeColor(rule.withAlphaComponent(tallyIn).cgColor)
    ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: 52, y: y(1192))); ctx.addLine(to: CGPoint(x: 1028, y: y(1192)))
    ctx.strokePath()
    let requests = t >= retry - 0.5 ? 2 : (t >= charge - 0.55 ? 1 : 0)
    let charged = t >= charge ? 1 : 0
    let elapsed = Int(min(1, max(0, (t - charge - 0.2) / gap)) * 843)
    let items = [("\(requests)", "REQUESTS"), ("\(charged)", "CHARGE"), ("\(elapsed)", "MS"), ("1", "KEY")]
    let step = (1028 - 52) / CGFloat(items.count)
    for (i, item) in items.enumerated() {
        let x = 52 + step * (CGFloat(i) + 0.5)
        draw(item.0, at: CGPoint(x: x, y: y(1262)), font: serif(48), colour: ink, align: .center, alpha: tallyIn)
        draw(item.1, at: CGPoint(x: x, y: y(1294)), font: sans(15, .medium), colour: ink3,
             align: .center, alpha: tallyIn, tracking: 2.4)
        if i > 0 {
            ctx.setStrokeColor(rule.withAlphaComponent(tallyIn).cgColor)
            ctx.move(to: CGPoint(x: 52 + step * CGFloat(i), y: y(1282)))
            ctx.addLine(to: CGPoint(x: 52 + step * CGFloat(i), y: y(1222)))
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
