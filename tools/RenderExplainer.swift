// A screen recording, stopped at each step to show what happened behind it.
//
//   swift tools/RenderExplainer.swift out.mp4 -phone recording.mp4
//   swift tools/RenderExplainer.swift frame.png -phone recording.mp4 --png 12.0
//
// The camera plays the recording, drives into the button being pressed, and the frame
// gives way to an animated scene — the phone, the gateway, the key between them, the
// ledger — then pulls back out and the recording carries on. The cut list below is in
// the recording's own seconds; a new recording needs new numbers and nothing else.

import AVFoundation
import AppKit

// MARK: - Arguments

func value(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}
let outPath = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-") ? CommandLine.arguments[1] : "explainer.mp4"
guard let phonePath = value("-phone") else { print("need -phone <recording>"); exit(1) }

// MARK: - The cut

enum Scene { case request, charge, lost, retry }

enum Shot {
    /// Play the recording from one second to another, at a speed.
    case play(from: Double, to: Double, speed: Double)
    /// Freeze at a second, drive into a point (0…1 of the recording), play a scene, come back.
    case beat(at: Double, focus: CGPoint, scene: Scene, hold: Double)
    /// The last frame, with the line that sums it up.
    case end(at: Double, hold: Double)
}

// The subscription, recorded in the simulator. Face ID and the spinner (5.2–8.6 s) are
// cut: the first scene says what happens there.
let cut: [Shot] = [
    .play(from: 0.3, to: 4.6, speed: 1.0),
    .beat(at: 4.6, focus: CGPoint(x: 0.5, y: 0.477), scene: .request, hold: 3.8),
    .play(from: 9.0, to: 9.6, speed: 1.0),
    .beat(at: 9.6, focus: CGPoint(x: 0.5, y: 0.45), scene: .charge, hold: 3.6),
    .play(from: 9.6, to: 18.6, speed: 2.2),
    .beat(at: 18.6, focus: CGPoint(x: 0.5, y: 0.54), scene: .lost, hold: 6.2),
    .play(from: 18.6, to: 22.6, speed: 1.5),
    .beat(at: 22.6, focus: CGPoint(x: 0.71, y: 0.54), scene: .retry, hold: 4.4),
    .play(from: 22.6, to: 25.2, speed: 1.0),
    .end(at: 25.2, hold: 3.0)
]

// What the scenes say. The ids are the ones on screen in the recording.
let price = "US$4.99"
let firstCharge = "ch_ba2c3ad6-0"
let novemberCharge = "ch_cebaef2c-7"
let novemberKey = "sub-5c5f372d:2026-11"

let zoomIn = 0.85, zoomOut = 0.85, zoomMax: CGFloat = 2.5

// MARK: - Canvas

let W = 1080, H = 1350
let fps: Int32 = 30

let bgCentre = NSColor(srgbRed: 0.145, green: 0.173, blue: 0.220, alpha: 1)
let bg       = NSColor(srgbRed: 0.098, green: 0.118, blue: 0.153, alpha: 1)
let bgEdge   = NSColor(srgbRed: 0.071, green: 0.086, blue: 0.114, alpha: 1)
let panel    = NSColor(srgbRed: 0.165, green: 0.192, blue: 0.239, alpha: 1)
let ink      = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink2     = NSColor(srgbRed: 0.640, green: 0.650, blue: 0.670, alpha: 1)
let ink3     = NSColor(srgbRed: 0.420, green: 0.440, blue: 0.470, alpha: 1)
let rule     = NSColor(srgbRed: 0.247, green: 0.278, blue: 0.329, alpha: 1)
let accent   = NSColor(srgbRed: 0.498, green: 0.659, blue: 0.769, alpha: 1)
let rose     = NSColor(srgbRed: 0.788, green: 0.557, blue: 0.608, alpha: 1)
let green    = NSColor(srgbRed: 0.435, green: 0.757, blue: 0.569, alpha: 1)

func Y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }
func sans(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .monospacedSystemFont(ofSize: s, weight: w) }
func serif(_ s: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: s)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: s) { return f }
    return base
}
func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
func span(_ p: Double, _ a: Double, _ b: Double) -> CGFloat { clamp((p - a) / (b - a)) }
func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func glide(_ t: CGFloat) -> CGFloat { t * t * t * (t * (t * 6 - 15) + 10) }
func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func text(_ s: String, _ p: CGPoint, _ f: NSFont, _ c: NSColor, alpha: CGFloat = 1,
          align: NSTextAlignment = .left, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c.withAlphaComponent(alpha), .kern: tracking])
    var o = p
    let w = a.size().width
    if align == .center { o.x -= w / 2 } else if align == .right { o.x -= w }
    a.draw(at: o)
}

func paragraph(_ s: String, centreX: CGFloat, top: CGFloat, width: CGFloat, font: NSFont, colour: NSColor, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineHeightMultiple = 1.2
    let a = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: colour.withAlphaComponent(alpha), .paragraphStyle: style])
    let r = a.boundingRect(with: CGSize(width: width, height: 400), options: [.usesLineFragmentOrigin])
    a.draw(with: CGRect(x: centreX - width / 2, y: Y(top) - r.height, width: width, height: r.height + 4),
           options: [.usesLineFragmentOrigin])
}

func roundRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 2) {
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let fill { ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath() }
    if let stroke { ctx.addPath(path); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(width); ctx.strokePath() }
}

func backdrop(_ ctx: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                       colors: [bgCentre.cgColor, bg.cgColor, bgEdge.cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(g, startCenter: CGPoint(x: CGFloat(W) / 2, y: Y(600)), startRadius: 0,
                           endCenter: CGPoint(x: CGFloat(W) / 2, y: Y(600)), endRadius: 1000, options: [.drawsAfterEndLocation])
}

// MARK: - The recording

final class Clip {
    private let output: AVAssetReaderTrackOutput
    private var current: (image: CGImage, time: Double)?
    private var next: (image: CGImage, time: Double)?

    init(path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let tracks = try awaitValue { try await asset.loadTracks(withMediaType: .video) } ?? []
        guard let track = tracks.first else { throw NSError(domain: "clip", code: 1) }
        let reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)])
        reader.add(output)
        reader.startReading()
        next = pull()
    }

    private func pull() -> (CGImage, Double)? {
        guard let sample = output.copyNextSampleBuffer(), let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer),
                            height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8,
                            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = ctx?.makeImage() else { return nil }
        return (image, time)
    }

    /// Forward only: the cut never goes back in the recording.
    func frame(at time: Double) -> CGImage? {
        while let candidate = next, candidate.time <= time { current = candidate; next = pull() }
        return current?.image ?? next?.image
    }
}

func awaitValue<T>(_ body: @escaping () async throws -> T?) throws -> T? {
    let s = DispatchSemaphore(value: 0); var result: T?; var failure: Error?
    Task { do { result = try await body() } catch { failure = error }; s.signal() }
    s.wait()
    if let failure { throw failure }
    return result
}

let phone = try Clip(path: phonePath)

/// The phone on the canvas: fitted to the height, centred, with a frame of its own.
func drawPhone(_ ctx: CGContext, _ image: CGImage, zoom: CGFloat, focus: CGPoint, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let h0 = CGFloat(H) * 0.9
    let w0 = h0 * CGFloat(image.width) / CGFloat(image.height)
    let rest = CGRect(x: (CGFloat(W) - w0) / 2, y: (CGFloat(H) - h0) / 2, width: w0, height: h0)
    // Where the focus sits at rest, and where it ends up: the middle of the frame.
    let atRest = CGPoint(x: rest.minX + focus.x * w0, y: rest.maxY - focus.y * h0)
    let k = (zoom - 1) / (zoomMax - 1)
    let target = CGPoint(x: mix(atRest.x, CGFloat(W) / 2, k), y: mix(atRest.y, CGFloat(H) / 2, k))
    let w = w0 * zoom, h = h0 * zoom
    let rect = CGRect(x: target.x - focus.x * w, y: target.y - (1 - focus.y) * h, width: w, height: h)
    ctx.saveGState()
    ctx.setAlpha(alpha)
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 40, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 38 * zoom, cornerHeight: 38 * zoom, transform: nil))
    ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 38 * zoom, cornerHeight: 38 * zoom, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: rect)
    ctx.restoreGState()
}

// MARK: - The scenes

let phoneNode = CGPoint(x: 250, y: 640)
let gatewayNode = CGPoint(x: 830, y: 600)
let ledgerTop: CGFloat = 790

func node(_ ctx: CGContext, _ c: CGPoint, _ title: String, _ size: CGSize, lit: CGFloat, alpha: CGFloat, tint: NSColor = accent) {
    let r = CGRect(x: c.x - size.width / 2, y: Y(c.y) - size.height / 2, width: size.width, height: size.height)
    roundRect(ctx, r, 22, fill: panel.withAlphaComponent(alpha),
              stroke: (lit > 0 ? tint : rule).withAlphaComponent(alpha * (0.6 + 0.4 * lit)), width: 2 + lit * 1.5)
    text(title, CGPoint(x: c.x, y: Y(c.y) + size.height / 2 - 40), sans(17, .semibold), ink2, alpha: alpha, align: .center, tracking: 3)
}

func phoneGlyph(_ ctx: CGContext, alpha: CGFloat, check: CGFloat = 0) {
    let c = phoneNode
    node(ctx, c, "PHONE", CGSize(width: 190, height: 300), lit: 0, alpha: alpha)
    let screen = CGRect(x: c.x - 62, y: Y(c.y) - 105, width: 124, height: 190)
    roundRect(ctx, screen, 14, fill: NSColor.black.withAlphaComponent(0.5 * alpha))
    if check > 0.01 {
        let o = CGPoint(x: c.x, y: Y(c.y) - 10)
        ctx.setFillColor(green.withAlphaComponent(0.18 * check * alpha).cgColor)
        ctx.fillEllipse(in: CGRect(x: o.x - 34, y: o.y - 34, width: 68, height: 68))
        ctx.setStrokeColor(green.withAlphaComponent(check * alpha).cgColor); ctx.setLineWidth(5); ctx.setLineCap(.round)
        ctx.move(to: CGPoint(x: o.x - 14, y: o.y)); ctx.addLine(to: CGPoint(x: o.x - 3, y: o.y - 12)); ctx.addLine(to: CGPoint(x: o.x + 17, y: o.y + 12))
        ctx.strokePath()
    }
}

func billingGlyph(_ ctx: CGContext, alpha: CGFloat) {
    node(ctx, phoneNode, "BILLING", CGSize(width: 190, height: 300), lit: 0, alpha: alpha)
    text("Apple", CGPoint(x: phoneNode.x, y: Y(phoneNode.y) - 10), serif(30), ink, alpha: alpha, align: .center)
    text("runs November", CGPoint(x: phoneNode.x, y: Y(phoneNode.y) - 44), sans(16), ink3, alpha: alpha, align: .center)
}

func gatewayGlyph(_ ctx: CGContext, lit: CGFloat, alpha: CGFloat, tint: NSColor = accent) {
    node(ctx, gatewayNode, "GATEWAY", CGSize(width: 260, height: 200), lit: lit, alpha: alpha, tint: tint)
    text("idempotency record", CGPoint(x: gatewayNode.x, y: Y(gatewayNode.y) - 20), sans(16), ink3, alpha: alpha, align: .center)
}

/// The line between the two nodes, and where along it a packet is.
let wireFrom = CGPoint(x: phoneNode.x + 95, y: Y(phoneNode.y) + 40)
let wireTo = CGPoint(x: gatewayNode.x - 130, y: Y(gatewayNode.y) + 40)
let backFrom = CGPoint(x: gatewayNode.x - 130, y: Y(gatewayNode.y) - 40)
let backTo = CGPoint(x: phoneNode.x + 95, y: Y(phoneNode.y) - 40)
func along(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { CGPoint(x: mix(a.x, b.x, t), y: mix(a.y, b.y, t)) }

func wire(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, alpha: CGFloat, dashed: Bool = false, colour: NSColor = rule) {
    ctx.saveGState()
    ctx.setStrokeColor(colour.withAlphaComponent(alpha).cgColor); ctx.setLineWidth(2)
    if dashed { ctx.setLineDash(phase: 0, lengths: [8, 9]) }
    ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    ctx.restoreGState()
}

/// A key travelling as a labelled chip.
func chip(_ ctx: CGContext, _ label: String, at p: CGPoint, alpha: CGFloat, tint: NSColor = accent) {
    guard alpha > 0.01 else { return }
    let a = NSAttributedString(string: label, attributes: [.font: mono(17, .medium)])
    let w = a.size().width + 32
    let r = CGRect(x: p.x - w / 2, y: p.y - 21, width: w, height: 42)
    roundRect(ctx, r, 21, fill: tint.withAlphaComponent(0.20 * alpha), stroke: tint.withAlphaComponent(alpha), width: 1.5)
    text(label, CGPoint(x: p.x, y: p.y - 11), mono(17, .medium), ink, alpha: alpha, align: .center)
}

func dot(_ ctx: CGContext, at p: CGPoint, _ c: NSColor, alpha: CGFloat) {
    ctx.setFillColor(c.withAlphaComponent(alpha).cgColor)
    ctx.fillEllipse(in: CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20))
}

func cross(_ ctx: CGContext, at p: CGPoint, alpha: CGFloat) {
    ctx.setStrokeColor(rose.withAlphaComponent(alpha).cgColor); ctx.setLineWidth(4); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: p.x - 13, y: p.y - 13)); ctx.addLine(to: CGPoint(x: p.x + 13, y: p.y + 13))
    ctx.move(to: CGPoint(x: p.x + 13, y: p.y - 13)); ctx.addLine(to: CGPoint(x: p.x - 13, y: p.y + 13))
    ctx.strokePath()
}

/// The gateway's table: one row per key.
func ledger(_ ctx: CGContext, rows: [(key: String, charge: String, glow: CGFloat, show: CGFloat)], alpha: CGFloat) {
    let box = CGRect(x: 120, y: Y(ledgerTop + 240), width: 840, height: 240)
    roundRect(ctx, box, 20, fill: panel.withAlphaComponent(0.7 * alpha), stroke: rule.withAlphaComponent(alpha), width: 1.5)
    text("KEY", CGPoint(x: 160, y: Y(ledgerTop + 48)), sans(14, .semibold), ink3, alpha: alpha, tracking: 2.5)
    text("CHARGE", CGPoint(x: 600, y: Y(ledgerTop + 48)), sans(14, .semibold), ink3, alpha: alpha, tracking: 2.5)
    for (i, row) in rows.enumerated() {
        let a = alpha * row.show
        guard a > 0.01 else { continue }
        let top = ledgerTop + 76 + CGFloat(i) * 64 + (1 - row.show) * 16
        if row.glow > 0.01 {
            roundRect(ctx, CGRect(x: 140, y: Y(top + 46), width: 800, height: 54), 12,
                      fill: green.withAlphaComponent(0.16 * row.glow * alpha), stroke: green.withAlphaComponent(0.8 * row.glow * alpha), width: 1.5)
        }
        text(row.key, CGPoint(x: 160, y: Y(top + 30)), mono(20, .medium), ink, alpha: a)
        text(row.charge, CGPoint(x: 600, y: Y(top + 30)), mono(20), ink2, alpha: a)
    }
}

func heading(_ step: String, _ title: String, _ line: String, alpha: CGFloat) {
    text(step, CGPoint(x: CGFloat(W) / 2, y: Y(120)), mono(18, .semibold), accent, alpha: alpha, align: .center, tracking: 3)
    text(title, CGPoint(x: CGFloat(W) / 2, y: Y(190)), serif(54), ink, alpha: alpha, align: .center)
    paragraph(line, centreX: CGFloat(W) / 2, top: 230, width: 860, font: sans(24), colour: ink2, alpha: alpha)
}

/// One scene at progress `p` (0…1 over its hold), drawn at `alpha`.
func drawScene(_ ctx: CGContext, _ scene: Scene, _ p: Double, alpha: CGFloat) {
    guard alpha > 0.01 else { return }
    let inA = alpha * glide(span(p, 0, 0.12))
    switch scene {

    case .request:
        heading("1 / 4", "One tap, one key", "Face ID unlocks the card. The charge leaves with a key made for this purchase.", alpha: inA)
        phoneGlyph(ctx, alpha: inA)
        gatewayGlyph(ctx, lit: glide(span(p, 0.70, 0.80)), alpha: inA)
        wire(ctx, wireFrom, wireTo, alpha: inA)
        let travel = ease(span(p, 0.30, 0.72))
        chip(ctx, "POST /v1/charges · key", at: along(wireFrom, wireTo, travel), alpha: inA * (p > 0.22 ? 1 : 0))
        ledger(ctx, rows: [], alpha: inA * 0.6)

    case .charge:
        heading("2 / 4", "Charged, and written down", "The gateway takes \(price) and files the receipt under that key. Then it answers.", alpha: inA)
        let back = ease(span(p, 0.55, 0.85))
        phoneGlyph(ctx, alpha: inA, check: glide(span(p, 0.85, 0.95)))
        gatewayGlyph(ctx, lit: 1 - span(p, 0.6, 0.9), alpha: inA)
        wire(ctx, backFrom, backTo, alpha: inA)
        if p > 0.5 && p < 0.88 { dot(ctx, at: along(backFrom, backTo, back), green, alpha: inA) }
        ledger(ctx, rows: [("this purchase", "\(firstCharge) · \(price)", 0, glide(span(p, 0.15, 0.35)))], alpha: inA)

    case .lost:
        heading("3 / 4", "The answer never arrived",
                "Apple bills November. The gateway charges — and the answer is lost on the way back.", alpha: inA * (1 - span(p, 0.46, 0.5)))
        heading("3 / 4", "Same key, same receipt",
                "The phone cannot know the money moved. It asks again with the same key — and gets the first receipt back.",
                alpha: inA * span(p, 0.5, 0.54))
        billingGlyph(ctx, alpha: inA)
        let found = glide(span(p, 0.72, 0.8))
        gatewayGlyph(ctx, lit: max(glide(span(p, 0.2, 0.26)) * (1 - span(p, 0.3, 0.4)), found), alpha: inA,
                     tint: found > 0 ? green : accent)
        wire(ctx, wireFrom, wireTo, alpha: inA)
        wire(ctx, backFrom, backTo, alpha: inA)
        // First try: out, charged, back — dies halfway.
        chip(ctx, novemberKey, at: along(wireFrom, wireTo, ease(span(p, 0.06, 0.2))), alpha: inA * (p < 0.22 ? 1 : 0))
        let lostAt: CGFloat = 0.55
        let lostP = ease(span(p, 0.26, 0.36))
        if p > 0.26 && p < 0.36 { dot(ctx, at: along(backFrom, backTo, lostP * lostAt), rose, alpha: inA) }
        if p >= 0.36 {
            let fade = 1 - span(p, 0.62, 0.7)
            cross(ctx, at: along(backFrom, backTo, lostAt), alpha: inA * fade)
            wire(ctx, backFrom, along(backFrom, backTo, lostAt), alpha: inA * fade, dashed: true, colour: rose)
        }
        // The silence.
        if p > 0.36 && p < 0.52 {
            let ms = Int(Double(span(p, 0.37, 0.5)) * 843)
            text("\(ms) ms with no answer", CGPoint(x: CGFloat(W) / 2, y: Y(470)), mono(26, .medium), rose,
                 alpha: inA * min(span(p, 0.36, 0.39), 1 - span(p, 0.49, 0.52)), align: .center)
        }
        // Second try: same key, found, answered.
        chip(ctx, novemberKey, at: along(wireFrom, wireTo, ease(span(p, 0.54, 0.7))),
             alpha: inA * (p >= 0.54 && p < 0.72 ? 1 : 0))
        if p > 0.8 && p < 0.92 { dot(ctx, at: along(backFrom, backTo, ease(span(p, 0.8, 0.92))), green, alpha: inA) }
        ledger(ctx, rows: [("sub-…:2026-10", "\(firstCharge)", 0, 1),
                           (novemberKey, "\(novemberCharge)", found * (1 - span(p, 0.95, 1)), glide(span(p, 0.2, 0.28)))],
               alpha: inA)
        if p > 0.86 {
            text("charges for November: 1", CGPoint(x: CGFloat(W) / 2, y: Y(1110)), mono(24, .semibold), green,
                 alpha: inA * span(p, 0.86, 0.9), align: .center)
        }

    case .retry:
        heading("4 / 4", "November, billed again",
                "A billing job reruns after a crash. Same month, same key — the gateway answers from its record. No new charge.", alpha: inA)
        billingGlyph(ctx, alpha: inA)
        let found = glide(span(p, 0.5, 0.58))
        gatewayGlyph(ctx, lit: found, alpha: inA, tint: green)
        wire(ctx, wireFrom, wireTo, alpha: inA)
        wire(ctx, backFrom, backTo, alpha: inA)
        chip(ctx, novemberKey, at: along(wireFrom, wireTo, ease(span(p, 0.18, 0.48))), alpha: inA * (p > 0.12 && p < 0.5 ? 1 : 0))
        if p > 0.6 && p < 0.78 { dot(ctx, at: along(backFrom, backTo, ease(span(p, 0.6, 0.78))), green, alpha: inA) }
        ledger(ctx, rows: [("sub-…:2026-10", "\(firstCharge)", 0, 1),
                           (novemberKey, "\(novemberCharge)  ← replayed", found, 1)], alpha: inA)
        if p > 0.74 {
            text("charges for November: still 1", CGPoint(x: CGFloat(W) / 2, y: Y(1110)), mono(24, .semibold), green,
                 alpha: inA * span(p, 0.74, 0.8), align: .center)
        }
    }
}

// MARK: - The timeline

struct Piece { let start: Double; let length: Double; let shot: Shot }
var pieces: [Piece] = []
var clock = 0.0
for shot in cut {
    let length: Double
    switch shot {
    case .play(let from, let to, let speed): length = (to - from) / speed
    case .beat(_, _, _, let hold): length = zoomIn + hold + zoomOut
    case .end(_, let hold): length = hold
    }
    pieces.append(Piece(start: clock, length: length, shot: shot))
    clock += length
}
let total = clock

func drawFrame(_ ctx: CGContext, _ t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    backdrop(ctx)

    let piece = pieces.last { $0.start <= t } ?? pieces[0]
    let local = t - piece.start
    switch piece.shot {

    case .play(let from, _, let speed):
        if let image = phone.frame(at: from + local * speed) {
            drawPhone(ctx, image, zoom: 1, focus: CGPoint(x: 0.5, y: 0.5), alpha: 1)
        }

    case .beat(let at, let focus, let scene, let hold):
        let image = phone.frame(at: at)
        let zoom: CGFloat
        let sceneAlpha: CGFloat
        if local < zoomIn {
            let k = glide(clamp(local / zoomIn))
            zoom = mix(1, zoomMax, k)
            sceneAlpha = clamp((local - zoomIn * 0.55) / (zoomIn * 0.45))
        } else if local < zoomIn + hold {
            zoom = zoomMax
            sceneAlpha = 1
        } else {
            let k = glide(clamp((local - zoomIn - hold) / zoomOut))
            zoom = mix(zoomMax, 1, k)
            sceneAlpha = 1 - clamp((local - zoomIn - hold) / (zoomOut * 0.45))
        }
        if let image { drawPhone(ctx, image, zoom: zoom, focus: focus, alpha: 1 - sceneAlpha) }
        if sceneAlpha > 0.01 {
            // The scene gets a clean ground of its own: a recording showing through behind
            // the diagram reads as a mistake, not as depth.
            ctx.saveGState(); ctx.setAlpha(sceneAlpha); backdrop(ctx); ctx.restoreGState()
            drawScene(ctx, scene, (local - zoomIn) / hold, alpha: sceneAlpha)
        }

    case .end(let at, let hold):
        if let image = phone.frame(at: at) { drawPhone(ctx, image, zoom: 1, focus: CGPoint(x: 0.5, y: 0.5), alpha: 1) }
        let on = glide(clamp(local / 0.8))
        ctx.setFillColor(bg.withAlphaComponent(0.9 * on).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        text("Same key twice.", CGPoint(x: CGFloat(W) / 2, y: Y(640)), serif(64), ink, alpha: on, align: .center)
        text("One charge.", CGPoint(x: CGFloat(W) / 2, y: Y(720)), serif(64), green, alpha: on, align: .center)
        _ = hold
    }
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Output

let space = CGColorSpaceCreateDeviceRGB()
let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
func render(_ t: Double) -> CGImage {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    drawFrame(ctx, t)
    return ctx.makeImage()!
}

if let at = value("--png").flatMap(Double.init) {
    // A still needs the recording read up to that point, frame by frame.
    var t = 0.0
    while t < at { _ = render(t); t += 1.0 / Double(fps) }
    try NSBitmapImageRep(cgImage: render(at)).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) at \(at) of \(String(format: "%.1f", total))s"); exit(0)
}

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)

let frames = Int(total * Double(fps))
for frame in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    // Drawn into a context of our own and blitted across: AppKit text drawn straight into
    // a pixel buffer's memory does not survive the encode.
    let image = render(Double(frame) / Double(fps))
    var maybe: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &maybe)
    let buffer = maybe!
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: space, bitmapInfo: info)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: W, height: H)); ctx.flush()
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { print("failed: \(writer.error?.localizedDescription ?? "?")"); exit(1) }
print("wrote \(outPath)  \(String(format: "%.1f", total))s")
