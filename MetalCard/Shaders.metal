//
//  Shaders.metal
//  MetalCard
//
//  Two stitchable shaders used by SwiftUI's .colorEffect (iOS 17+):
//   - sheen: brushed-metal specular band + holographic tint that follows device tilt
//   - frost: ice creeping in from the card edges, with crystal veins
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MARK: - Noise helpers

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 5; i++) {
        v += amp * valueNoise(p);
        p *= 2.02;
        amp *= 0.5;
    }
    return v;
}

static half3 spectrum(float h) {
    float3 c = clamp(abs(fmod(h * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
    return half3(c);
}

// MARK: - Sheen
//
// position : pixel position inside the layer
// color    : incoming pixel (premultiplied)
// size     : layer size in points
// tilt     : device tilt, roughly -1...1 on both axes
// time     : seconds, drives the slow holographic drift

[[ stitchable ]] half4 sheen(float2 position, half4 color, float2 size, float2 tilt, float time) {
    float2 uv = position / size;

    // The highlight travels with the tilt of the phone.
    float2 light = float2(0.5, 0.5) + tilt * 0.45;
    float band = dot(normalize(float2(1.0, 0.62)), uv - light);

    // Narrow specular band + a wider soft falloff, so metal reads as metal.
    float specular = exp(-pow(band * 7.0, 2.0)) + 0.25 * exp(-pow(band * 2.2, 2.0));

    // Fine horizontal grain: brushed aluminium.
    float brushed = (fbm(float2(uv.x * 260.0, uv.y * 7.0)) - 0.5) * 0.16;

    // Holographic rainbow, visible only where the band is.
    float hue = fract(band * 1.7 + time * 0.03 + tilt.x * 0.35);
    half3 rainbow = spectrum(hue) * 0.55h;

    half3 rgb = rainbow * half(specular) + half3(half(specular * 0.55 + brushed));
    half alpha = clamp(half(specular * 0.8 + brushed * 0.4), 0.0h, 1.0h) * color.a;

    // SwiftUI expects premultiplied alpha.
    return half4(rgb * alpha, alpha);
}

// MARK: - Frost
//
// progress : 0 = no ice, 1 = fully frozen

[[ stitchable ]] half4 frost(float2 position, half4 color, float2 size, float progress, float time) {
    float2 uv = position / size;

    // 0 at the border, 1 in the middle: the ice grows inwards.
    float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)) * 2.0;

    float crystals = fbm(uv * float2(9.0, 6.0) + time * 0.015);
    float front = progress * 1.4;
    float mask = smoothstep(front, front - 0.14, edge + (crystals - 0.5) * 0.5);

    // Sharp veins inside the frozen area.
    float veins = smoothstep(0.55, 0.92, fbm(uv * 28.0 + crystals * 2.5));
    float sparkle = step(0.997, hash21(floor(position * 0.9) + floor(time * 6.0)));

    half3 ice = mix(half3(0.58h, 0.78h, 0.95h), half3(0.96h, 0.99h, 1.0h), half(veins));
    ice += half3(half(sparkle));

    half alpha = clamp(half(mask * (0.5 + 0.4 * veins) + sparkle * 0.6), 0.0h, 1.0h) * color.a;
    return half4(ice * alpha, alpha);
}
