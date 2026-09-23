//
//  Shaders.metal
//  MetalCard
//
//  Stitchable shaders for SwiftUI's .colorEffect / .layerEffect:
//   - sheen: a soft specular band that follows the phone's tilt
//   - grain: print grain for matte cards, brushed hairlines for metal
//   - frost: ice growing in from the edges; it refracts, blurs and cools the card under it
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// MARK: - Noise

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

static float fbm(float2 p, int octaves) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < octaves; i++) {
        v += amp * valueNoise(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return v;
}

// Ridged noise: thin, sharp creases where plain noise crosses the middle. They read as ice.
static float ridged(float2 p) {
    float n = 1.0 - abs(valueNoise(p) * 2.0 - 1.0);
    return pow(n, 5.0);
}

// Each octave is weighted by the one before it, so fine detail grows along existing
// creases — that is what makes the pattern branch like frost instead of looking like static.
static float ridgedFbm(float2 p, int octaves) {
    float v = 0.0;
    float amp = 0.6;
    float weight = 1.0;
    for (int i = 0; i < octaves; i++) {
        float n = ridged(p) * weight;
        v += n * amp;
        weight = saturate(n * 3.0);
        p = p * 2.07 + float2(1.7, 9.2);
        amp *= 0.55;
    }
    return v;
}

// Straight crystal needles running along `dir`: ridged noise, squeezed across the needle
// and stretched along it.
static float needles(float2 q, float2 dir, float across, float along, float2 seed, int octaves) {
    float2 perp = float2(-dir.y, dir.x);
    return ridgedFbm(float2(dot(q, perp) * across, dot(q, dir) * along) + seed, octaves);
}

// A trunk along d0 with barbs at ±60°, like the arms of an ice crystal. That branching
// is what turns streaks into frost.
static float frostFern(float2 q, float2 d0) {
    float2 d1 = float2(d0.x * 0.5 - d0.y * 0.866, d0.x * 0.866 + d0.y * 0.5);
    float2 d2 = float2(d0.x * 0.5 + d0.y * 0.866, -d0.x * 0.866 + d0.y * 0.5);
    float trunk = needles(q, d0, 16.0, 2.0, float2(0.0, 0.0), 4);
    float barbA = needles(q, d1, 28.0, 4.5, float2(13.1, 7.7), 3);
    float barbB = needles(q, d2, 28.0, 4.5, float2(3.3, 21.9), 3);
    return max(trunk, max(barbA, barbB) * 0.8);
}

// MARK: - Sheen
//
// Composited with .plusLighter, so it only ever adds light.

// glare: 0...1 — how strongly the card is being held. It fades in a broad highlight that
// slides the opposite way to the tilt, like light catching a glossy object as it turns.

[[ stitchable ]] half4 sheen(float2 position, half4 color, float2 size, float2 tilt,
                             float strength, float glare) {
    float2 uv = position / size;

    // At rest the light grazes the top-left corner; tilting sweeps it across the card.
    float2 light = float2(0.22, 0.18) + tilt * float2(0.7, 0.6);
    float band = dot(normalize(float2(1.0, 0.8)), uv - light);

    // A wide soft falloff plus a narrower core.
    float spec = 0.6 * exp(-pow(band * 3.2, 2.0)) + 0.4 * exp(-pow(band * 10.0, 2.0));

    // Measured in card heights on both axes, so the glare is round rather than stretched.
    float2 centre = float2(0.5, 0.5) - tilt * float2(0.55, 0.45);
    float2 d = (uv - centre) * float2(size.x / size.y, 1.0);
    float spot = exp(-dot(d, d) * 3.5) * glare;

    half a = half(clamp(spec * strength + spot * 0.22, 0.0, 1.0));
    return half4(a, a, a, a) * color.a;
}

// MARK: - Grain
//
// Mid-grey plus noise, for the overlay blend mode: 0.5 leaves the card untouched,
// lighter and darker values etch it.

[[ stitchable ]] half4 grain(float2 position, half4 color, float amount, float brushed) {
    float fine = hash21(floor(position * 3.0)) - 0.5;
    float hairline = fbm(float2(position.x * 0.02, position.y * 1.6), 4) - 0.5;
    float n = mix(fine, hairline * 1.6, brushed) * amount;
    half g = half(0.5 + n);
    return half4(g, g, g, 1.0h) * color.a;
}

// MARK: - Frost
//
// progress: 0 = no ice, 1 = fully frozen. tilt drives the glints on the crystal facets.

[[ stitchable ]] half4 frost(float2 position, SwiftUI::Layer layer, float2 size,
                             float progress, float time, float2 tilt) {
    half4 base = layer.sample(position);
    if (progress <= 0.0 || base.a <= 0.0h) {
        return base;
    }

    // Aspect-correct units: one unit is half the card's height.
    float unit = min(size.x, size.y) * 0.5;
    float2 p = position / unit;

    // Distance to the nearest side edge, to the nearest top/bottom edge, and to either:
    // 0 at the border, 1 on the centre line.
    float dx = min(position.x, size.x - position.x) / unit;
    float dy = min(position.y, size.y - position.y) / unit;
    float edge = min(dx, dy);

    // Lobes and feathers break the front, so it grows like frost on a window
    // rather than a rectangle sliding in.
    float lobes = fbm(p * 1.6 + 3.1, 4) - 0.5;
    float feathers = fbm(p * 7.0 + 11.0, 3) - 0.5;
    float field = edge + lobes * 0.9 + feathers * 0.22;

    // Crystals shoot out ahead of the frozen area, so the front is spiky, not a clean cut.
    // Pixels beyond their reach can skip the expensive part.
    const float reach = 0.25;
    // Starts just short of the lowest field value (edge, lobes and needle reach combined),
    // so progress 0 means no ice at all, and ends past the highest.
    float front = progress * 2.6 - 0.85;
    if (field > front + reach) {
        return base;
    }

    // Ferns grow across the nearest edge: horizontally from the sides, vertically from
    // the top and bottom. Only the orientation that is needed gets computed.
    float2 warp = (float2(fbm(p * 2.2, 3), fbm(p * 2.2 + 5.2, 3)) - 0.5) * 0.18;
    float2 q = p + warp;
    float nearSide = smoothstep(-0.12, 0.12, dy - dx);          // 1 near the left/right edges
    float ferns = 0.0;
    if (nearSide > 0.01) { ferns += frostFern(q, float2(1.0, 0.0)) * nearSide; }
    if (nearSide < 0.99) { ferns += frostFern(q + 31.7, float2(0.0, 1.0)) * (1.0 - nearSide); }

    // Denser in some places than others, and sparser towards the middle.
    float density = 0.45 + 0.9 * smoothstep(0.35, 0.7, fbm(p * 1.3 + 8.4, 3));
    float crystals = ferns * density * mix(1.0, 0.45, smoothstep(0.25, 0.9, edge));

    float ice = 1.0 - smoothstep(front - 0.12, front, field - saturate(crystals) * reach);   // 1 = frozen
    if (ice <= 0.001) {
        return base;
    }

    // Thick rime at the edges, a thin veil in the middle, so the card still shows through.
    float thickness = ice * mix(1.0, 0.4, smoothstep(0.05, 1.0, edge));

    // Refract and blur what is under the ice. Summing premultiplied samples and dividing
    // by their alpha gives an alpha-weighted average, so the transparent corners don't bleed in.
    float2 s0 = position + warp * 10.0 * thickness;
    float r = 2.8 * thickness;
    half4 sum = layer.sample(s0)
              + layer.sample(s0 + float2( r, 0.0))
              + layer.sample(s0 + float2(-r, 0.0))
              + layer.sample(s0 + float2(0.0,  r))
              + layer.sample(s0 + float2(0.0, -r))
              + layer.sample(s0 + float2( r,  r) * 0.7)
              + layer.sample(s0 + float2(-r, -r) * 0.7)
              + layer.sample(s0 + float2( r, -r) * 0.7)
              + layer.sample(s0 + float2(-r,  r) * 0.7);
    half3 under = sum.a > 0.001h ? sum.rgb / sum.a : half3(0.0h);
    half3 straight = base.rgb / base.a;

    half k = half(thickness);
    half3 rgb = mix(straight, under, k);

    // Cold: drain most of the colour and push it towards blue-white.
    half lum = dot(rgb, half3(0.299h, 0.587h, 0.114h));
    half3 cold = mix(half3(lum), rgb, 0.3h) * half3(0.88h, 0.95h, 1.0h) + half3(0.05h, 0.07h, 0.09h);
    rgb = mix(rgb, cold, k * 0.85h);

    // Milky haze.
    rgb = mix(rgb, half3(0.94h, 0.97h, 1.0h), k * 0.38h);

    // Sugar-fine grain: frost is made of tiny crystals, not a smooth film.
    rgb += half3(half((hash21(floor(position * 2.5)) - 0.5) * 0.10 * thickness));

    // White crystals on top.
    float c = smoothstep(0.12, 0.45, crystals) * thickness;
    rgb = mix(rgb, half3(0.98h, 0.99h, 1.0h), half(c) * 0.85h);

    // The crystals catch the light as the phone tilts.
    float glint = pow(saturate(0.5 + 0.5 * dot(normalize(warp + 0.0001), normalize(tilt + float2(0.0001, -0.3)))), 6.0);
    rgb += half3(half(glint * c * 0.25));

    // A bright rim where new ice is still forming.
    float rim = smoothstep(front - 0.12, front - 0.02, field) * ice;
    rgb = mix(rgb, half3(1.0h), half(rim * 0.55));

    // A few sparkles, only on crystals, twinkling with time and tilt.
    float s = hash21(floor(position * 0.7));
    float twinkle = 0.5 + 0.5 * sin(time * 4.0 + s * 50.0 + tilt.x * 7.0 + tilt.y * 5.0);
    rgb += half3(half(step(0.994, s) * c * twinkle * 1.3));

    rgb = clamp(rgb, 0.0h, 1.0h);
    return half4(rgb * base.a, base.a);
}
