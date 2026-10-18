// The recording and the gateway in one frame: what each tap sends, what comes back.
//
//   swift tools/RenderExplainer.swift out.mp4 -phone recording.mp4
//   swift tools/RenderExplainer.swift frame.png -phone recording.mp4 --png 12.0
//
// The recording never leaves the screen. The key leaves the button that was pressed and
// flies to the gateway, a line is written there, the answer flies back to the part of the
// screen that changed. The camera follows it.
//
// Two clocks run through the edit. Source time is the recording's: what is on the phone.
// Output time is the film's: where the camera is, what is in flight, which caption is up.
// `sourceTime(_:)` maps one to the other — fast through navigation, held on each tap while
// the key travels. A new recording needs new numbers in "The edit" and nothing else.

import AVFoundation
import AppKit

// MARK: - Arguments

func value(_ name: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count
    else { return nil }
    return CommandLine.arguments[i + 1]
}
let outPath = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-")
              ? CommandLine.arguments[1] : "explainer.mp4"
guard let phonePath = value("-phone") else { print("need -phone <recording>"); exit(1) }

// MARK: - The recording

final class Clip {
    private let output: AVAssetReaderTrackOutput
    private var current: (image: CGImage, time: Double)?
    private var next: (image: CGImage, time: Double)?
    let duration: Double
    /// Width over height, from the first frame.
    var aspect: CGFloat {
        guard let image = (current ?? next)?.image else { return 9.0 / 19.5 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    init(path: String) throws {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let tracks = try awaitValue { try await asset.loadTracks(withMediaType: .video) } ?? []
        guard let track = tracks.first else { throw NSError(domain: "clip", code: 1) }
        duration = (try awaitValue { try await asset.load(.duration) }).map(CMTimeGetSeconds) ?? 0
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
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = ctx?.makeImage() else { return nil }
        return (image, time)
    }

    func frame(at time: Double) -> CGImage? {
        while let candidate = next, candidate.time <= time { current = candidate; next = pull() }
        return current?.image ?? next?.image
    }
}

func awaitValue<T>(_ body: @escaping () async throws -> T?) throws -> T? {
    let semaphore = DispatchSemaphore(value: 0)
    var result: T?, failure: Error?
    Task { do { result = try await body() } catch { failure = error }; semaphore.signal() }
    semaphore.wait()
    if let failure { throw failure }
    return result
}


let phone = try Clip(path: phonePath)

// MARK: - Canvas

let W = 1080, H = 1350
let fps: Int32 = 30

// A backdrop rather than black: lighter at the centre, deeper at the edges, so a zoom
// shows colour around the subject instead of a void.
let bg       = NSColor(srgbRed: 0.098, green: 0.118, blue: 0.153, alpha: 1)
let bgCentre = NSColor(srgbRed: 0.145, green: 0.173, blue: 0.220, alpha: 1)
let bgEdge   = NSColor(srgbRed: 0.071, green: 0.086, blue: 0.114, alpha: 1)
let panel    = NSColor(srgbRed: 0.165, green: 0.192, blue: 0.239, alpha: 1)
let ink    = NSColor(srgbRed: 0.929, green: 0.918, blue: 0.894, alpha: 1)
let ink2   = NSColor(srgbRed: 0.600, green: 0.604, blue: 0.612, alpha: 1)
let ink3   = NSColor(srgbRed: 0.380, green: 0.388, blue: 0.404, alpha: 1)
let rule   = NSColor(srgbRed: 0.247, green: 0.278, blue: 0.329, alpha: 1)
let accent = NSColor(srgbRed: 0.498, green: 0.659, blue: 0.769, alpha: 1)
let rose   = NSColor(srgbRed: 0.788, green: 0.557, blue: 0.608, alpha: 1)
let green  = NSColor(srgbRed: 0.435, green: 0.757, blue: 0.569, alpha: 1)

// Everything below is laid out from the top of the canvas; `p` turns it into Core Graphics.
let phoneX: CGFloat = 48, phoneW: CGFloat = 430, phoneTop: CGFloat = 176
let phoneH = phoneW / phone.aspect
let panelX: CGFloat = 590, panelRight: CGFloat = 1036, panelTop: CGFloat = 176
let entryTop: CGFloat = 262, entryStep: CGFloat = 104

func p(_ q: CGPoint) -> CGPoint { CGPoint(x: q.x, y: CGFloat(H) - q.y) }
func y(_ fromTop: CGFloat) -> CGFloat { CGFloat(H) - fromTop }
/// A point on the recording's screen, given as a fraction of it.
func screen(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: phoneX + fx * phoneW, y: phoneTop + fy * phoneH) }
/// Where a request lands on the gateway's panel: the left edge of its line.
func row(_ i: Int) -> CGPoint { CGPoint(x: panelX + 14, y: entryTop + CGFloat(i) * entryStep + 40) }

func sans(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { .monospacedSystemFont(ofSize: s, weight: w) }
func serif(_ s: CGFloat) -> NSFont {
    let base = NSFont.systemFont(ofSize: s)
    if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: s) { return f }
    return base
}
func clamp(_ v: Double) -> CGFloat { CGFloat(min(1, max(0, v))) }
func fade(_ t: Double, _ from: Double, _ over: Double) -> CGFloat { clamp((t - from) / over) }
func ease(_ t: CGFloat) -> CGFloat { t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
/// Leaves at speed and settles: what a thing thrown across the frame should do.
func dart(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
/// Smootherstep: zero velocity and zero acceleration at both ends, for the camera.
func glide(_ t: CGFloat) -> CGFloat { t * t * t * (t * (t * 6 - 15) + 10) }

func text(_ s: String, _ at: CGPoint, _ f: NSFont, _ c: NSColor, alpha: CGFloat = 1,
          align: NSTextAlignment = .left, tracking: CGFloat = 0) {
    guard alpha > 0.01 else { return }
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: c.withAlphaComponent(alpha), .kern: tracking])
    var o = at
    let w = a.size().width
    if align == .center { o.x -= w / 2 } else if align == .right { o.x -= w }
    a.draw(at: o)
}

func roundRect(_ ctx: CGContext, _ r: CGRect, _ radius: CGFloat, fill: NSColor? = nil, stroke: NSColor? = nil, width: CGFloat = 2) {
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    if let fill { ctx.addPath(path); ctx.setFillColor(fill.cgColor); ctx.fillPath() }
    if let stroke { ctx.addPath(path); ctx.setStrokeColor(stroke.cgColor); ctx.setLineWidth(width); ctx.strokePath() }
}

/// A curve that leaves and arrives level, so a flight from the phone to the panel reads as a path.
func along(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    let c1 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: a.y), c2 = CGPoint(x: a.x + (b.x - a.x) * 0.5, y: b.y)
    let u = 1 - t
    return CGPoint(x: u*u*u*a.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*b.x,
                   y: u*u*u*a.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*b.y)
}

// MARK: - The edit

// Где что на экране записи: тёмная тема, его iPhone.
let payButton   = screen(0.50, 0.511)
let chargeRow   = screen(0.50, 0.4885)
let billButton  = screen(0.50, 0.587)
let retryButton = screen(0.725, 0.585)
let outcomeText = screen(0.50, 0.6555)
let historyRow  = screen(0.50, 0.784)

/// Время фильма → время записи. Плоские участки — паузы: экран стоит, пока летит ключ.
///
/// На каждой строке шлюза камера стоит около двух секунд. Меньше — и прочитать строку
/// не успеваешь: она появляется и тут же уезжает, а ради неё всё и затевалось.
/// Разрешение на Face ID (5,5–7,0 с записи) пропущено — это след переустановки.
let timeline: [(t: Double, s: Double)] = [
    (0.0, 0.30), (0.4, 0.30),        // кошелёк, одно мгновение
    (1.5, 3.00), (2.1, 3.30),        // к странице Apple, и нажатие
    (2.7, 5.20),                     // лист поднялся
    (3.3, 5.42),                     // нажал Pay with Wallet
    (3.9, 5.46),                     // держим на нажатии
    (5.1, 7.40),                     // Face ID — мимо разрешения
    (5.9, 8.20),                     // списано
    (7.9, 8.20),                     // стоим на строке шлюза
    (8.7, 9.40),                     // подписан
    (9.5, 9.60),
    (10.3, 11.90),                   // назад в кошелёк
    (11.1, 15.00),                   // к подписке, быстро
    (11.9, 16.60),
    (12.5, 16.85), (13.3, 16.90),    // Bill November, и держим
    (14.3, 19.30),                   // ожидание
    (14.9, 19.40),                   // списано
    (16.9, 19.50),                   // стоим на строке, потом ответ теряется
    (18.7, 19.60),                   // 800 мс тишины
    (19.7, 19.65),                   // тот же ключ снова
    (20.5, 19.70),                   // повтор из записи
    (22.5, 19.80),                   // стоим на нём
    (23.5, 21.00),
    (24.5, 23.40), (25.1, 23.60),    // Retry November
    (25.9, 23.70),
    (26.9, 24.40),                   // повтор
    (28.9, 24.60),                   // стоим: ноябрь всё ещё одно списание
    (30.1, 25.60), (31.1, 27.00),
    (33.7, 27.00)                    // держим
]

/// Строки шлюза, по часам фильма. Номера списаний — те, что видны на записи.
struct Line { let at: Double; let source: Double; let level: String; let head: String; let detail: String; let colour: NSColor }
let lines: [Line] = [
    Line(at: 5.1,  source: 8.20,  level: "INFO", head: "charged", detail: "ch_c2d64fb9-2  US$4.99  charges=1", colour: ink),
    Line(at: 14.3, source: 19.40, level: "INFO", head: "charged", detail: "key=sub-0c90f8ad:2026-11", colour: ink),
    Line(at: 16.9, source: 19.50, level: "WARN", head: "response dropped", detail: "ch_5eea4c4a-d  the money moved", colour: rose),
    Line(at: 19.7, source: 19.65, level: "INFO", head: "replayed — not charged again", detail: "ch_5eea4c4a-d  charges=1", colour: green),
    Line(at: 26.9, source: 24.40, level: "INFO", head: "replayed — not charged again", detail: "ch_5eea4c4a-d  charges=1", colour: green)
]
let countAt = 28.3

/// Когда проявляется панель шлюза — за мгновение до того, как к ней полетит первый ключ.
let panelAppears = 3.1

/// Ключ в пути к шлюзу: он вылетает из нажатой кнопки.
struct Request { let from: Double; let to: Double; let start: CGPoint; let row: Int; let label: String }
let monthKey = "sub-0c90f8ad:2026-11"
let requests: [Request] = [
    Request(from: 3.9,  to: 5.1,  start: payButton,   row: 0, label: "POST · new key"),
    Request(from: 13.3, to: 14.3, start: billButton,  row: 1, label: monthKey),
    Request(from: 18.7, to: 19.7, start: billButton,  row: 3, label: monthKey),
    Request(from: 25.9, to: 26.9, start: retryButton, row: 4, label: monthKey)
]

/// Ответ на пути назад: он садится на то место экрана, которое меняет, или гибнет.
/// Вылетает он внутри паузы на шлюзе — тогда видно, откуда он взялся.
struct Answer { let from: Double; let to: Double; let row: Int; let end: CGPoint; let lost: Bool }
let answers: [Answer] = [
    Answer(from: 6.9,  to: 7.7,  row: 0, end: chargeRow,   lost: false),
    Answer(from: 15.5, to: 16.3, row: 1, end: outcomeText, lost: true),
    Answer(from: 20.7, to: 21.5, row: 3, end: outcomeText, lost: false),
    Answer(from: 27.5, to: 28.3, row: 4, end: historyRow,  lost: false)
]
let lostReach: CGFloat = 0.32
let silence = (from: 16.3, to: 18.7, ms: 800.0)

/// Нажатие по экрану.
let taps: [(at: Double, point: CGPoint)] = [(3.3, payButton), (12.5, billButton), (25.1, retryButton)]

/// Что изменил ответ — обводится прямо на записи. Каждая рамка ждёт, пока то, что она
/// обводит, появится на экране: пока идёт «Paying…», обводить ещё нечего.
struct Mark { let from: Double; let to: Double; let centre: CGPoint; let size: CGSize }
let marks: [Mark] = [
    Mark(from: 8.9,  to: 10.2, centre: chargeRow,   size: CGSize(width: 410, height: 34)),
    Mark(from: 22.7, to: 24.3, centre: outcomeText, size: CGSize(width: 410, height: 72)),
    Mark(from: 29.5, to: 31.5, centre: historyRow,  size: CGSize(width: 410, height: 92))
]

/// Куда смотрит камера: приближение, точка взгляда и где эта точка на экране.
struct Shot { let t: Double; let zoom: CGFloat; let fx: CGFloat; let fy: CGFloat; let sy: CGFloat }
func wide(_ t: Double, _ z: CGFloat = 1) -> Shot { Shot(t: t, zoom: z, fx: 540, fy: 675, sy: 675) }
func look(_ t: Double, _ z: CGFloat, _ x: CGFloat, _ y: CGFloat) -> Shot { Shot(t: t, zoom: z, fx: x, fy: y, sy: 640) }
let shots: [Shot] = [
    look(0, 1.45, 263, 560), look(1.2, 1.5, 263, 600),         // только телефон: шлюза ещё нет
    look(2.3, 1.7, 263, 640), look(3.9, 1.7, 263, 640),        // нажатие
    look(4.6, 1.15, 540, 470),                                  // оба, пока летит ключ
    look(5.2, 1.8, 813, 300), look(7.3, 1.8, 813, 300),         // charged — стоим и читаем
    look(7.9, 1.15, 540, 470),
    look(8.6, 1.7, 263, 620), look(10.1, 1.7, 263, 620),        // списание на телефоне
    wide(10.8), wide(11.9),
    look(12.5, 1.7, 263, 720), look(13.3, 1.7, 263, 720),       // Bill November
    look(13.8, 1.15, 540, 560),
    look(14.3, 1.75, 813, 420), look(16.5, 1.75, 813, 420),     // charged — стоим
    look(17.3, 1.3, 540, 520), look(18.7, 1.32, 540, 530),      // потерянный ответ и тишина
    look(19.2, 1.15, 540, 640),
    look(19.7, 1.75, 813, 580), look(21.9, 1.75, 813, 580),     // replayed — стоим
    look(22.5, 1.15, 540, 680),
    look(23.1, 1.7, 263, 760), look(24.2, 1.7, 263, 760),       // что увидел телефон
    look(25.1, 1.7, 330, 730), look(25.9, 1.7, 330, 730),       // Retry November
    look(26.3, 1.15, 560, 700),
    look(26.9, 1.6, 813, 760), look(29.1, 1.6, 813, 760),       // replayed и счёт — стоим
    look(29.5, 1.15, 540, 780),
    look(30.1, 1.7, 263, 880), look(31.2, 1.7, 263, 880),       // история списаний
    wide(32.1), wide(33.7, 1.03)
]

struct Caption { let from: Double; let to: Double; let step: String; let line: String }
let captions: [Caption] = [
    Caption(from: 2.9,  to: 5.5,  step: "1 / 4", line: "Tap. Face ID. The charge leaves with a new key."),
    Caption(from: 6.1,  to: 10.2, step: "2 / 4", line: "Charged US$4.99, filed under that key."),
    Caption(from: 12.1, to: 16.3, step: "3 / 4", line: "Apple bills November. One key for the month."),
    Caption(from: 16.3, to: 19.1, step: "3 / 4", line: "The money moved. The answer never came back."),
    Caption(from: 19.1, to: 24.3, step: "3 / 4", line: "Same key again: the same receipt, no new charge."),
    Caption(from: 24.7, to: 31.5, step: "4 / 4", line: "Billing runs November again. Still one charge."),
    Caption(from: 31.9, to: 33.7, step: "",      line: "One key per month. One charge.")
]

var total: Double { timeline.last!.t }

func sourceTime(_ t: Double) -> Double {
    for (a, b) in zip(timeline, timeline.dropFirst()) where t <= b.t {
        let f = (t - a.t) / max(b.t - a.t, 0.0001)
        return a.s + (b.s - a.s) * max(0, min(1, f))
    }
    return timeline.last!.s
}

func shot(_ t: Double) -> Shot {
    for (a, b) in zip(shots, shots.dropFirst()) where t <= b.t {
        let f = glide(clamp((t - a.t) / max(b.t - a.t, 0.0001)))
        func mix(_ x: CGFloat, _ z: CGFloat) -> CGFloat { x + (z - x) * f }
        return Shot(t: t, zoom: mix(a.zoom, b.zoom), fx: mix(a.fx, b.fx), fy: mix(a.fy, b.fy), sy: mix(a.sy, b.sy))
    }
    return shots.last!
}

func clock(_ s: Double) -> String { String(format: "23:44:%06.3f", s) }

// MARK: - The pieces

/// A key in flight: a pill with the key written on it.
func chip(_ ctx: CGContext, _ label: String, at c: CGPoint, alpha: CGFloat, scale: CGFloat = 1) {
    guard alpha > 0.01 else { return }
    let font = mono(15 * scale, .medium)
    let w = NSAttributedString(string: label, attributes: [.font: font]).size().width + 26 * scale
    let h = 34 * scale
    let r = CGRect(x: c.x - w / 2, y: y(c.y) - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: NSColor.black.withAlphaComponent(0.5 * alpha).cgColor)
    roundRect(ctx, r, h / 2, fill: NSColor(srgbRed: 0.13, green: 0.18, blue: 0.23, alpha: alpha))
    ctx.restoreGState()
    roundRect(ctx, r, h / 2, stroke: accent.withAlphaComponent(alpha), width: 1.5)
    text(label, CGPoint(x: c.x, y: y(c.y) - 9 * scale), font, ink, alpha: alpha, align: .center)
}

func dot(_ ctx: CGContext, _ c: CGPoint, _ colour: NSColor, alpha: CGFloat, radius: CGFloat = 8) {
    ctx.setFillColor(colour.withAlphaComponent(0.25 * alpha).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - radius * 2, y: y(c.y) - radius * 2, width: radius * 4, height: radius * 4))
    ctx.setFillColor(colour.withAlphaComponent(alpha).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - radius, y: y(c.y) - radius, width: radius * 2, height: radius * 2))
}

/// The path a flight takes, drawn faintly behind it.
func trail(_ ctx: CGContext, _ a: CGPoint, _ b: CGPoint, upTo t: CGFloat, _ colour: NSColor, alpha: CGFloat, dashed: Bool = false) {
    guard alpha > 0.01, t > 0 else { return }
    ctx.saveGState()
    ctx.setStrokeColor(colour.withAlphaComponent(alpha).cgColor); ctx.setLineWidth(2)
    if dashed { ctx.setLineDash(phase: 0, lengths: [6, 7]) }
    ctx.move(to: p(a))
    for i in 1...40 { ctx.addLine(to: p(along(a, b, t * CGFloat(i) / 40))) }
    ctx.strokePath()
    ctx.restoreGState()
}

func cross(_ ctx: CGContext, _ c: CGPoint, alpha: CGFloat) {
    let o = p(c)
    ctx.setStrokeColor(rose.withAlphaComponent(alpha).cgColor); ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: o.x - 10, y: o.y - 10)); ctx.addLine(to: CGPoint(x: o.x + 10, y: o.y + 10))
    ctx.move(to: CGPoint(x: o.x + 10, y: o.y - 10)); ctx.addLine(to: CGPoint(x: o.x - 10, y: o.y + 10))
    ctx.strokePath()
}

// MARK: - One frame

func drawScene(_ ctx: CGContext, _ s: Double, film t: Double) {
    ctx.setLineCap(.round)

    // The phone
    if let image = phone.frame(at: min(s, phone.duration - 0.05)) {
        let rect = CGRect(x: phoneX, y: y(phoneTop + phoneH), width: phoneW, height: phoneH)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 36, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.clip()
        ctx.draw(image, in: rect)
        ctx.restoreGState()
        ctx.setStrokeColor(rule.cgColor); ctx.setLineWidth(1.5)
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: -0.75, dy: -0.75), cornerWidth: 34, cornerHeight: 34, transform: nil))
        ctx.strokePath()
    }

    // Шлюз появляется вместе с первым ключом: пустая панель в полкадра с самого начала
    // ничего не объясняет, а только отнимает место у телефона.
    let panelOn = fade(t, panelAppears, 1.0)
    ctx.saveGState()
    ctx.setAlpha(panelOn)
    let panelRect = CGRect(x: panelX, y: y(panelTop + phoneH), width: panelRight - panelX, height: phoneH)
    roundRect(ctx, panelRect, 22, fill: panel)
    text("gateway", CGPoint(x: panelX + 26, y: y(panelTop + 50)), mono(20, .semibold), ink)
    ctx.setFillColor(green.cgColor)
    ctx.fillEllipse(in: CGRect(x: panelRight - 178, y: y(panelTop + 41), width: 9, height: 9))
    text("records by key", CGPoint(x: panelRight - 162, y: y(panelTop + 48)), mono(14), ink3)
    ctx.setStrokeColor(rule.cgColor); ctx.setLineWidth(1)
    ctx.move(to: CGPoint(x: panelX + 26, y: y(panelTop + 66))); ctx.addLine(to: CGPoint(x: panelRight - 26, y: y(panelTop + 66)))
    ctx.strokePath()

    for (i, line) in lines.enumerated() where t >= line.at {
        let on = fade(t, line.at, 0.22)
        let top = entryTop + CGFloat(i) * entryStep + (1 - ease(on)) * 10
        // A line just written glows for a moment.
        let glow = (1 - fade(t, line.at + 0.4, 0.6)) * on
        if glow > 0.01 {
            roundRect(ctx, CGRect(x: panelX + 12, y: y(top + 90), width: panelRight - panelX - 24, height: 92), 12,
                      fill: line.colour.withAlphaComponent(0.10 * glow), stroke: line.colour.withAlphaComponent(0.5 * glow), width: 1.5)
        }
        text(clock(line.source), CGPoint(x: panelX + 26, y: y(top + 18)), mono(14), ink3, alpha: on)
        text(line.level, CGPoint(x: panelX + 160, y: y(top + 18)), mono(14, .semibold),
             line.level == "WARN" ? rose : ink3, alpha: on)
        text(line.head, CGPoint(x: panelX + 26, y: y(top + 48)), mono(19, .medium), line.colour, alpha: on)
        text(line.detail, CGPoint(x: panelX + 26, y: y(top + 74)), mono(14), ink3, alpha: on)
    }

    // The silence, counted where the next line will be written.
    if t > silence.from && t < silence.to + 0.4 {
        let on = min(fade(t, silence.from, 0.3), 1 - fade(t, silence.to, 0.4))
        let ms = Int(Double(clamp((t - silence.from) / (silence.to - silence.from))) * silence.ms)
        let top = entryTop + 3 * entryStep
        text("no answer", CGPoint(x: panelX + 26, y: y(top + 30)), mono(15), rose, alpha: on)
        text("\(ms) ms", CGPoint(x: panelX + 26, y: y(top + 74)), mono(36, .semibold), rose, alpha: on)
    }

    // The count
    if t >= countAt {
        let on = fade(t, countAt, 0.5)
        let top = entryTop + CGFloat(lines.count) * entryStep + 30
        ctx.setStrokeColor(rule.withAlphaComponent(on).cgColor); ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: panelX + 26, y: y(top))); ctx.addLine(to: CGPoint(x: panelRight - 26, y: y(top))); ctx.strokePath()
        text("November = 1 charge", CGPoint(x: panelX + 26, y: y(top + 58)), mono(30, .semibold), ink, alpha: on)
        text("three requests, one key", CGPoint(x: panelX + 26, y: y(top + 88)), mono(15), ink3, alpha: on)
    }
    ctx.restoreGState()

    // On the recording: the press, and what the answer changed.
    for tap in taps where t >= tap.at && t < tap.at + 0.7 {
        let k = clamp((t - tap.at) / 0.7)
        let o = p(tap.point)
        let r = 10 + 46 * ease(k)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9 * (1 - k)).cgColor); ctx.setLineWidth(3)
        ctx.strokeEllipse(in: CGRect(x: o.x - r, y: o.y - r, width: r * 2, height: r * 2))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.5 * (1 - fade(t, tap.at + 0.1, 0.25))).cgColor)
        ctx.fillEllipse(in: CGRect(x: o.x - 18, y: o.y - 18, width: 36, height: 36))
    }
    for m in marks where t >= m.from && t <= m.to {
        let on = min(fade(t, m.from, 0.25), 1 - fade(t, m.to - 0.3, 0.3))
        let r = CGRect(x: m.centre.x - m.size.width / 2, y: y(m.centre.y) - m.size.height / 2,
                       width: m.size.width, height: m.size.height).insetBy(dx: -(1 - ease(on)) * 8, dy: -(1 - ease(on)) * 8)
        roundRect(ctx, r, 10, fill: green.withAlphaComponent(0.10 * on), stroke: green.withAlphaComponent(0.95 * on), width: 2.5)
    }

    // Requests: the key leaves the button and lands on the line it causes.
    for r in requests where t >= r.from && t <= r.to + 0.5 {
        let k = dart(clamp((t - r.from) / (r.to - r.from)))
        let end = row(r.row)
        let gone = 1 - fade(t, r.to, 0.3)
        trail(ctx, r.start, end, upTo: k, accent, alpha: 0.45 * gone)
        let pop = glide(fade(t, r.from, 0.18))
        chip(ctx, r.label, at: along(r.start, end, k), alpha: gone * pop, scale: 0.72 + 0.28 * pop)
    }

    // Answers: one dies on the way, the others land on what they change.
    for a in answers where t >= a.from {
        let start = row(a.row)
        let k = dart(clamp((t - a.from) / (a.to - a.from)))
        if a.lost {
            let stop = along(start, a.end, lostReach)
            let gone = 1 - fade(t, silence.to, 0.5)
            trail(ctx, start, a.end, upTo: k * lostReach, rose, alpha: 0.6 * gone, dashed: true)
            if k < 1 { dot(ctx, along(start, a.end, k * lostReach), rose, alpha: 1) }
            else { cross(ctx, stop, alpha: gone) }
        } else if t <= a.to + 0.6 {
            let gone = 1 - fade(t, a.to, 0.5)
            trail(ctx, start, a.end, upTo: k, green, alpha: 0.45 * gone)
            if k < 1 { dot(ctx, along(start, a.end, k), green, alpha: 1) }
            else {
                let o = p(a.end), rr = 12 + 30 * fade(t, a.to, 0.5)
                ctx.setStrokeColor(green.withAlphaComponent(gone).cgColor); ctx.setLineWidth(2.5)
                ctx.strokeEllipse(in: CGRect(x: o.x - rr, y: o.y - rr, width: rr * 2, height: rr * 2))
            }
        }
    }
}

func drawFrame(_ ctx: CGContext, _ t: Double) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    // The backdrop is drawn in screen space, under the camera, so it always fills the frame.
    let backdrop = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                              colors: [bgCentre.cgColor, bg.cgColor, bgEdge.cgColor] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawRadialGradient(backdrop, startCenter: CGPoint(x: CGFloat(W) / 2, y: y(560)), startRadius: 0,
                           endCenter: CGPoint(x: CGFloat(W) / 2, y: y(560)), endRadius: 980,
                           options: [.drawsAfterEndLocation])

    let cam = shot(t)
    ctx.saveGState()
    ctx.translateBy(x: CGFloat(W) / 2, y: y(cam.sy))
    ctx.scaleBy(x: cam.zoom, y: cam.zoom)
    ctx.translateBy(x: -cam.fx, y: -y(cam.fy))
    drawScene(ctx, sourceTime(t), film: t)
    ctx.restoreGState()

    // The title at the opening and the close, when the whole frame is in view
    let wideness = t > 31.5 ? 1 - clamp(Double((cam.zoom - 1.02) / 0.25)) : 0
    if wideness > 0.01 {
        text("One key per month", CGPoint(x: phoneX, y: y(92)), serif(40), ink, alpha: wideness)
        text("A SUBSCRIPTION — THE PHONE AND THE GATEWAY, SIDE BY SIDE", CGPoint(x: phoneX, y: y(128)), sans(14, .medium),
             ink3, alpha: wideness, tracking: 3)
    }

    // Captions sit on a band of their own, outside the camera
    for c in captions where t >= c.from && t <= c.to {
        let on = min(fade(t, c.from, 0.35), 1 - fade(t, c.to - 0.4, 0.4))
        let band = CGRect(x: 0, y: 0, width: W, height: 190)
        ctx.saveGState()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: [bgEdge.withAlphaComponent(0.94 * on).cgColor, bgEdge.withAlphaComponent(0).cgColor] as CFArray,
                                  locations: [0.55, 1])!
        ctx.clip(to: band)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: band.maxY), options: [])
        ctx.restoreGState()
        if !c.step.isEmpty {
            text(c.step, CGPoint(x: CGFloat(W) / 2, y: y(1232)), mono(15, .semibold), accent, alpha: on, align: .center, tracking: 2)
        }
        text(c.line, CGPoint(x: CGFloat(W) / 2, y: y(c.step.isEmpty ? 1268 : 1286)),
             serif(c.step.isEmpty ? 40 : 31), ink, alpha: on, align: .center)
    }

    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Encode

let space = CGColorSpaceCreateDeviceRGB()
let info = CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

func render(_ t: Double) -> CGImage {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    ctx.interpolationQuality = .high
    drawFrame(ctx, t)
    return ctx.makeImage()!
}

if let at = value("--png").flatMap(Double.init) {
    try NSBitmapImageRep(cgImage: render(at)).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)"); exit(0)
}

let url = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: url)
let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000,
                                      AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H
])
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
