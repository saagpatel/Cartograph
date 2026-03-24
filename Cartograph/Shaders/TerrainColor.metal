#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Unique output struct
struct TerrainVertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// ---------------------------------------------------------------------------
// Vertex
// ---------------------------------------------------------------------------
vertex TerrainVertexOut terrain_color_vertex(const device Vertex* vertices [[buffer(0)]],
                                              constant Uniforms& uniforms  [[buffer(1)]],
                                              uint vid [[vertex_id]]) {
    TerrainVertexOut out;
    float4 pos = float4(vertices[vid].position, 0.0, 1.0);
    out.position = uniforms.modelViewProjection * pos;
    out.texCoord = vertices[vid].texCoord;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment
// Inputs:
//   texture(0) — biomeColorTex  : RGBA colour keyed by biome
//   texture(1) — heightTex      : R = normalised elevation
//   texture(2) — parchmentTex   : RGB parchment layer
// ---------------------------------------------------------------------------
fragment float4 terrain_color_fragment(TerrainVertexOut in              [[stage_in]],
                                       texture2d<float> biomeColorTex   [[texture(0)]],
                                       texture2d<float> heightTex       [[texture(1)]],
                                       texture2d<float> parchmentTex    [[texture(2)]],
                                       constant TerrainColorParams& p   [[buffer(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float2 uv = in.texCoord;

    float  height    = heightTex.sample(s, uv).r;
    float4 biomeCol  = biomeColorTex.sample(s, uv);
    float3 parchment = parchmentTex.sample(s, uv).rgb;

    // -----------------------------------------------------------------------
    // 8-neighbour ambient occlusion
    // Sample height in a 3×3 kernel; darker where surrounded by higher terrain
    // -----------------------------------------------------------------------
    float texelW = 1.0 / 1024.0;
    float texelH = 1.0 / 1024.0;
    float aoSum  = 0.0;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            float2 offset  = float2(float(dx) * texelW, float(dy) * texelH);
            float  neighbH = heightTex.sample(s, uv + offset).r;
            aoSum += saturate(neighbH - height);
        }
    }
    // aoSum in [0,8]; normalise to [0,1]
    float aoRaw    = aoSum / 8.0;
    float aoFactor = mix(p.aoMax, p.aoMin, aoRaw);   // bright at aoMax, dark at aoMin

    // -----------------------------------------------------------------------
    // Ocean cells — blend parchment with a cool tint at oceanOpacity
    // -----------------------------------------------------------------------
    bool  isOcean    = (height < p.seaLevel);
    float3 oceanTint = float3(0.55, 0.68, 0.78);     // pale portolan sea blue
    float3 oceanCol  = mix(parchment, oceanTint, p.oceanOpacity);

    float3 landCol   = biomeCol.rgb * aoFactor;
    float3 baseCol   = isOcean ? oceanCol : landCol;

    // -----------------------------------------------------------------------
    // Vignette — darken towards corners
    // -----------------------------------------------------------------------
    float2 centered      = uv * 2.0 - 1.0;
    float  vignetteDist  = length(centered);
    float  vignette      = saturate(1.0 - vignetteDist * p.vignetteStrength);
    baseCol *= vignette;

    return float4(saturate(baseCol), 1.0);
}
