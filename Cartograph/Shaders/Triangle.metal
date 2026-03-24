#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(const device Vertex* vertices [[buffer(0)]],
                             uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return float4(1.0, 0.0, 0.0, 1.0);
}
