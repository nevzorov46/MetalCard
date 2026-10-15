//
//  CardMaterial.metal
//  MetalCard
//
//  The card surface as a lit material: anisotropic GGX for brushed metal,
//  Fresnel, and an analytic studio environment it reflects.
//

#include <metal_stdlib>
using namespace metal;

struct CardUniforms {
    float4 baseColour;   // rgb
    float4 sky;          // environment above
    float4 bounce;       // coloured fill from the left
    float4 ground;       // environment below
    float4 reflectance;  // f0: what the surface reflects head on
    float4 params0;      // metallic, roughness, anisotropy, tilt.x
    float4 params1;      // tilt.y, aspect, bend, glare
    float4 params2;      // frost, time, unused, unused
};

struct Vertex {
    float4 position [[position]];
    float3 normal;
    float3 tangent;
    float3 world;
    float2 uv;
};

constant uint kGridX = 64;
constant uint kGridY = 40;

// Card bends like a real one held in the hand: a shallow saddle, strongest at the edges.
static float bendHeight(float2 p, float amount) {
    return amount * (p.x * p.x * 0.22 - p.y * p.y * 0.10);
}

vertex Vertex cardVertex(uint vid [[vertex_id]], constant CardUniforms &u [[buffer(0)]]) {
    // Two triangles per cell, built without an index buffer.
    uint quad = vid / 6;
    uint corner = vid % 6;
    uint cx = quad % kGridX;
    uint cy = quad / kGridX;
    const float2 offsets[6] = { float2(0, 0), float2(1, 0), float2(0, 1),
                                float2(1, 0), float2(1, 1), float2(0, 1) };
    float2 g = (float2(cx, cy) + offsets[corner]) / float2(kGridX, kGridY);

    float aspect = u.params1.y;
    float bend = u.params1.z;
    float2 p = g * 2.0 - 1.0;                 // -1...1
    float3 pos = float3(p.x * aspect, p.y, bendHeight(p, bend));

    // Normal and tangent from the analytic surface, so the bend really sweeps the light.
    float dzdx = bend * 0.44 * p.x / max(aspect, 0.001);
    float dzdy = bend * -0.20 * p.y;
    float3 tangent = normalize(float3(1.0, 0.0, dzdx));
    float3 bitangent = normalize(float3(0.0, 1.0, dzdy));

    Vertex out;
    // Orthographic in x and y: the card fills the view exactly, whatever the bend does.
    out.position = float4(p, 0.5, 1.0);
    out.normal = normalize(cross(tangent, bitangent));
    out.tangent = tangent;
    out.world = pos;
    out.uv = float2(g.x, 1.0 - g.y);
    return out;
}

// MARK: - Noise for the brushing

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1)), d = hash21(i + float2(1, 1));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Ridged noise branches along its own creases, which is what makes frost look grown
// rather than sprinkled.
static float ridged(float2 p) {
    float n = 1.0 - abs(valueNoise(p) * 2.0 - 1.0);
    return pow(n, 5.0);
}

static float crystals(float2 p) {
    float v = 0.0, amp = 0.6, weight = 1.0;
    for (int i = 0; i < 4; i++) {
        float n = ridged(p) * weight;
        v += n * amp;
        weight = saturate(n * 3.0);
        p = p * 2.07 + float2(1.7, 9.2);
        amp *= 0.55;
    }
    return v;
}

// MARK: - Environment

// A dark studio with one wide strip light and a thinner second one. The strip is what
// a metal card actually reflects: a shape with an edge that sweeps across the surface
// as you tilt, not a gradient. Roughness softens the edge instead of needing mips.
static float3 environment(float3 d, constant CardUniforms &u, float rough) {
    // Ambient: the room, tinted by the theme, darker towards the floor.
    float3 room = mix(u.ground.rgb, u.sky.rgb, smoothstep(-0.7, 0.7, d.y)) * 0.20;
    room += u.bounce.rgb * smoothstep(0.2, -0.7, d.x) * smoothstep(0.4, -0.4, d.y) * 0.16;

    float soft = 0.018 + rough * 0.10;

    // The window: a narrow strip with a real edge, rounded at the ends, plus a soft
    // halo around it so it reads as a light and not as a cut-out.
    float cy = 0.40, hh = 0.065;
    float band = smoothstep(cy - hh - soft, cy - hh + soft, d.y) * (1.0 - smoothstep(cy + hh - soft, cy + hh + soft, d.y));
    float ends = smoothstep(-0.90, -0.50, d.x) * (1.0 - smoothstep(0.50, 0.90, d.x));
    float halo = exp(-pow((d.y - cy) / 0.22, 2.0)) * exp(-pow(d.x / 0.9, 2.0));
    float3 strip = float3(1.0, 0.985, 0.96) * (band * ends * 1.30 + halo * 0.18);

    // A thin cooler bar lower down, so two highlights slide at different speeds.
    float by = 0.12, bh = 0.022;
    float thin = smoothstep(by - bh - soft, by - bh + soft, d.y) * (1.0 - smoothstep(by + bh - soft, by + bh + soft, d.y));
    float3 bar = mix(float3(0.82, 0.90, 1.0), u.bounce.rgb, 0.30) * thin * ends * 0.55;

    return room + strip + bar;
}

// What a diffuse surface receives: the room without the strips.
static float3 irradiance(float3 d, constant CardUniforms &u) {
    float3 c = mix(u.ground.rgb, u.sky.rgb, smoothstep(-0.45, 0.65, d.y)) * 0.6;
    c += u.bounce.rgb * smoothstep(0.30, -0.50, d.y) * 0.18;
    return c;
}

// MARK: - Anisotropic GGX

static float ggxAniso(float nh, float ht, float hb, float ax, float ay) {
    float a = ht / ax, b = hb / ay;
    float w = a * a + b * b + nh * nh;
    return 1.0 / (M_PI_F * ax * ay * w * w);
}

static float smithAniso(float nv, float vt, float vb, float ax, float ay) {
    float l = length(float3(ax * vt, ay * vb, nv));
    return 2.0 * nv / max(nv + l, 1e-4);
}

static float3 fresnel(float3 f0, float vh) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - vh), 5.0);
}

// MARK: - Output

// Filmic knee, then sRGB. The target is bgra8Unorm, so the encode happens here:
// without it, light writes straight into display values, midtones crush and
// anything over 1.0 clips to flat white.
static float3 tonemap(float3 c) {
    c = max(c, 0.0);
    c = (c * (2.51 * c + 0.03)) / (c * (2.43 * c + 0.59) + 0.14);
    return saturate(c);
}

static float3 encode(float3 c) {
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

fragment half4 cardFragment(Vertex in [[stage_in]], constant CardUniforms &u [[buffer(0)]]) {
    float metallic = u.params0.x;
    float rough = clamp(u.params0.y, 0.035, 1.0);
    float aniso = u.params0.z;
    float2 tilt = float2(u.params0.w, u.params1.x);
    float glare = u.params1.w;

    float3 N = normalize(in.normal);
    float3 T = normalize(in.tangent - N * dot(N, in.tangent));
    float3 B = cross(N, T);

    // Brushing: fine grooves along the long side. Kept below the pixel grid's
    // reach and faded where they would alias, so they live inside the highlight
    // instead of printing scanlines across the whole card.
    float density = 1.0 - saturate(fwidth(in.uv.y) * 220.0);
    float grooves = (valueNoise(float2(in.uv.x * 6.0, in.uv.y * 520.0)) - 0.5)
                  + (valueNoise(float2(in.uv.x * 2.0, in.uv.y * 160.0)) - 0.5) * 0.7;
    grooves *= density;
    float grain = (valueNoise(in.uv * 240.0) - 0.5) * density;
    N = normalize(N + T * grooves * aniso * 0.06 + B * grain * 0.006);
    rough = clamp(rough * (1.0 + grooves * aniso * 0.25), 0.03, 1.0);

    // Tilting the phone moves the viewer, not the card.
    float3 eye = normalize(float3(tilt.x * 1.15, tilt.y * 1.15, 2.4));
    float3 V = normalize(eye * 2.4 - in.world);
    float nv = saturate(dot(N, V));

    float3 albedo = u.baseColour.rgb;
    // Tinted metal keeps its colourway: half the reflectance comes from the base.
    float3 f0 = mix(u.reflectance.rgb, albedo, metallic * 0.35);

    // Key light sits where the strip is and follows the tilt with the environment.
    float3 L = normalize(float3(-0.25 + tilt.x * 0.45, 0.70 - tilt.y * 0.30, 0.60));
    float3 H = normalize(L + V);
    float nl = saturate(dot(N, L));
    float nh = saturate(dot(N, H));
    float vh = saturate(dot(V, H));

    float ax = max(rough * (1.0 + aniso * 0.85), 0.004);
    float ay = max(rough * (1.0 - aniso * 0.75), 0.004);

    float D = ggxAniso(nh, dot(H, T), dot(H, B), ax, ay);
    float G = smithAniso(nv, dot(V, T), dot(V, B), ax, ay) * smithAniso(nl, dot(L, T), dot(L, B), ax, ay);
    float3 F = fresnel(f0, vh);
    float3 direct = D * G * F / max(4.0 * nv * nl, 1e-4) * nl * (0.55 + glare * 0.6);

    // Environment: the mirror lobe, stretched along the brushing so the strip reads as
    // a brushed highlight rather than a chrome one.
    float3 R = reflect(-V, N);
    R = normalize(R + T * grooves * aniso * 0.07);
    float3 specularIBL = environment(R, u, rough) * F;
    float3 up = normalize(N + float3(0.0, 0.75, 0.0));
    float3 diffuseIBL = irradiance(up, u) * albedo * (1.0 - metallic);
    // Metal still shows its own colour where nothing bright is reflected.
    float3 tint = albedo * metallic * 0.35;

    float coatRough = 0.12 + rough * 0.1;
    float coatD = ggxAniso(nh, dot(H, T), dot(H, B), coatRough, coatRough);
    float3 coat = coatD * fresnel(float3(0.04), vh) * nl * (1.0 - metallic) * 0.6;

    float3 colour = diffuseIBL + specularIBL + direct + coat + tint;

    // Thickness: a hairline of light on the edge the card is turned towards, and
    // shadow on the other. The one thing that makes a flat surface read as an object.
    float2 e = min(in.uv, 1.0 - in.uv);
    float edge = min(e.x * 1.586, e.y);
    float lip = 1.0 - smoothstep(0.0, 0.012, edge);
    float2 toward = float2(-tilt.x, tilt.y) * 0.5 + 0.5;          // which edges face the light
    float facing = (in.uv.x < 0.5 ? toward.x : 1.0 - toward.x) * 0.5
                 + (in.uv.y < 0.5 ? toward.y : 1.0 - toward.y) * 0.5;
    colour += lip * (facing * 0.7 - 0.22) * (0.5 + metallic * 0.5);

    // Ice grows in from the edges. The surface stays visible underneath: ice is a
    // skin that scatters light, not paint.
    float frost = u.params2.x;
    if (frost > 0.001) {
        // The front wanders at two scales: slow bays and fingers, then crystals.
        float wander = (valueNoise(in.uv * float2(3.0, 2.0) + 4.0) - 0.5) * 0.14
                     + (valueNoise(in.uv * float2(9.0, 6.0) + 11.0) - 0.5) * 0.05;
        float front = frost * 0.46 + wander * frost;
        float broken = edge - crystals(in.uv * float2(11.0, 7.0)) * 0.07 * frost;
        float ice = 1.0 - smoothstep(front - 0.06, front + 0.015, broken);
        // Thick rime at the rim, thin frost at the front: the white follows thickness.
        float thick = 1.0 - smoothstep(front - 0.30, front, broken);

        float veins = crystals(in.uv * float2(30.0, 19.0));
        float sparkle = pow(valueNoise(in.uv * 260.0), 26.0) * 5.0;

        // The reflection refracts through the crystals, so the strip breaks up under ice.
        float3 Ri = normalize(R + float3(veins - 0.5, crystals(in.uv * float2(17.0, 11.0)) - 0.5, 0.0) * 0.35);
        float3 underIce = environment(Ri, u, min(rough + 0.35, 1.0)) * F;

        float3 cold = float3(0.80, 0.89, 0.97);
        float white = 0.10 + thick * 0.30 + veins * 0.12;
        float3 frosted = colour * (0.60 - thick * 0.25) + underIce * 0.30 + cold * white + sparkle * ice * thick;
        colour = mix(colour, frosted, ice);
    }

    return half4(half3(encode(tonemap(colour))), 1.0h);
}
