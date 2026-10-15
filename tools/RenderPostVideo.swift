// Renders the payment walkthrough to an MP4, for posting.
//
//   swift tools/RenderPostVideo.swift out.mp4
//
// 1080x1350 — the tallest frame a feed will show without cropping. Core Graphics
// draws each frame, AVAssetWriter encodes them. No dependencies, nothing to install.

import AVFoundation
import AppKit

// MARK: - Palette

let bg = NSColor(srgbRed: 0.055, green: 0.067, blue: 0.082, alpha: 1)
let lane = NSColor(srgbRed: 0.090, green: 0.106, blue: 0.129, alpha: 1)
let ink = NSColor(srgbRed: 0.914, green: 0.925, blue: 0.937, alpha: 1)
let ink2 = NSColor(srgbRed: 0.608, green: 0.639, blue: 0.675, alpha: 1)
let ink3 = NSColor(srgbRed: 0.447, green: 0.478, blue: 0.514, alpha: 1)
let accent = NSColor(srgbRed: 0.455, green: 0.725, blue: 0.839, alpha: 1)
let flag = NSColor(srgbRed: 0.898, green: 0.514, blue: 0.592, alpha: 1)
let good = NSColor(srgbRed: 0.435, green: 0.757, blue: 0.569, alpha: 1)

// MARK: - Geometry

let W = 1080, H = 1350
let fps: Int32 = 30
let duration = 13.0

let phoneY: CGFloat = 400      // from the top
let serverY: CGFloat = 740
let laneHeight: CGFloat = 130

struct Node { let x: CGFloat; let y: CGFloat; let label: String; let colour: NSColor }
let e1 = Node(x: 200, y: phoneY, label: "POST №1", colour: accent)
let e2 = Node(x: 410, y: serverY, label: "списал · ответ выброшен", colour: flag)
let e3 = Node(x: 650, y: phoneY, label: "POST №2 · тот же ключ", colour: accent)
let e4 = Node(x: 850, y: serverY, label: "отдал запись", colour: good)
let e5 = Node(x: 975, y: phoneY, label: "чек", colour: good)

// MARK: - Script

struct Beat {
    let start: Double
    let end: Double
    let caption: String
    let strong: String
}

let beats: [Beat] = [
    Beat(start: 0.6, end: 2.4, caption: "Face ID подтверждён. Телефон шлёт запрос\nи кладёт ключ идемпотентности в заголовок.", strong: ""),
    Beat(start: 2.4, end: 3.4, caption: "Сервер списал деньги\nи записал чек под ключом.", strong: "списал"),
    Beat(start: 3.4, end: 4.4, caption: "А ответ не дошёл.\nОборванный Wi-Fi, упавший балансировщик — неважно.", strong: ""),
    Beat(start: 4.4, end: 6.4, caption: "Деньги ушли.\nТелефон об этом не знает.", strong: "Телефон об этом не знает."),
    Beat(start: 6.4, end: 7.8, caption: "Телефон повторяет — тем же ключом.\nНамерение не изменилось, значит и ключ не меняется.", strong: "тем же ключом"),
    Beat(start: 7.8, end: 9.2, caption: "Ключ знаком. Сервер отдаёт ту же запись,\nа не списывает заново.", strong: "ту же запись"),
    Beat(start: 9.2, end: 13.0, caption: "Два запроса. Одно списание.", strong: "Одно списание.")
]

// Which wire is moving when: (from, to, start, duration, lost)
struct Wire { let a: Node; let b: Node; let start: Double; let dur: Double; let lost: Bool }
let wires: [Wire] = [
    Wire(a: e1, b: e2, start: 1.4, dur: 1.0, lost: false),
    Wire(a: e2, b: Node(x: 560, y: 580, label: "", colour: flag), start: 3.4, dur: 0.8, lost: true),
    Wire(a: e3, b: e4, start: 6.4, dur: 1.0, lost: false),
    Wire(a: e4, b: e5, start: 8.2, dur: 0.9, lost: false)
]

// When each node lights up for good.
let litAt: [(Node, Double)] = [(e1, 1.4), (e2, 2.4), (e3, 6.4), (e4, 7.8), (e5, 9.1)]

// MARK: - Drawing helpers

func y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
    NSFont.monospacedSystemFont(ofSize: size, weight: weight)
}

func draw(_ text: String, at point: CGPoint, font f: NSFont, colour: NSColor,
          align: NSTextAlignment = .left, alpha: CGFloat = 1, lineHeight: CGFloat = 1.3) {
    let style = NSMutableParagraphStyle()
    style.alignment = align
    style.lineHeightMultiple = lineHeight
    let attributed = NSAttributedString(string: text, attributes: [
        .font: f,
        .foregroundColor: colour.withAlphaComponent(colour.alphaComponent * alpha),
        .paragraphStyle: style
    ])
    let size = attributed.size()
    var origin = point
    switch align {
    case .center: origin.x -= size.width / 2
    case .right:  origin.x -= size.width
    default: break
    }
    attributed.draw(in: CGRect(origin: origin, size: CGSize(width: size.width + 4, height: size.height + 6)))
}

func drawMultiline(_ text: String, centeredAt x: CGFloat, top: CGFloat, font f: NSFont,
                   colour: NSColor, alpha: CGFloat, strong: String) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineHeightMultiple = 1.25
    let attributed = NSMutableAttributedString(string: text, attributes: [
        .font: f,
        .foregroundColor: ink2.withAlphaComponent(alpha),
        .paragraphStyle: style
    ])
    if !strong.isEmpty, let range = text.range(of: strong) {
        attributed.addAttributes([
            .font: NSFont.systemFont(ofSize: f.pointSize, weight: .semibold),
            .foregroundColor: ink.withAlphaComponent(alpha)
        ], range: NSRange(range, in: text))
    }
    let size = attributed.size()
    attributed.draw(in: CGRect(x: x - size.width / 2, y: y(top) - size.height,
                               width: size.width + 4, height: size.height + 8))
}

func roundedRect(_ ctx: CGContext, _ rect: CGRect, radius: CGFloat, fill: NSColor) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill.cgColor)
    ctx.fillPath()
}

func ease(_ t: Double) -> Double {
    t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

// MARK: - One frame

func drawFrame(_ ctx: CGContext, time t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns

    ctx.setFillColor(bg.cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

    // Title
    let titleIn = min(1, max(0, t / 0.6))
    draw("Один ключ, два запроса", at: CGPoint(x: CGFloat(W) / 2, y: y(170)),
         font: font(54, .bold), colour: ink, align: .center, alpha: titleIn)
    draw("один платёж, записанный с двух сторон", at: CGPoint(x: CGFloat(W) / 2, y: y(232)),
         font: font(26), colour: ink3, align: .center, alpha: titleIn)

    // The key
    let keyIn = min(1, max(0, (t - 0.3) / 0.5))
    roundedRect(ctx, CGRect(x: 120, y: y(320), width: 840, height: 54), radius: 12,
                fill: accent.withAlphaComponent(0.14 * keyIn))
    draw("Idempotency-Key  5b2f2c8c-11c9-4f42-b3f4-d5367f08c0eb",
         at: CGPoint(x: CGFloat(W) / 2, y: y(305)),
         font: mono(22), colour: accent, align: .center, alpha: keyIn)

    // Lanes
    let lanesIn = min(1, max(0, (t - 0.5) / 0.5))
    roundedRect(ctx, CGRect(x: 120, y: y(phoneY + laneHeight / 2), width: 890, height: laneHeight),
                radius: 18, fill: lane.withAlphaComponent(lanesIn))
    roundedRect(ctx, CGRect(x: 120, y: y(serverY + laneHeight / 2), width: 890, height: laneHeight),
                radius: 18, fill: lane.withAlphaComponent(lanesIn))
    draw("ТЕЛЕФОН", at: CGPoint(x: 150, y: y(phoneY - 36)), font: font(19, .medium),
         colour: ink3, alpha: lanesIn)
    draw("СЕРВЕР", at: CGPoint(x: 150, y: y(serverY - 36)), font: font(19, .medium),
         colour: ink3, alpha: lanesIn)

    // Wires, drawn once their beat has started
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    for wire in wires {
        guard t >= wire.start else { continue }
        let grow = min(1, (t - wire.start) / wire.dur)
        let from = CGPoint(x: wire.a.x, y: y(wire.a.y))
        let full = CGPoint(x: wire.b.x, y: y(wire.b.y))
        let to = CGPoint(x: from.x + (full.x - from.x) * grow,
                         y: from.y + (full.y - from.y) * grow)
        ctx.setStrokeColor((wire.lost ? flag : accent).withAlphaComponent(wire.lost ? 0.9 : 0.55).cgColor)
        if wire.lost { ctx.setLineDash(phase: 0, lengths: [10, 10]) } else { ctx.setLineDash(phase: 0, lengths: []) }
        ctx.move(to: from)
        ctx.addLine(to: to)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])

        // The packet itself
        if t >= wire.start, t <= wire.start + wire.dur {
            let p = ease(min(1, (t - wire.start) / wire.dur))
            let pt = CGPoint(x: from.x + (full.x - from.x) * p, y: from.y + (full.y - from.y) * p)
            ctx.setFillColor((wire.lost ? flag : accent).cgColor)
            ctx.fillEllipse(in: CGRect(x: pt.x - 11, y: pt.y - 11, width: 22, height: 22))
        }
        // The cross where the lost answer stops
        if wire.lost, t > wire.start + wire.dur {
            let c = full
            ctx.setStrokeColor(flag.cgColor)
            ctx.setLineWidth(4)
            ctx.move(to: CGPoint(x: c.x - 13, y: c.y - 13)); ctx.addLine(to: CGPoint(x: c.x + 13, y: c.y + 13))
            ctx.move(to: CGPoint(x: c.x + 13, y: c.y - 13)); ctx.addLine(to: CGPoint(x: c.x - 13, y: c.y + 13))
            ctx.strokePath()
            ctx.setLineWidth(3)
            draw("ответ не дошёл", at: CGPoint(x: c.x + 34, y: c.y - 14),
                 font: font(22), colour: flag)
        }
    }

    // Nodes
    for (node, at) in litAt {
        let appear = min(1, max(0, (t - at + 0.9) / 0.5))
        guard appear > 0 else { continue }
        let isLit = t >= at
        let centre = CGPoint(x: node.x, y: y(node.y))
        let r: CGFloat = 20
        ctx.setFillColor((isLit ? node.colour : bg).withAlphaComponent(appear).cgColor)
        ctx.fillEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
        ctx.setStrokeColor(node.colour.withAlphaComponent(appear).cgColor)
        ctx.setLineWidth(5)
        ctx.strokeEllipse(in: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))

        draw(node.label, at: CGPoint(x: node.x, y: y(node.y + 58)),
             font: font(23, isLit ? .medium : .regular),
             colour: isLit ? ink : ink3, align: .center, alpha: appear)
    }

    // The gap, counted out
    if t >= 4.4, t <= 6.4 {
        let done = min(1, (t - 4.6) / 1.1)
        let ms = Int(done * 843)
        draw("\(ms) мс без ответа", at: CGPoint(x: CGFloat(W) / 2, y: y(920)),
             font: mono(30, .medium), colour: flag, align: .center)
    }

    // Caption
    for beat in beats where t >= beat.start && t < beat.end {
        let fade = min(1, min((t - beat.start) / 0.3, (beat.end - t) / 0.3))
        drawMultiline(beat.caption, centeredAt: CGFloat(W) / 2, top: 1020,
                      font: font(31), colour: ink2, alpha: max(0, fade), strong: beat.strong)
    }

    // The tally, at the end
    if t >= 9.4 {
        let appear = min(1, (t - 9.4) / 0.6)
        let tiles: [(String, String)] = [("2", "запроса"), ("1", "списание"), ("843", "мс"), ("1", "ключ")]
        let width: CGFloat = 200, gap: CGFloat = 18
        let total = CGFloat(tiles.count) * width + CGFloat(tiles.count - 1) * gap
        var x = (CGFloat(W) - total) / 2
        for (number, label) in tiles {
            roundedRect(ctx, CGRect(x: x, y: y(1240), width: width, height: 130), radius: 16,
                        fill: lane.withAlphaComponent(appear))
            draw(number, at: CGPoint(x: x + width / 2, y: y(1180)), font: font(52, .bold),
                 colour: ink, align: .center, alpha: appear)
            draw(label, at: CGPoint(x: x + width / 2, y: y(1228)), font: font(22),
                 colour: ink3, align: .center, alpha: appear)
            x += width + gap
        }
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Encode

// `--png <seconds> <path>` renders one frame instead, for checking the drawing.
if CommandLine.arguments.count > 3, CommandLine.arguments[1] == "--png" {
    let t = Double(CommandLine.arguments[2]) ?? 0
    let path = CommandLine.arguments[3]
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
    else { fatalError("no context") }
    drawFrame(ctx, time: t)
    guard let image = ctx.makeImage() else { fatalError("no image") }
    let rep = NSBitmapImageRep(cgImage: image)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
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
let space = CGColorSpaceCreateDeviceRGB()

for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }

    guard let pool = adaptor.pixelBufferPool else { fatalError("no pixel buffer pool") }
    var maybeBuffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &maybeBuffer)
    guard let buffer = maybeBuffer else { fatalError("no pixel buffer") }

    // Drawn into a context of our own and blitted across. Drawing straight into the
    // pixel buffer's memory loses everything after the first fill — AppKit's text
    // drawing and the buffer's backing store do not agree about who owns the bits.
    guard let scratch = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                            | CGBitmapInfo.byteOrder32Little.rawValue)
    else { fatalError("no scratch context") }
    scratch.setShouldAntialias(true)
    drawFrame(scratch, time: Double(frame) / Double(fps))
    guard let image = scratch.makeImage() else { fatalError("no image") }

    CVPixelBufferLockBaseAddress(buffer, [])
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                              width: W, height: H, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue)
    else { fatalError("no context") }
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H))
    ctx.flush()
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))

    if frame % 60 == 0 { FileHandle.standardError.write("frame \(frame)/\(frames)\n".data(using: .utf8)!) }
}

input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()

if writer.status == .completed {
    print("wrote \(outPath)")
} else {
    print("failed: \(writer.error?.localizedDescription ?? "unknown")")
    exit(1)
}
