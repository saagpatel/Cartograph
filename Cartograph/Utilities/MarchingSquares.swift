import Foundation
import simd

// MARK: - Marching Squares

/// Extracts iso-contours from a scalar height field and smooths them with
/// Catmull-Rom splines.  All coordinates are expressed in normalised UV space
/// (0.0–1.0) so they remain resolution-independent.
struct MarchingSquares {

    // MARK: - Public API

    /// Extract closed contour polygons from a height field at the given threshold.
    ///
    /// - Parameters:
    ///   - heightData: Row-major height values, `width × height` elements, values in 0–1.
    ///   - width: Grid width in samples (typically 1024).
    ///   - height: Grid height in samples (typically 1024).
    ///   - threshold: Iso-value (e.g. sea level = 0.35).
    /// - Returns: Array of `LandmassPolygon` with centroid, area, and UV points.
    static func extractContours(
        heightData: [Float],
        width: Int,
        height: Int,
        threshold: Float
    ) -> [LandmassPolygon] {
        // We iterate over (width-1) × (height-1) cells.
        let cellW = width - 1
        let cellH = height - 1

        // Collect raw line segments: each entry is a pair of UV points.
        var segments: [(SIMD2<Float>, SIMD2<Float>)] = []
        segments.reserveCapacity(cellW * cellH / 4)

        for cy in 0..<cellH {
            for cx in 0..<cellW {
                // Sample corners: BL, BR, TR, TL
                let bl = heightData[(cy + 1) * width + cx]
                let br = heightData[(cy + 1) * width + (cx + 1)]
                let tr = heightData[cy       * width + (cx + 1)]
                let tl = heightData[cy       * width + cx]

                let caseIndex: Int =
                    (tl >= threshold ? 8 : 0) |
                    (tr >= threshold ? 4 : 0) |
                    (br >= threshold ? 2 : 0) |
                    (bl >= threshold ? 1 : 0)

                guard caseIndex != 0 && caseIndex != 15 else { continue }

                // Interpolated edge crossing positions (in pixel coords, converted to UV below)
                let fCX = Float(cx)
                let fCY = Float(cy)
                let fW = Float(width)
                let fH = Float(height)

                // Lerp helper: position along edge between corners a and b
                func lerp(_ a: Float, _ b: Float) -> Float {
                    guard abs(b - a) > 1e-6 else { return 0.5 }
                    return (threshold - a) / (b - a)
                }

                // Edge midpoints in pixel space then UV
                // Edge T: top (tl→tr)
                let tEdge = SIMD2<Float>((fCX + lerp(tl, tr)) / fW, fCY / fH)
                // Edge R: right (tr→br)
                let rEdge = SIMD2<Float>((fCX + 1.0) / fW, (fCY + lerp(tr, br)) / fH)
                // Edge B: bottom (bl→br)
                let bEdge = SIMD2<Float>((fCX + lerp(bl, br)) / fW, (fCY + 1.0) / fH)
                // Edge L: left (tl→bl)
                let lEdge = SIMD2<Float>(fCX / fW, (fCY + lerp(tl, bl)) / fH)

                // Saddle-point resolution: sample cell centre
                let centreX = cx + width / 2   // rough centre index for saddle check
                _ = centreX  // suppress unused warning — we use the height map directly
                let centerVal: Float = {
                    // bilinear centre of the 2×2 cell
                    (tl + tr + br + bl) / 4.0
                }()

                switch caseIndex {
                case 1:  segments.append((lEdge, bEdge))
                case 2:  segments.append((bEdge, rEdge))
                case 3:  segments.append((lEdge, rEdge))
                case 4:  segments.append((tEdge, rEdge))
                case 5:
                    // Saddle: case 5 or 10
                    if centerVal >= threshold {
                        segments.append((tEdge, lEdge))
                        segments.append((bEdge, rEdge))
                    } else {
                        segments.append((tEdge, rEdge))
                        segments.append((bEdge, lEdge))
                    }
                case 6:  segments.append((tEdge, bEdge))
                case 7:  segments.append((tEdge, lEdge))
                case 8:  segments.append((tEdge, lEdge))
                case 9:  segments.append((tEdge, bEdge))
                case 10:
                    if centerVal >= threshold {
                        segments.append((tEdge, rEdge))
                        segments.append((bEdge, lEdge))
                    } else {
                        segments.append((tEdge, lEdge))
                        segments.append((bEdge, rEdge))
                    }
                case 11: segments.append((tEdge, rEdge))
                case 12: segments.append((lEdge, rEdge))
                case 13: segments.append((bEdge, rEdge))
                case 14: segments.append((lEdge, bEdge))
                default: break
                }
            }
        }

        guard !segments.isEmpty else { return [] }

        // Chain segments into closed contours
        let contours = chainSegments(segments)

        // Convert to LandmassPolygon, filtering degenerate polygons
        return contours.compactMap { points -> LandmassPolygon? in
            guard points.count >= 3 else { return nil }
            let area = shoelaceArea(points)
            guard area >= 0.0001 else { return nil }
            let centroid = points.reduce(.zero, +) / Float(points.count)
            return LandmassPolygon(points: points, centroid: centroid, area: area)
        }
    }

    /// Smooth a closed polygon with Catmull-Rom interpolation.
    ///
    /// - Parameters:
    ///   - points: Input vertices (treated as a closed loop).
    ///   - tension: 0 = full Catmull-Rom; 1 = all straight lines.
    ///   - subdivisions: Number of samples between each pair of control points.
    /// - Returns: A denser array of smoothed vertices (still a closed loop).
    static func smoothPolygon(
        _ points: [SIMD2<Float>],
        tension: Float = 0.5,
        subdivisions: Int = 4
    ) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }
        let n = points.count
        var result: [SIMD2<Float>] = []
        result.reserveCapacity(n * subdivisions)

        let t = 1.0 - tension  // tangent scale factor

        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]

            for s in 0..<subdivisions {
                let tt = Float(s) / Float(subdivisions)
                let tt2 = tt * tt
                let tt3 = tt2 * tt

                // Catmull-Rom with tension applied to tangent terms.
                // All intermediate values are explicitly typed so the Swift
                // type-checker does not time out on compound SIMD expressions.
                let term0: SIMD2<Float> = p1

                let t1a: SIMD2<Float> = p2 - p0
                let term1: SIMD2<Float> = t1a * (t * tt * 0.5)

                let t2a: SIMD2<Float> = p0 * 2.0
                let t2b: SIMD2<Float> = p1 * 5.0
                let t2c: SIMD2<Float> = p2 * 4.0
                let t2d: SIMD2<Float> = t2a - t2b + t2c - p3
                let term2: SIMD2<Float> = t2d * (tt2 * 0.5)

                let t3a: SIMD2<Float> = p1 - p2
                let t3b: SIMD2<Float> = p3 - p0 + t3a * 3.0
                let term3: SIMD2<Float> = t3b * (tt3 * 0.5)

                let q: SIMD2<Float> = term0 + term1 + term2 + term3
                result.append(q)
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Chain a flat list of unordered line segments into closed contours.
    private static func chainSegments(
        _ segments: [(SIMD2<Float>, SIMD2<Float>)]
    ) -> [[SIMD2<Float>]] {
        // Build adjacency: map endpoint → list of segment indices that have that endpoint
        // We use a spatial hash with a fixed epsilon grid to cluster near-identical points.
        let epsilon: Float = 1.0 / 2048.0  // half a pixel at 1024 resolution

        func key(_ p: SIMD2<Float>) -> String {
            let ix = Int((p.x / epsilon).rounded())
            let iy = Int((p.y / epsilon).rounded())
            return "\(ix),\(iy)"
        }

        var adjacency: [String: [(segIndex: Int, isStart: Bool)]] = [:]
        for (i, seg) in segments.enumerated() {
            let k0 = key(seg.0)
            let k1 = key(seg.1)
            adjacency[k0, default: []].append((i, true))
            adjacency[k1, default: []].append((i, false))
        }

        var used = [Bool](repeating: false, count: segments.count)
        var contours: [[SIMD2<Float>]] = []

        for startIdx in 0..<segments.count {
            guard !used[startIdx] else { continue }

            var chain: [SIMD2<Float>] = []
            var currentIdx = startIdx
            var fromStart = true  // we are extending from the end point

            while !used[currentIdx] {
                used[currentIdx] = true
                let seg = segments[currentIdx]
                let (enterPoint, exitPoint) = fromStart ? (seg.0, seg.1) : (seg.1, seg.0)

                if chain.isEmpty { chain.append(enterPoint) }
                chain.append(exitPoint)

                // Find next unused segment that shares exitPoint
                let nextKey = key(exitPoint)
                guard let candidates = adjacency[nextKey] else { break }

                var foundNext = false
                for candidate in candidates {
                    if !used[candidate.segIndex] {
                        currentIdx = candidate.segIndex
                        let nextSeg = segments[currentIdx]
                        // Determine which end of the next segment is the shared point
                        let d0 = simd_distance(nextSeg.0, exitPoint)
                        fromStart = d0 < epsilon * 2
                        foundNext = true
                        break
                    }
                }
                if !foundNext { break }
            }

            if chain.count >= 3 {
                contours.append(chain)
            }
        }

        return contours
    }

    /// Compute the absolute area of a polygon using the shoelace formula.
    private static func shoelaceArea(_ points: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        return abs(area) / 2.0
    }
}
