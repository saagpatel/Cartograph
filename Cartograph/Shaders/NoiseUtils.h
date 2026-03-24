#ifndef NoiseUtils_h
#define NoiseUtils_h

#include <metal_stdlib>
using namespace metal;

// ---------------------------------------------------------------------------
// hash21 — pseudo-random float in [0,1) from a 2-D integer seed
// ---------------------------------------------------------------------------
inline float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ---------------------------------------------------------------------------
// value_noise_2d — smooth value noise, returns [0,1)
// ---------------------------------------------------------------------------
inline float value_noise_2d(float2 uv) {
    float2 i = floor(uv);
    float2 f = fract(uv);

    // Smoothstep C2 curve
    float2 u = f * f * (3.0 - 2.0 * f);

    float a = hash21(i + float2(0.0, 0.0));
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ---------------------------------------------------------------------------
// fbm_2d — fractal Brownian motion, 5 octaves, returns [0,1) approximately
// ---------------------------------------------------------------------------
inline float fbm_2d(float2 uv) {
    float value     = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;

    for (int i = 0; i < 5; i++) {
        value     += amplitude * value_noise_2d(uv * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    // Accumulated range is roughly [0, amplitude_sum] = [0, ~0.97]
    // Remap to [0,1]
    return saturate(value / 0.97);
}

#endif /* NoiseUtils_h */
