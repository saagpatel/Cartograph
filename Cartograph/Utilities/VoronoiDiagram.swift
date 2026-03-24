import Foundation
import simd

struct VoronoiDiagram {

    /// Assigns each cell in a width×height grid to the nearest seed.
    /// Seeds are in UV space (0..1). Returns row-major [Int] of length width*height.
    /// Each value is in 0..<seeds.count.
    static func assign(seeds: [SIMD2<Float>], width: Int, height: Int) -> [Int] {
        let cellCount = width * height
        var result = [Int](repeating: 0, count: cellCount)
        let invW = 1.0 / Float(width)
        let invH = 1.0 / Float(height)

        for y in 0..<height {
            let uy = Float(y) * invH
            let rowOffset = y * width
            for x in 0..<width {
                let ux = Float(x) * invW
                var bestIndex = 0
                var bestDist: Float = .greatestFiniteMagnitude
                for s in 0..<seeds.count {
                    let dx = ux - seeds[s].x
                    let dy = uy - seeds[s].y
                    let d2 = dx * dx + dy * dy
                    if d2 < bestDist {
                        bestDist = d2
                        bestIndex = s
                    }
                }
                result[rowOffset + x] = bestIndex
            }
        }
        return result
    }
}
