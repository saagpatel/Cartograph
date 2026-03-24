import Foundation
import simd

// MARK: - Stroke Geometry

/// Converts polyline paths into GPU-ready quad-strip geometry and applies
/// organic wobble displacement.  `StrokeVertex` is defined in `ShaderTypes.h`
/// and exposed to Swift via the bridging header — do **not** redefine it here.
struct StrokeGeometry {

    // MARK: - Input Type

    /// A single point along a polyline, carrying its own width and a noise seed
    /// value that modulates the per-vertex displacement.
    struct PolylinePoint {
        /// Position in UV space (0–1).
        var position: SIMD2<Float>
        /// Half-width of the stroke at this point (UV units).
        var width: Float
        /// Pre-sampled noise value in [-1, 1] used to vary stroke profile.
        var noise: Float
    }

    // MARK: - Public API

    /// Convert a polyline into a triangle-list quad strip.
    ///
    /// For each interior point, a tangent is computed from the previous and next
    /// neighbours (endpoints use a one-sided tangent).  A normal is extruded
    /// ±`point.width` to produce left and right `StrokeVertex` entries.
    /// Two triangles connect each consecutive quad.
    ///
    /// - Parameter points: At least 2 `PolylinePoint` values.
    /// - Returns: Interleaved vertices + triangle indices, or empty arrays if
    ///   fewer than 2 points are provided.
    static func buildQuadStrip(
        from points: [PolylinePoint]
    ) -> (vertices: [StrokeVertex], indices: [UInt16]) {
        guard points.count >= 2 else { return ([], []) }

        var vertices: [StrokeVertex] = []
        var indices: [UInt16] = []
        vertices.reserveCapacity(points.count * 2)
        indices.reserveCapacity((points.count - 1) * 6)

        for i in 0..<points.count {
            let prev = points[max(i - 1, 0)].position
            let curr = points[i].position
            let next = points[min(i + 1, points.count - 1)].position

            // Tangent: average of forward and backward directions
            let tangent: SIMD2<Float>
            if i == 0 {
                tangent = normalize(next - curr)
            } else if i == points.count - 1 {
                tangent = normalize(curr - prev)
            } else {
                let forward = normalize(next - curr)
                let backward = normalize(curr - prev)
                let avg = forward + backward
                tangent = simd_length(avg) > 1e-6 ? normalize(avg) : forward
            }

            // Normal: 90° CCW rotation of tangent
            let normal = SIMD2<Float>(-tangent.y, tangent.x)

            let halfW = points[i].width
            let distFromCenter = points[i].noise  // repurpose noise as profile modulator

            // Left vertex
            let leftPos = curr + normal * halfW
            vertices.append(StrokeVertex(
                position: leftPos,
                normal: normal,
                width: halfW,
                distFromCenter: -distFromCenter
            ))

            // Right vertex
            let rightPos = curr - normal * halfW
            vertices.append(StrokeVertex(
                position: rightPos,
                normal: -normal,
                width: halfW,
                distFromCenter: distFromCenter
            ))

            // Emit two triangles connecting this quad to the previous one
            if i > 0 {
                let base = UInt16(i - 1) * 2
                //  TL=base+0, TR=base+2, BL=base+1, BR=base+3
                indices.append(contentsOf: [
                    base + 0, base + 2, base + 1,
                    base + 1, base + 2, base + 3
                ])
            }
        }

        return (vertices, indices)
    }

    /// Displace a polyline perpendicular to its local tangent using simplex noise.
    ///
    /// - Parameters:
    ///   - points: Input UV positions.
    ///   - amplitude: Maximum displacement in UV units.
    ///   - seed: Seed for the `NoiseGenerator`.
    /// - Returns: New array of displaced positions.
    static func applyWobble(
        to points: [SIMD2<Float>],
        amplitude: Float,
        seed: UInt64
    ) -> [SIMD2<Float>] {
        guard points.count >= 2 else { return points }

        let noise = NoiseGenerator(seed: seed)
        var result: [SIMD2<Float>] = []
        result.reserveCapacity(points.count)

        for i in 0..<points.count {
            let prev = points[max(i - 1, 0)]
            let curr = points[i]
            let next = points[min(i + 1, points.count - 1)]

            // Tangent and perpendicular normal
            let tangent: SIMD2<Float>
            if i == 0 {
                tangent = normalize(next - curr)
            } else if i == points.count - 1 {
                tangent = normalize(curr - prev)
            } else {
                let avg = normalize(next - curr) + normalize(curr - prev)
                tangent = simd_length(avg) > 1e-6 ? normalize(avg) : normalize(next - curr)
            }
            let normal = SIMD2<Float>(-tangent.y, tangent.x)

            // Sample simplex noise scaled to a frequency that gives interesting detail
            let n = noise.simplex2D(x: curr.x * 200.0, y: curr.y * 200.0)
            result.append(curr + normal * (n * amplitude))
        }

        return result
    }
}
