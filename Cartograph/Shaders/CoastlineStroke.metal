#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Unique output struct
struct StrokeVertexOut {
    float4 position    [[position]];
    float2 texCoord;          // UV of the full quad (for debug if needed)
    float  distFromCenter;    // 0 = centreline, 1 = outer edge
};

// ---------------------------------------------------------------------------
// Vertex
// StrokeVertex.position is in UV space (0..1).
// We convert to clip space: clip = uv * 2 - 1 (Y flipped for Metal).
// The Uniforms MVP is applied on top for camera transforms.
// ---------------------------------------------------------------------------
vertex StrokeVertexOut coastline_vertex(const device StrokeVertex* vertices [[buffer(0)]],
                                        constant Uniforms& uniforms         [[buffer(1)]],
                                        uint vid [[vertex_id]]) {
    StrokeVertex v = vertices[vid];

    // UV → NDC: x in [-1,1], y flipped (UV y=0 is top, Metal NDC y=1 is top)
    float2 clipXY = v.position * 2.0 - 1.0;
    clipXY.y = -clipXY.y;

    float4 worldPos = float4(clipXY, 0.0, 1.0);
    float4 clipPos  = uniforms.modelViewProjection * worldPos;

    StrokeVertexOut out;
    out.position       = clipPos;
    out.texCoord       = v.position;
    out.distFromCenter = v.distFromCenter;   // 0..1 from StrokeGeometry CPU side
    return out;
}

// ---------------------------------------------------------------------------
// Fragment
// Used for both coastlines and rivers.
// Ink density varies from solid at centre to translucent at edge.
// ---------------------------------------------------------------------------
fragment float4 coastline_fragment(StrokeVertexOut in               [[stage_in]],
                                   constant StrokeColorParams& params [[buffer(0)]]) {
    float edgeFade = saturate(in.distFromCenter);

    // Ink density: full at centre, 60% at outer edge
    float density = 1.0 - edgeFade * 0.4;

    // Anti-aliased opacity falloff in the outer 20% of the stroke width
    float alpha = smoothstep(1.0, 0.8, edgeFade);

    float3 ink = params.color.rgb * density;
    return float4(ink, params.color.a * alpha);
}
