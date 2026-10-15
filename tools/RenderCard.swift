// Renders the card material offscreen, from the same CardMaterial.metal the app uses,
// so a shader change can be looked at before it is shipped to a phone.
//
//   swift tools/RenderCard.swift sheet.png                 contact sheet: 2 themes x 3 tilts
//   swift tools/RenderCard.swift one.png -theme graphite -tilt 0.6 0.3 -frost 0
//
// Faithful to the app: bgra8Unorm target, no colour management on the way out,
// the same uniform packing as CardRenderer.apply(_:).

import AppKit
import Metal

let sourcePath = "MetalCard/CardMaterial.metal"
let tileW = 800, tileH = Int(800.0 / 1.586)

func number(_ name: String, _ index: Int, _ fallback: Double) -> Double {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + index < CommandLine.arguments.count,
          let v = Double(CommandLine.arguments[i + index]) else { return fallback }
    return v
}
func text(_ name: String, _ fallback: String) -> String {
    guard let i = CommandLine.arguments.firstIndex(of: name), i + 1 < CommandLine.arguments.count
    else { return fallback }
    return CommandLine.arguments[i + 1]
}

// MARK: - Colours, as the app converts them

func linear(_ hex: UInt32) -> SIMD4<Float> {
    func channel(_ v: UInt32) -> Float {
        let s = Float(v & 0xFF) / 255
        return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }
    return SIMD4(channel(hex >> 16), channel(hex >> 8), channel(hex), 1)
}
func darkened(_ hex: UInt32, _ amount: Float) -> SIMD4<Float> {
    var c = linear(hex)
    // The app blends in sRGB and then linearises; close enough to do it here in sRGB too.
    func srgb(_ v: UInt32) -> Float { Float(v & 0xFF) / 255 }
    let r = srgb(hex >> 16) * (1 - amount), g = srgb(hex >> 8) * (1 - amount), b = srgb(hex) * (1 - amount)
    func lin(_ s: Float) -> Float { s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
    c = SIMD4(lin(r), lin(g), lin(b), 1)
    return c
}
func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> { a + (b - a) * t }

struct ThemeSet { let name: String; let base: UInt32; let canvas: UInt32; let accent: UInt32; let surface: UInt32 }
let themes: [String: ThemeSet] = [
    "lavender": ThemeSet(name: "lavender", base: 0x1E1830, canvas: 0xFFFFFF, accent: 0xC4B9F5, surface: 0xF2F0F7),
    "graphite": ThemeSet(name: "graphite", base: 0x2A2B2F, canvas: 0x111214, accent: 0xD9905E, surface: 0x1E1F22),
    "cobalt":   ThemeSet(name: "cobalt",   base: 0x111A33, canvas: 0xFFFFFF, accent: 0x7B96FF, surface: 0xEFF2F8)
]

// Mirrors CardUniforms in the shader. All float4.
struct CardUniforms {
    var baseColour = SIMD4<Float>(0, 0, 0, 1)
    var sky = SIMD4<Float>(0, 0, 0, 1)
    var bounce = SIMD4<Float>(0, 0, 0, 1)
    var ground = SIMD4<Float>(0, 0, 0, 1)
    var reflectance = SIMD4<Float>(0.045, 0.045, 0.045, 1)
    var params0 = SIMD4<Float>(0, 0, 0, 0)
    var params1 = SIMD4<Float>(0, 0, 0, 0)
    var params2 = SIMD4<Float>(0, 0, 0, 0)
}

func uniforms(theme t: ThemeSet, tilt: SIMD2<Float>, frost: Float, glare: Float = 0) -> CardUniforms {
    var u = CardUniforms()
    u.baseColour = linear(t.base)
    u.sky = linear(t.canvas)
    u.bounce = linear(t.accent)
    u.ground = darkened(t.surface, 0.45)
    let aluminium = SIMD4<Float>(0.91, 0.92, 0.93, 1)
    u.reflectance = mix(aluminium, u.baseColour, 0.30)
    u.params0 = SIMD4(1.0, 0.19, 0.85, tilt.x)
    u.params1 = SIMD4(tilt.y, 1.586, 0.26, glare)
    u.params2 = SIMD4(frost, 0, 0, 0)
    return u
}

// MARK: - Metal

guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
    print("no Metal device"); exit(1)
}
let source = try String(contentsOfFile: sourcePath, encoding: .utf8)
let library: MTLLibrary
do {
    library = try device.makeLibrary(source: source, options: nil)
} catch {
    print("shader failed to compile:\n\(error)"); exit(1)
}
let descriptor = MTLRenderPipelineDescriptor()
descriptor.vertexFunction = library.makeFunction(name: "cardVertex")
descriptor.fragmentFunction = library.makeFunction(name: "cardFragment")
descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

func renderTile(_ u: CardUniforms) -> CGImage {
    var u = u
    let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: tileW, height: tileH, mipmapped: false)
    td.usage = [.renderTarget, .shaderRead]
    td.storageMode = .shared
    let texture = device.makeTexture(descriptor: td)!
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = texture
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].storeAction = .store
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    let buffer = queue.makeCommandBuffer()!
    let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)!
    encoder.setRenderPipelineState(pipeline)
    encoder.setVertexBytes(&u, length: MemoryLayout<CardUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&u, length: MemoryLayout<CardUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 64 * 40 * 6)
    encoder.endEncoding()
    buffer.commit()
    buffer.waitUntilCompleted()

    var bytes = [UInt8](repeating: 0, count: tileW * tileH * 4)
    texture.getBytes(&bytes, bytesPerRow: tileW * 4, from: MTLRegionMake2D(0, 0, tileW, tileH), mipmapLevel: 0)
    let data = CFDataCreate(nil, bytes, bytes.count)!
    let provider = CGDataProvider(data: data)!
    return CGImage(width: tileW, height: tileH, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: tileW * 4,
                   space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func label(_ ctx: CGContext, _ s: String, at p: CGPoint) {
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
    NSAttributedString(string: s, attributes: [
        .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium),
        .foregroundColor: NSColor(white: 0.75, alpha: 1)
    ]).draw(at: p)
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ image: CGImage, to path: String) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

// MARK: - Output

let out = CommandLine.arguments.count > 1 && !CommandLine.arguments[1].hasPrefix("-") ? CommandLine.arguments[1] : "card.png"

if CommandLine.arguments.contains("-theme") {
    let t = themes[text("-theme", "lavender")] ?? themes["lavender"]!
    let tilt = SIMD2<Float>(Float(number("-tilt", 1, 0)), Float(number("-tilt", 2, 0)))
    let frost = Float(number("-frost", 1, 0))
    try writePNG(renderTile(uniforms(theme: t, tilt: tilt, frost: frost)), to: out)
    print("wrote \(out)")
    exit(0)
}

// Contact sheet: rows are themes, columns are tilts, the last column frosted.
let rows = ["lavender", "graphite", "cobalt"]
let columns: [(String, SIMD2<Float>, Float)] = [
    ("tilt -0.7 -0.35", SIMD2(-0.7, -0.35), 0),
    ("flat", SIMD2(0, 0), 0),
    ("tilt 0.7 0.35", SIMD2(0.7, 0.35), 0),
    ("flat · frost 0.7", SIMD2(0, 0), 0.7)
]
let gutter = 28, header = 44
let sheetW = gutter + columns.count * (tileW + gutter)
let sheetH = gutter + rows.count * (tileH + header + gutter)
let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

for (r, name) in rows.enumerated() {
    let t = themes[name]!
    for (c, column) in columns.enumerated() {
        let tile = renderTile(uniforms(theme: t, tilt: column.1, frost: column.2))
        let x = gutter + c * (tileW + gutter)
        let top = gutter + r * (tileH + header + gutter)
        let yy = sheetH - top - header - tileH
        ctx.draw(tile, in: CGRect(x: x, y: yy, width: tileW, height: tileH))
        label(ctx, "\(name) · \(column.0)", at: CGPoint(x: x, y: yy + tileH + 10))
    }
}
try writePNG(ctx.makeImage()!, to: out)
print("wrote \(out)  \(sheetW)x\(sheetH)")
