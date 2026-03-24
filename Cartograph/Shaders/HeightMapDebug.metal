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

fragment float4 plate_debug_fragment(VertexOut in [[stage_in]],
                                      texture2d<float> plateMap [[texture(0)]]) {
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    float idx = plateMap.sample(s, in.texCoord).r;

    // HSV to RGB with evenly spaced hues
    float hue = idx * 6.0;
    float c = 0.8;
    float x = c * (1.0 - abs(fmod(hue, 2.0) - 1.0));
    float3 rgb;
    if      (hue < 1.0) rgb = float3(c, x, 0);
    else if (hue < 2.0) rgb = float3(x, c, 0);
    else if (hue < 3.0) rgb = float3(0, c, x);
    else if (hue < 4.0) rgb = float3(0, x, c);
    else if (hue < 5.0) rgb = float3(x, 0, c);
    else                 rgb = float3(c, 0, x);

    return float4(rgb + 0.2, 1.0);
}

fragment float4 debug_rgba_fragment(VertexOut in [[stage_in]],
                                     texture2d<float> colorMap [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return colorMap.sample(s, in.texCoord);
}
