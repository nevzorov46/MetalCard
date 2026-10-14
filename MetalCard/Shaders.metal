//
//  Shaders.metal
//  MetalCard
//
//  Stitchable shaders for SwiftUI's .colorEffect / .layerEffect:
//   - holo: holographic foil for the back of the card
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

// Ice has a colour of its own, whatever it covers: deep slate over dark cards,
// steel blue over mid tones, pale blue over light ones.
static half3 iceColour(half lum) {
    half3 deep = half3(0.20h, 0.31h, 0.44h);
    half3 steel = half3(0.52h, 0.65h, 0.78h);
    half3 pale = half3(0.82h, 0.90h, 0.97h);
    return lum < 0.5h ? mix(deep, steel, lum * 2.0h) : mix(steel, pale, lum * 2.0h - 1.0h);
}

// MARK: - Sheen
//
// Composited with .plusLighter, so it only ever adds light.

// glare: 0...1 — how strongly the card is being held. It fades in a broad highlight that
// slides the opposite way to the tilt, like light catching a glossy object as it turns.

// MARK: - Grain
//
// Mid-grey plus noise, for the overlay blend mode: 0.5 leaves the card untouched,
// lighter and darker values etch it.

// MARK: - Hologram
//
// Foil: silver with pale rainbow bands and a fine diffraction grating. The bands slide
// as the card turns, the way they do on a real hologram.

[[ stitchable ]] half4 holo(float2 position, half4 color, float2 size, float2 tilt) {
    float2 uv = position / size;
    // Only part of the spectrum shows at once; turning the card runs through the rest.
    float phase = dot(uv, float2(0.6, 0.4)) * 0.7 + tilt.x * 0.9 + tilt.y * 0.5;
    float3 rainbow = 0.5 + 0.5 * cos(6.28318 * (phase + float3(0.0, 0.33, 0.67)));
    float grating = sin((uv.x * 0.8 + uv.y) * 120.0 + tilt.x * 8.0);
    float shine = exp(-pow((uv.x + uv.y - 1.0 - tilt.x * 0.8) * 2.5, 2.0));
    float3 foil = mix(float3(0.84, 0.85, 0.88), rainbow, 0.4) + grating * 0.05 + shine * 0.15;
    return half4(half3(saturate(foil)), 1.0h) * color.a;
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
    // Starts where the most advanced needle tips sit, so the first crystals show as soon as
    // progress leaves 0, and ends past the highest field value, so 1 covers the whole card.
    float front = progress * 2.5 - 0.72;
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

    // Cold: the ice's own blue-grey takes over, keeping only a trace of the card's hue.
    // It tints the thin veil in the middle too, a little less than the rime at the edges.
    half tint = half(ice * mix(1.0, 0.65, smoothstep(0.05, 1.0, edge)));
    half lum = dot(rgb, half3(0.299h, 0.587h, 0.114h));
    half3 cold = mix(iceColour(lum), rgb, 0.1h);
    rgb = mix(rgb, cold, tint * 0.95h);

    // Milky haze, faintly blue.
    rgb = mix(rgb, half3(0.84h, 0.91h, 0.97h), k * 0.34h);

    // Thick ice is bluer between the crystals, which gives the white feathers depth.
    rgb *= mix(half3(1.0h), half3(0.86h, 0.93h, 1.0h), k * 0.6h);

    // Sugar-fine grain: frost is made of tiny crystals, not a smooth film.
    rgb += half3(half((hash21(floor(position * 2.5)) - 0.5) * 0.10 * thickness));

    // Crystals on top: white, with a cold cast.
    float c = smoothstep(0.12, 0.45, crystals) * thickness;
    rgb = mix(rgb, half3(0.93h, 0.97h, 1.0h), half(c) * 0.85h);

    // The crystals catch the light as the phone tilts.
    float glint = pow(saturate(0.5 + 0.5 * dot(normalize(warp + 0.0001), normalize(tilt + float2(0.0001, -0.3)))), 6.0);
    rgb += half3(half(glint * c * 0.25));

    // A bright rim where new ice is still forming.
    float rim = smoothstep(front - 0.12, front - 0.02, field) * ice;
    rgb = mix(rgb, half3(0.94h, 0.97h, 1.0h), half(rim * 0.55));

    // A few sparkles, only on crystals, twinkling with time and tilt.
    float s = hash21(floor(position * 0.7));
    float twinkle = 0.5 + 0.5 * sin(time * 4.0 + s * 50.0 + tilt.x * 7.0 + tilt.y * 5.0);
    rgb += half3(half(step(0.994, s) * c * twinkle * 1.3));

    rgb = clamp(rgb, 0.0h, 1.0h);
    return half4(rgb * base.a, base.a);
}
