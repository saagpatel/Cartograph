#include <metal_stdlib>
#include "ShaderTypes.h"
#include "NoiseUtils.h"
using namespace metal;

// Unique output struct — avoids collision with VertexOut in Triangle/HeightMapDebug
struct ParchmentVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// ---------------------------------------------------------------------------
// Vertex
// ---------------------------------------------------------------------------
vertex ParchmentVertexOut parchment_vertex(const device Vertex* vertices [[buffer(0)]],
                                           uint vid [[vertex_id]]) {
    ParchmentVertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment
// Layers applied in order:
//   1. Base parchment colour (warm buff)
//   2. FBM grain
//   3. Edge darkening (vignette-style)
//   4. Age spots
//   5. Fold creases (2 vertical + 1 horizontal)
// ---------------------------------------------------------------------------
fragment float4 parchment_fragment(ParchmentVertexOut in [[stage_in]],
                                   constant ParchmentParams& params [[buffer(0)]]) {
    float2 uv = in.texCoord;  // 0..1

    // --- 1. Base colour ---
    float3 col = float3(params.baseR, params.baseG, params.baseB);

    // --- 2. FBM grain ---
    // Use seed to offset the noise field so different maps look distinct
    float seedOffset = float(params.seed) * 0.003713;
    float grain = fbm_2d(uv * 14.0 + seedOffset);
    // Centered: grain in [-0.5, 0.5], then scaled by amplitude
    col += params.grainAmplitude * 2.0 * (grain - 0.5);

    // --- 3. Edge darkening ---
    // Distance from center in [0,1] (corners → 0.707)
    float2 centered = uv * 2.0 - 1.0;         // [-1,1]
    float edgeDist  = length(centered);         // 0 at centre, ~1.4 at corners
    col -= edgeDist * params.edgeDarken;

    // --- 4. Age spots ---
    // Low-frequency noise; darken where it exceeds threshold
    float spotNoise = fbm_2d(uv * 5.0 + seedOffset + 3.7);
    if (spotNoise > params.spotThreshold) {
        float spotStrength = smoothstep(params.spotThreshold,
                                        params.spotThreshold + 0.12,
                                        spotNoise);
        col *= (1.0 - 0.17 * spotStrength);
    }

    // --- 5. Fold creases ---
    // Slight noise wobble on crease positions for organic feel
    float wobble = fbm_2d(uv * 8.0 + seedOffset + 7.1) * 0.015 - 0.0075;

    // Vertical crease at x ≈ 0.33
    {
        float dx = abs(uv.x - (0.33 + wobble));
        float strength = smoothstep(0.012, 0.0, dx);
        col *= (1.0 - 0.09 * strength);
    }
    // Vertical crease at x ≈ 0.66
    {
        float dx = abs(uv.x - (0.66 + wobble));
        float strength = smoothstep(0.012, 0.0, dx);
        col *= (1.0 - 0.09 * strength);
    }
    // Horizontal crease at y ≈ 0.50
    {
        float dy = abs(uv.y - (0.50 + wobble));
        float strength = smoothstep(0.012, 0.0, dy);
        col *= (1.0 - 0.07 * strength);
    }

    col = saturate(col);
    return float4(col, 1.0);
}
