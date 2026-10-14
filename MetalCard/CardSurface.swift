import MetalKit
import SwiftUI

/// The card's material, rendered by Metal and sized to the card.
/// SwiftUI keeps the layout, the printing and the rounded corners; this is only the surface.
struct CardSurface: UIViewRepresentable {
    var finish: Card.Finish
    var base: Color
    var environment: EnvironmentColours
    var tilt: CGSize
    var glare: CGFloat
    var frost: Double

    /// What the card reflects. Taken from the theme, so each theme changes the room.
    struct EnvironmentColours: Equatable {
        var sky: Color
        var bounce: Color
        var ground: Color
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = false
        view.layer.isOpaque = false
        view.enableSetNeedsDisplay = true
        view.isPaused = true          // redrawn when the tilt changes, not on a clock
        view.delegate = context.coordinator
        context.coordinator.apply(self)
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.apply(self)
        view.setNeedsDisplay()
    }

    func makeCoordinator() -> CardRenderer { CardRenderer() }
}

@MainActor
final class CardRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var uniforms = CardUniforms()

    /// 64 x 40 cells, two triangles each, built in the vertex shader without buffers.
    private static let vertexCount = 64 * 40 * 6

    override init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        super.init()
        buildPipeline()
    }

    private func buildPipeline() {
        guard let device, let library = device.makeDefaultLibrary() else { return }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cardVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cardFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func apply(_ surface: CardSurface) {
        let metal = surface.finish == .metal
        uniforms.baseColour = surface.base.linearComponents
        uniforms.sky = surface.environment.sky.linearComponents
        uniforms.bounce = surface.environment.bounce.linearComponents
        uniforms.ground = surface.environment.ground.linearComponents
        // Brushed aluminium reflects almost everything; a metal card tinted by the theme
        // keeps a hint of its colourway without turning into a black mirror.
        let aluminium = SIMD4<Float>(0.91, 0.92, 0.93, 1)
        uniforms.reflectance = metal ? mix(aluminium, uniforms.baseColour, 0.30)
                                     : SIMD4(0.045, 0.045, 0.045, 1)
        uniforms.params0 = SIMD4(metal ? 1.0 : 0.0,
                                 metal ? 0.19 : 0.55,
                                 metal ? 0.85 : 0.20,
                                 Float(surface.tilt.width))
        uniforms.params1 = SIMD4(Float(surface.tilt.height),
                                 Float(CardView.aspect),
                                 metal ? 0.26 : 0.18,
                                 Float(surface.glare))
        uniforms.params2 = SIMD4(Float(surface.frost), 0, 0, 0)
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated { render(view) }
    }

    private func render(_ view: MTKView) {
        guard let pipeline, let queue,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<CardUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CardUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: Self.vertexCount)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

/// Mirrors `CardUniforms` in CardMaterial.metal. All float4, so there is no padding to get wrong.
private struct CardUniforms {
    var baseColour = SIMD4<Float>(0, 0, 0, 1)
    var sky = SIMD4<Float>(0, 0, 0, 1)
    var bounce = SIMD4<Float>(0, 0, 0, 1)
    var ground = SIMD4<Float>(0, 0, 0, 1)
    var reflectance = SIMD4<Float>(0.045, 0.045, 0.045, 1)
    var params0 = SIMD4<Float>(0, 0, 0, 0)
    var params1 = SIMD4<Float>(0, 0, 0, 0)
    var params2 = SIMD4<Float>(0, 0, 0, 0)
}

extension Color {
    /// Toward black. The card lies on a table, and a table is darker than the sky.
    func darkened(_ amount: Double) -> Color {
        Color(UIColor { _ in UIColor(self).withAlphaComponent(1).blended(with: .black, amount: amount) })
    }
}

private extension UIColor {
    func blended(with other: UIColor, amount: Double) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: 1)
    }
}

private func mix(_ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) -> SIMD4<Float> {
    a + (b - a) * t
}

extension Color {
    /// sRGB to linear, because the shader does its arithmetic in light, not in display values.
    var linearComponents: SIMD4<Float> {
        let rgba = UIColor(self).cgColor.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                   intent: .defaultIntent, options: nil)
        let c = rgba?.components ?? [0, 0, 0, 1]
        func linear(_ v: CGFloat) -> Float {
            let s = Float(max(0, min(1, v)))
            return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        guard c.count >= 3 else { return SIMD4(0, 0, 0, 1) }
        return SIMD4(linear(c[0]), linear(c[1]), linear(c[2]), 1)
    }
}
