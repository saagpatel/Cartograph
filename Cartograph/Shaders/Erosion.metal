#include <metal_stdlib>
#include "ShaderTypes.h"
using namespace metal;

// --- RNG ---

static inline uint wang_hash(uint seed) {
    seed = (seed ^ 61u) ^ (seed >> 16u);
    seed *= 9u;
    seed ^= seed >> 4u;
    seed *= 0x27d4eb2du;
    seed ^= seed >> 15u;
    return seed;
}

static inline float hash_to_float(uint h) {
    // Map to [0, 1)
    return float(h & 0x00FFFFFFu) / float(0x01000000u);
}

// --- Height map access ---

static inline float sample_height(device int* map, uint w, uint h, int x, int y) {
    int cx = clamp(x, 0, int(w) - 1);
    int cy = clamp(y, 0, int(h) - 1);
    return float(map[cy * int(w) + cx]) / 65536.0f;
}

static inline float2 compute_gradient(device int* map, uint w, uint h, float px, float py) {
    int x0 = int(px);
    int y0 = int(py);
    int x1 = x0 + 1;
    int y1 = y0 + 1;

    float fx = px - float(x0);
    float fy = py - float(y0);

    float h00 = sample_height(map, w, h, x0, y0);
    float h10 = sample_height(map, w, h, x1, y0);
    float h01 = sample_height(map, w, h, x0, y1);
    float h11 = sample_height(map, w, h, x1, y1);

    // Bilinear gradient
    float dhdx = (h10 - h00) * (1.0f - fy) + (h11 - h01) * fy;
    float dhdy = (h01 - h00) * (1.0f - fx) + (h11 - h10) * fx;

    return float2(dhdx, dhdy);
}

static inline float interpolate_height(device int* map, uint w, uint h, float px, float py) {
    int x0 = int(px);
    int y0 = int(py);
    int x1 = x0 + 1;
    int y1 = y0 + 1;

    float fx = px - float(x0);
    float fy = py - float(y0);

    float h00 = sample_height(map, w, h, x0, y0);
    float h10 = sample_height(map, w, h, x1, y0);
    float h01 = sample_height(map, w, h, x0, y1);
    float h11 = sample_height(map, w, h, x1, y1);

    float top    = mix(h00, h10, fx);
    float bottom = mix(h01, h11, fx);
    return mix(top, bottom, fy);
}

// --- Atomic write ---

static inline void erode_at(device atomic_int* map, uint w, uint h, float px, float py, float amount) {
    int x0 = clamp(int(px),     0, int(w) - 1);
    int y0 = clamp(int(py),     0, int(h) - 1);
    int x1 = clamp(int(px) + 1, 0, int(w) - 1);
    int y1 = clamp(int(py) + 1, 0, int(h) - 1);

    float fx = px - floor(px);
    float fy = py - floor(py);

    // Bilinear weights
    float w00 = (1.0f - fx) * (1.0f - fy);
    float w10 = fx           * (1.0f - fy);
    float w01 = (1.0f - fx) * fy;
    float w11 = fx           * fy;

    int delta = int(amount * 65536.0f);

    atomic_fetch_add_explicit(&map[y0 * int(w) + x0], int(w00 * float(delta)), memory_order_relaxed);
    atomic_fetch_add_explicit(&map[y0 * int(w) + x1], int(w10 * float(delta)), memory_order_relaxed);
    atomic_fetch_add_explicit(&map[y1 * int(w) + x0], int(w01 * float(delta)), memory_order_relaxed);
    atomic_fetch_add_explicit(&map[y1 * int(w) + x1], int(w11 * float(delta)), memory_order_relaxed);
}

// --- Main kernel ---

kernel void erosion_kernel(
    device atomic_int*        heightMap  [[buffer(0)]],
    constant ErosionParams&   params     [[buffer(1)]],
    constant uint&            batchIndex [[buffer(2)]],
    uint                      tid        [[thread_position_in_grid]])
{
    if (tid >= params.particleCount) return;

    uint w = params.mapWidth;
    uint h = params.mapHeight;

    // Seed per particle
    uint rngState = wang_hash(tid + batchIndex * params.particleCount + params.seed);

    // Random start position (keep 1-pixel margin)
    rngState = wang_hash(rngState);
    float px = 1.0f + hash_to_float(rngState) * float(w - 2);
    rngState = wang_hash(rngState);
    float py = 1.0f + hash_to_float(rngState) * float(h - 2);

    float dirX    = 0.0f;
    float dirY    = 0.0f;
    float speed   = 1.0f;
    float water   = 1.0f;
    float sediment = 0.0f;

    device int* readMap = (device int*)heightMap;

    for (int step = 0; step < 30; step++) {
        float oldPx = px;
        float oldPy = py;

        // a. Gradient at current position
        float2 grad = compute_gradient(readMap, w, h, px, py);

        // b. Update direction with inertia
        dirX = dirX * params.inertia - grad.x * (1.0f - params.inertia);
        dirY = dirY * params.inertia - grad.y * (1.0f - params.inertia);

        // c. Normalize direction; fall back to random if near zero
        float len = sqrt(dirX * dirX + dirY * dirY);
        if (len < 1e-6f) {
            rngState = wang_hash(rngState);
            float angle = hash_to_float(rngState) * 2.0f * M_PI_F;
            dirX = cos(angle);
            dirY = sin(angle);
        } else {
            dirX /= len;
            dirY /= len;
        }

        // d. Move one step
        px += dirX;
        py += dirY;

        // e. Kill if out of bounds (1-pixel margin)
        if (px < 1.0f || px > float(w) - 2.0f || py < 1.0f || py > float(h) - 2.0f) {
            break;
        }

        // f. Height difference
        float oldHeight = interpolate_height(readMap, w, h, oldPx, oldPy);
        float newHeight = interpolate_height(readMap, w, h, px, py);
        float heightDiff = newHeight - oldHeight;

        // g. Speed update
        speed = sqrt(max(0.0f, speed * speed + heightDiff));

        // h. Sediment capacity
        float capacity = max(params.minSlope, abs(heightDiff)) * speed * water * params.sedimentCapacity;

        // i. Deposit or erode
        if (sediment > capacity || heightDiff > 0.0f) {
            // Deposit at old position
            float deposit;
            if (heightDiff > 0.0f) {
                deposit = min(sediment, heightDiff);
            } else {
                deposit = (sediment - capacity) * params.depositRate;
            }
            sediment -= deposit;
            erode_at(heightMap, w, h, oldPx, oldPy, deposit);
        } else {
            // j. Erode at old position
            float erodeAmount = min((capacity - sediment) * params.erosionRate, -heightDiff);
            sediment += erodeAmount;
            erode_at(heightMap, w, h, oldPx, oldPy, -erodeAmount);
        }

        // k. Evaporate
        water *= (1.0f - params.evaporationRate);

        // l. Kill if nearly dry
        if (water < 0.001f) {
            break;
        }
    }
}
