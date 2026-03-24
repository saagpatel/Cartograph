#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut heightmap_vertex(const device Vertex* vertices [[buffer(0)]],
                                  uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.texCoord = vertices[vid].texCoord;
    return out;
}

fragment float4 heightmap_fragment(VertexOut in [[stage_in]],
                                   texture2d<float> heightMap [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float h = heightMap.sample(s, in.texCoord).r;
    return float4(h, h, h, 1.0);
}
