#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// Unique output struct
struct MountainVertexOut {
    float4 position [[position]];
    float2 localUV;   // local quad UV [0,1] — used for the triangular profile
};

// ---------------------------------------------------------------------------
// Vertex  (instanced)
// Each instance represents one mountain glyph on the portolan chart.
// A unit quad [-0.5, 0.5]² in local space is passed in via a Vertex buffer
// whose position field is re-interpreted as local offsets.
// ---------------------------------------------------------------------------
vertex MountainVertexOut mountain_vertex(const device Vertex*           vertices  [[buffer(0)]],
                                          const device MountainInstance* instances [[buffer(1)]],
                                          constant Uniforms&             uniforms  [[buffer(2)]],
                                          uint vid [[vertex_id]],
                                          uint iid [[instance_id]]) {
    MountainInstance inst = instances[iid];

    // Unit quad vertex in local [-0.5,0.5] space
    float2 local = vertices[vid].position;   // position field carries local offset

    // Rotate
    float cosR = cos(inst.rotation);
    float sinR = sin(inst.rotation);
    float2 rotated = float2(cosR * local.x - sinR * local.y,
                            sinR * local.x + cosR * local.y);

    // Scale
    float2 scaled = rotated * inst.size;

    // Translate to instance centre (UV space)
    float2 worldUV = inst.center + scaled;

    // UV → NDC (flip Y)
    float2 clipXY  = worldUV * 2.0 - 1.0;
    clipXY.y       = -clipXY.y;

    float4 clipPos = uniforms.modelViewProjection * float4(clipXY, 0.0, 1.0);

    // LocalUV for fragment: remap local [-0.5,0.5] → [0,1]
    float2 quadUV = local + 0.5;

    MountainVertexOut out;
    out.position = clipPos;
    out.localUV  = quadUV;
    return out;
}

// ---------------------------------------------------------------------------
// Fragment
// Triangular glyph profile:
//   - Peak at (0.5, 0.95)
//   - Base spans x ∈ [0.15, 0.85] at y = 0
//   - Left face: lighter (paper)
//   - Right face: right-side shadow (darker)
//   - Discard pixels outside triangle
// ---------------------------------------------------------------------------
fragment float4 mountain_fragment(MountainVertexOut in [[stage_in]]) {
    float2 uv = in.localUV;  // [0,1]

    // Apex and base extents
    const float apexX  = 0.5;
    const float apexY  = 0.95;
    const float baseL  = 0.15;
    const float baseR  = 0.85;
    const float baseY  = 0.0;

    // Interpolate left and right edges of triangle at this fragment's Y
    // Y=0 → base, Y=apexY → apex
    float tY = uv.y / apexY;
    tY = saturate(tY);

    float leftEdge  = mix(baseL, apexX, tY);
    float rightEdge = mix(baseR, apexX, tY);

    // Discard if outside triangle footprint or above apex
    if (uv.x < leftEdge || uv.x > rightEdge || uv.y > apexY) {
        discard_fragment();
    }

    // Dark brown ink base
    float3 inkColor = float3(0.18, 0.12, 0.08);

    // Right-side shadow: right half of triangle is 37% darker
    float span     = rightEdge - leftEdge;
    float tX       = (span > 0.0001) ? ((uv.x - leftEdge) / span) : 0.5;
    float shadow   = (tX > 0.5) ? 0.55 : 0.85;   // right darker, left lighter
    float3 col     = inkColor * shadow;

    // Anti-aliased fade near base (bottom 15% of quad height)
    float baseAlpha = smoothstep(0.0, 0.15, uv.y);

    return float4(col, baseAlpha);
}
