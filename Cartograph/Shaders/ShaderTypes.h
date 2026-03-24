#ifndef ShaderTypes_h
#define ShaderTypes_h
#include <simd/simd.h>

typedef struct {
    simd_float2 position;   // clip space -1..1
    simd_float2 texCoord;   // UV 0..1
} Vertex;

typedef struct {
    simd_float4x4 modelViewProjection;
    simd_float2 mapSize;    // width, height in pixels
    float time;             // reserved for future animation
    float seaLevel;         // normalized 0..1, default 0.35
} Uniforms;

typedef struct {
    simd_float2 position;   // UV space 0..1
    float elevation;
    float flowAccumulation; // normalized 0..1
} RiverVertex;

typedef struct {
    simd_float2 center;     // UV space — mountain ridge peak
    float size;             // world-space size multiplier
    float rotation;         // radians, along ridge direction
} MountainInstance;

typedef struct {
    uint32_t mapWidth;      // always 1024
    uint32_t mapHeight;     // always 1024
    uint32_t particleCount; // default 500000
    float inertia;          // 0.05
    float sedimentCapacity; // 4.0
    float minSlope;         // 0.01
    float erosionRate;      // 0.3
    float depositRate;      // 0.3
    float evaporationRate;  // 0.01
    uint32_t seed;
} ErosionParams;

#endif
