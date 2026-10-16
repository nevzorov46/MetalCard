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

// A studio in closed form: soft box overhead, coloured bounce from the left, dark floor.
// Roughness widens the box instead of needing a prefiltered mip chain.
static float3 environment(float3 d, constant CardUniforms &u, float rough) {
    float3 c = mix(u.ground.rgb, u.sky.rgb, smoothstep(-0.40, 0.50, d.y));

    float soft = 0.10 + rough * 0.55;
    float box = smoothstep(0.52 - soft, 0.52 + soft, d.y) * smoothstep(-0.45, 0.30, d.z);
    c += (2.3 - rough * 1.1) * box;

    // A second, smaller source to the right keeps the surface from reading as one gradient.
    float spot = smoothstep(0.25, 0.75, d.x) * smoothstep(-0.1, 0.55, d.y);
    c += 0.5 * spot * (1.0 - rough * 0.5);

    float fill = smoothstep(0.35, -0.55, d.y) * smoothstep(-0.25, 0.85, -d.x);
    c += u.bounce.rgb * fill * 0.55;

    // A dim band just under the horizon: the table the card is lying on.
    float table = smoothstep(-0.05, -0.45, d.y) * smoothstep(-0.75, -0.2, d.y);
    c += u.sky.rgb * table * 0.30;
    return c;
}

// What a diffuse surface receives: the room averaged, without the light sources
// themselves, so albedo stays albedo instead of being blown out by the soft box.
static float3 irradiance(float3 d, constant CardUniforms &u) {
    float3 c = mix(u.ground.rgb, u.sky.rgb, smoothstep(-0.45, 0.65, d.y));
    c += u.bounce.rgb * smoothstep(0.30, -0.50, d.y) * 0.22;
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

fragment half4 cardFragment(Vertex in [[stage_in]], constant CardUniforms &u [[buffer(0)]]) {
    float metallic = u.params0.x;
    float rough = clamp(u.params0.y, 0.035, 1.0);   // adjusted by the brushing below
    float aniso = u.params0.z;
    float2 tilt = float2(u.params0.w, u.params1.x);
    float glare = u.params1.w;

    float3 N = normalize(in.normal);
    float3 T = normalize(in.tangent - N * dot(N, in.tangent));
    float3 B = cross(N, T);

    // Brushing runs along the card's long side: grooves are fine across it, long along it.
    float grooves = valueNoise(float2(in.uv.x * 11.0, in.uv.y * 1700.0)) - 0.5;
    grooves += (valueNoise(float2(in.uv.x * 3.0, in.uv.y * 420.0)) - 0.5) * 0.6;
    float grain = valueNoise(in.uv * 520.0) - 0.5;
    N = normalize(N + T * grooves * aniso * 0.20 + B * grain * 0.015);

    // The grooves also vary the polish, which is what makes them readable away from the
    // highlight instead of only inside it.
    rough = clamp(rough * (1.0 + grooves * aniso * 0.55), 0.02, 1.0);

    // Tilting the phone moves the viewer, not the card.
    float3 eye = normalize(float3(tilt.x * 1.15, tilt.y * 1.15, 2.4));
    float3 V = normalize(eye * 2.4 - in.world);
    float nv = saturate(dot(N, V));

    float3 albedo = u.baseColour.rgb;
    float3 f0 = u.reflectance.rgb;

    // Key light sits where the soft box is, and follows the tilt with the environment.
    float3 L = normalize(float3(-0.35 + tilt.x * 0.5, 0.78 - tilt.y * 0.35, 0.52));
    float3 H = normalize(L + V);
    float nl = saturate(dot(N, L));
    float nh = saturate(dot(N, H));
    float vh = saturate(dot(V, H));

    float ax = max(rough * (1.0 + aniso * 0.85), 0.004);
    float ay = max(rough * (1.0 - aniso * 0.75), 0.004);

    float D = ggxAniso(nh, dot(H, T), dot(H, B), ax, ay);
    float G = smithAniso(nv, dot(V, T), dot(V, B), ax, ay) * smithAniso(nl, dot(L, T), dot(L, B), ax, ay);
    float3 F = fresnel(f0, vh);
    float3 direct = D * G * F / max(4.0 * nv * nl, 1e-4) * nl * (1.6 + glare * 1.4);

    // Environment: a mirror lobe for specular, the normal for diffuse.
    float3 R = reflect(-V, N);
    float3 specularIBL = environment(R, u, rough) * F;
    // A surface facing the viewer is lit mostly by what is above it, not by the table,
    // so the irradiance direction leans towards the sky.
    float3 up = normalize(N + float3(0.0, 0.75, 0.0));
    float3 diffuseIBL = irradiance(up, u) * albedo * (1.0 - metallic);

    float coatRough = 0.12 + rough * 0.1;
    float coatD = ggxAniso(nh, dot(H, T), dot(H, B), coatRough, coatRough);
    float3 coat = coatD * fresnel(float3(0.04), vh) * nl * (1.0 - metallic) * 0.9;

    // Edge brightening, the giveaway of a real surface.
    float rim = pow(1.0 - nv, 4.0) * (0.35 + metallic * 0.5);

    float3 colour = diffuseIBL + specularIBL + direct + coat + rim;

    // Ice grows in from the edges: the front is the distance to the nearest one, broken
    // up by crystals so it never reads as a rectangle sliding inwards.
    float frost = u.params2.x;
    if (frost > 0.001) {
        float2 e = min(in.uv, 1.0 - in.uv);
        float edge = min(e.x * 1.586, e.y);
        float front = frost * 0.62;
        float broken = edge - crystals(in.uv * float2(11.0, 7.0)) * 0.085 * frost;
        float ice = 1.0 - smoothstep(front - 0.055, front + 0.015, broken);

        float veins = crystals(in.uv * float2(34.0, 21.0));
        float sparkle = pow(valueNoise(in.uv * 300.0), 22.0) * 7.0;

        float3 cold = float3(0.80, 0.90, 0.98);
        float3 frosted = mix(colour, colour * 0.55 + cold * 0.55, 0.85);
        frosted += veins * 0.14 + sparkle * ice;
        colour = mix(colour, frosted, ice);
    }

    return half4(half3(colour), 1.0h);
}
