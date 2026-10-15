// Renders the payment walkthrough to an MP4, for posting.
//
//   swift tools/RenderPostVideo.swift out.mp4
//   swift tools/RenderPostVideo.swift --png 5.2 frame.png
//
// 1080x1350 — the tallest frame a feed shows without cropping. Core Graphics draws
// each frame, AVAssetWriter encodes it. Nothing to install.

import AVFoundation
import AppKit

// MARK: - Palette

let bg     = NSColor(srgbRed: 0.043, green: 0.047, blue: 0.055, alpha: 1)
let ink    = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink2   = NSColor(srgbRed: 0.549, green: 0.553, blue: 0.561, alpha: 1)
let ink3   = NSColor(srgbRed: 0.353, green: 0.361, blue: 0.376, alpha: 1)
let rule   = NSColor(srgbRed: 0.125, green: 0.137, blue: 0.157, alpha: 1)
let accent = NSColor(srgbRed: 0.498, green: 0.659, blue: 0.769, alpha: 1)
let rose   = NSColor(srgbRed: 0.788, green: 0.557, blue: 0.608, alpha: 1)

// MARK: - Geometry

let W = 1080, H = 1350
let fps: Int32 = 30
let duration = 14.5

let phoneLine: CGFloat = 480
let gatewayLine: CGFloat = 800
let left: CGFloat = 110
let right: CGFloat = 970

struct Node { let x: CGFloat; let y: CGFloat; let label: String; let tint: NSColor }
let e1 = Node(x: 250, y: phoneLine,   label: "POST #1",                   tint: accent)
let e2 = Node(x: 415, y: gatewayLine, label: "charged · answer dropped",  tint: rose)
let e3 = Node(x: 670, y: phoneLine,   label: "POST #2 · same key",        tint: accent)
let e4 = Node(x: 855, y: gatewayLine, label: "replayed",                  tint: ink)
let e5 = Node(x: 965, y: phoneLine,   label: "receipt",                   tint: ink)

// MARK: - Script

struct Beat { let start: Double; let end: Double; let text: String; let strong: String }

let beats: [Beat] = [
    Beat(start: 0.8, end: 2.7, text: "Face ID confirms. The phone sends the charge\nwith an idempotency key in the header.", strong: "idempotency key"),
    Beat(start: 2.7, end: 3.9, text: "The gateway takes the money\nand files the receipt under that key.", strong: "takes the money"),
    Beat(start: 3.9, end: 5.0, text: "The answer never comes back. A dropped connection,\na restarted proxy — it does not matter which.", strong: ""),
    Beat(start: 5.0, end: 7.2, text: "The money is gone.\nThe phone does not know.", strong: "The phone does not know."),
    Beat(start: 7.2, end: 9.0, text: "So it asks again, with the same key.\nThe intent has not changed, so neither has the key.", strong: "with the same key"),
    Beat(start: 9.0, end: 10.5, text: "The key is known. The gateway returns\nthe receipt it already wrote.", strong: "the receipt it already wrote"),
    Beat(start: 10.5, end: 14.5, text: "Two requests. One charge.", strong: "One charge.")
]

struct Wire { let a: Node; let b: Node; let start: Double; let dur: Double; let lost: Bool }
let lostEnd = Node(x: 575, y: 645, label: "", tint: rose)
let wires: [Wire] = [
    Wire(a: e1, b: e2, start: 1.6, dur: 1.1, lost: false),
    Wire(a: e2, b: lostEnd, start: 3.9, dur: 0.9, lost: true),
    Wire(a: e3, b: e4, start: 7.3, dur: 1.1, lost: false),
    Wire(a: e4, b: e5, start: 9.4, dur: 0.9, lost: false)
]

let litAt: [(Node, Double)] = [(e1, 1.6), (e2, 2.7), (e3, 7.3), (e4, 9.0), (e5, 10.3)]

// MARK: - Drawing

func y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }

func sans(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func serif(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let descriptor = base.fontDescriptor.withDesign(.serif),
       let font = NSFont(descriptor: descriptor, size: size) { return font }
    return base
}

func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func draw(_ text: String, at point: CGPoint, font f: NSFont, colour: NSColor,
          align: NSTextAlignment = .left, alpha: CGFloat = 1, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = align
    let attributed = NSAttributedString(string: text, attributes: [
        .font: f,
        .foregroundColor: colour.withAlphaComponent(alpha),
        .kern: tracking,
        .paragraphStyle: style
    ])
    let size = attributed.size()
    var origin = point
    switch align {
    case .center: origin.x -= size.width / 2
    case .right:  origin.x -= size.width
    default: break
    }
    attributed.draw(in: CGRect(origin: origin, size: CGSize(width: size.width + 6, height: size.height + 6)))
}

func drawCaption(_ text: String, top: CGFloat, alpha: CGFloat, strong: String) {
    guard alpha > 0.01 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineHeightMultiple = 1.3
    let attributed = NSMutableAttributedString(string: text, attributes: [
        .font: serif(34),
        .foregroundColor: ink2.withAlphaComponent(alpha),
        .paragraphStyle: style
    ])
    if !strong.isEmpty, let range = text.range(of: strong) {
        attributed.addAttributes([.foregroundColor: ink.withAlphaComponent(alpha)],
                                 range: NSRange(range, in: text))
    }
    let size = attributed.size()
    attributed.draw(in: CGRect(x: (CGFloat(W) - size.width) / 2, y: y(top) - size.height,
                               width: size.width + 6, height: size.height + 8))
}

func hairline(_ ctx: CGContext, from: CGPoint, to: CGPoint, colour: NSColor, width: CGFloat = 1) {
    ctx.setStrokeColor(colour.cgColor)
    ctx.setLineWidth(width)
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
}

func ease(_ t: Double) -> Double { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func fade(_ t: Double, _ start: Double, _ over: Double) -> CGFloat {
    CGFloat(min(1, max(0, (t - start) / over)))
}

// MARK: - One frame

func drawFrame(_ ctx: CGContext, time t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    ctx.setLineCap(.round)

    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    let titleIn = fade(t, 0, 0.7)
    draw("One key, two requests", at: CGPoint(x: CGFloat(W) / 2, y: y(205)),
         font: serif(60), colour: ink, align: .center, alpha: titleIn)
    draw("A SINGLE PAYMENT, RECORDED FROM BOTH SIDES",
         at: CGPoint(x: CGFloat(W) / 2, y: y(262)),
         font: sans(17, .medium), colour: ink3, align: .center, alpha: titleIn, tracking: 3.4)

    let keyIn = fade(t, 0.35, 0.6)
    hairline(ctx, from: CGPoint(x: left, y: y(322)), to: CGPoint(x: right, y: y(322)),
             colour: rule.withAlphaComponent(keyIn))
    draw("Idempotency-Key   5b2f2c8c-11c9-4f42-b3f4-d5367f08c0eb",
         at: CGPoint(x: CGFloat(W) / 2, y: y(374)),
         font: mono(21), colour: ink3, align: .center, alpha: keyIn)
    hairline(ctx, from: CGPoint(x: left, y: y(402)), to: CGPoint(x: right, y: y(402)),
             colour: rule.withAlphaComponent(keyIn))

    // The lanes are rules, not boxes.
    let lanesIn = fade(t, 0.6, 0.6)
    for (lineY, name) in [(phoneLine, "PHONE"), (gatewayLine, "GATEWAY")] {
        hairline(ctx, from: CGPoint(x: left, y: y(lineY)),
                 to: CGPoint(x: left + (right - left) * lanesIn, y: y(lineY)), colour: rule)
        draw(name, at: CGPoint(x: left, y: y(lineY - 50)), font: sans(15, .medium),
             colour: ink3, alpha: lanesIn, tracking: 3)
    }

    for wire in wires where t >= wire.start {
        let grow = CGFloat(min(1, (t - wire.start) / wire.dur))
        let from = CGPoint(x: wire.a.x, y: y(wire.a.y))
        let full = CGPoint(x: wire.b.x, y: y(wire.b.y))
        ctx.setStrokeColor((wire.lost ? rose : accent).withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(2)
        if wire.lost { ctx.setLineDash(phase: 0, lengths: [7, 9]) }
        ctx.move(to: from)
        ctx.addLine(to: CGPoint(x: from.x + (full.x - from.x) * grow,
                                y: from.y + (full.y - from.y) * grow))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        if t <= wire.start + wire.dur {
            let p = CGFloat(ease(min(1, (t - wire.start) / wire.dur)))
            let pt = CGPoint(x: from.x + (full.x - from.x) * p, y: from.y + (full.y - from.y) * p)
            ctx.setFillColor((wire.lost ? rose : accent).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 8, y: pt.y - 8, width: 16, height: 16))
        }

        if wire.lost, t > wire.start + wire.dur {
            let appear = fade(t, wire.start + wire.dur, 0.3)
            ctx.setStrokeColor(rose.withAlphaComponent(appear).cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: full.x - 11, y: full.y - 11))
            ctx.addLine(to: CGPoint(x: full.x + 11, y: full.y + 11))
            ctx.move(to: CGPoint(x: full.x + 11, y: full.y - 11))
            ctx.addLine(to: CGPoint(x: full.x - 11, y: full.y + 11))
            ctx.strokePath()
            // Centred above the cross: to the right it would sit under the second request.
            draw("the answer never arrived", at: CGPoint(x: full.x, y: full.y + 26),
                 font: sans(21), colour: rose, align: .center, alpha: appear)
        }
    }

    for (node, at) in litAt {
        let appear = fade(t, at - 0.9, 0.5)
        guard appear > 0.01 else { continue }
        let lit = t >= at
        let centre = CGPoint(x: node.x, y: y(node.y))
        let r: CGFloat = 13

        ctx.setFillColor(bg.cgColor)
        ctx.fillEllipse(in: CGRect(x: centre.x - r - 5, y: centre.y - r - 5,
                                   width: (r + 5) * 2, height: (r + 5) * 2))
        if lit {
            ctx.setFillColor(node.tint.withAlphaComponent(appear).cgColor)
            ctx.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        }
        ctx.setStrokeColor(node.tint.withAlphaComponent(appear * (lit ? 1 : 0.45)).cgColor)
        ctx.setLineWidth(2)
        ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))

        // Phone labels above their rule, gateway labels below, so the middle stays clear.
        let above = node.y == phoneLine
        draw(node.label, at: CGPoint(x: node.x, y: y(node.y + (above ? -34 : 64))),
             font: sans(21, lit ? .medium : .regular),
             colour: lit ? ink : ink3, align: .center, alpha: appear)
    }

    if t >= 5.0, t <= 7.2 {
        let shown = fade(t, 5.0, 0.3) * (1 - fade(t, 6.9, 0.3))
        let counted = Int(min(1, max(0, (t - 5.1) / 1.2)) * 843)
        draw("\(counted) ms with no answer", at: CGPoint(x: CGFloat(W) / 2, y: y(935)),
             font: mono(26), colour: rose, align: .center, alpha: shown)
    }

    for beat in beats where t >= beat.start && t < beat.end {
        let on = min(fade(t, beat.start, 0.35), 1 - fade(t, beat.end - 0.35, 0.35))
        drawCaption(beat.text, top: 1065, alpha: on, strong: beat.strong)
    }

    if t >= 11.2 {
        let appear = fade(t, 11.2, 0.7)
        hairline(ctx, from: CGPoint(x: left, y: y(1200)), to: CGPoint(x: right, y: y(1200)),
                 colour: rule.withAlphaComponent(appear))
        let items = [("2", "REQUESTS"), ("1", "CHARGE"), ("843", "MS"), ("1", "KEY")]
        let step = (right - left) / CGFloat(items.count)
        for (index, item) in items.enumerated() {
            let x = left + step * (CGFloat(index) + 0.5)
            draw(item.0, at: CGPoint(x: x, y: y(1272)), font: serif(46), colour: ink,
                 align: .center, alpha: appear)
            draw(item.1, at: CGPoint(x: x, y: y(1302)), font: sans(14, .medium),
                 colour: ink3, align: .center, alpha: appear, tracking: 2.4)
            if index > 0 {
                hairline(ctx, from: CGPoint(x: left + step * CGFloat(index), y: y(1290)),
                         to: CGPoint(x: left + step * CGFloat(index), y: y(1230)),
                         colour: rule.withAlphaComponent(appear))
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Output

let space = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

func render(at t: Double) -> CGImage {
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo)
    else { fatalError("no context") }
    ctx.setShouldAntialias(true)
    drawFrame(ctx, time: t)
    guard let image = ctx.makeImage() else { fatalError("no image") }
    return image
}

if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--png" {
    let image = render(at: Double(CommandLine.arguments[2]) ?? 0)
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
    print("wrote \(CommandLine.arguments[3])")
    exit(0)
}

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "post.mp4"
let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)

let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: W,
    AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 9_000_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
    ]
])
input.expectsMediaDataInRealTime = false

let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frames = Int(duration * Double(fps))
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }

    // Drawn into a context of our own and blitted across. Drawing straight into the
    // pixel buffer's memory loses everything after the first fill: AppKit's text
    // drawing and that backing store disagree about who owns the bits.
    let image = render(at: Double(frame) / Double(fps))

    guard let pool = adaptor.pixelBufferPool else { fatalError("no pixel buffer pool") }
    var maybeBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
    guard let buffer = maybeBuffer else { fatalError("no pixel buffer") }

    CVPixelBufferLockBaseAddress(buffer, [])
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                              width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              space: space, bitmapInfo: bitmapInfo)
    else { fatalError("no buffer context") }
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
print("wrote \(outPath)")
