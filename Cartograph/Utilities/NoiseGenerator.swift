import Foundation
import simd

struct NoiseGenerator {
    private let perm: [Int]        // 512 elements
    private let permMod12: [Int]   // 512 elements

    private static let grad2: [SIMD2<Float>] = [
        SIMD2( 1,  1), SIMD2(-1,  1), SIMD2( 1, -1), SIMD2(-1, -1),
        SIMD2( 1,  0), SIMD2(-1,  0), SIMD2( 0,  1), SIMD2( 0, -1),
        SIMD2( 1,  1), SIMD2(-1,  1), SIMD2( 1, -1), SIMD2(-1, -1)
    ]

    // F2 and G2 skew/unskew constants for 2D simplex
    private static let F2: Float = Float(0.5 * (sqrt(3.0) - 1.0))
    private static let G2: Float = Float((3.0 - sqrt(3.0)) / 6.0)

    init(seed: UInt64) {
        // Build permutation table via Fisher-Yates shuffle with xorshift64 PRNG
        var state = seed == 0 ? 1 : seed  // Avoid zero seed
        var p = Array(0..<256)
        for i in stride(from: 255, through: 1, by: -1) {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let j = Int(state % UInt64(i + 1))
            p.swapAt(i, j)
        }
        // Double the table to avoid index wrapping
        let fullPerm = p + p
        perm = fullPerm
        permMod12 = fullPerm.map { $0 % 12 }
    }

    func simplex2D(x: Float, y: Float) -> Float {
        let s = (x + y) * Self.F2
        let i = Int(floor(x + s))
        let j = Int(floor(y + s))

        let t = Float(i + j) * Self.G2
        let x0 = x - (Float(i) - t)
        let y0 = y - (Float(j) - t)

        // Determine which simplex triangle we're in
        let (i1, j1): (Int, Int) = x0 > y0 ? (1, 0) : (0, 1)

        let x1 = x0 - Float(i1) + Self.G2
        let y1 = y0 - Float(j1) + Self.G2
        let x2 = x0 - 1.0 + 2.0 * Self.G2
        let y2 = y0 - 1.0 + 2.0 * Self.G2

        let ii = i & 255
        let jj = j & 255

        let gi0 = permMod12[ii + perm[jj]]
        let gi1 = permMod12[ii + i1 + perm[jj + j1]]
        let gi2 = permMod12[ii + 1 + perm[jj + 1]]

        // Calculate contributions from each corner
        var n0: Float = 0, n1: Float = 0, n2: Float = 0

        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 >= 0 {
            t0 *= t0
            n0 = t0 * t0 * dot(Self.grad2[gi0], SIMD2(x0, y0))
        }

        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 >= 0 {
            t1 *= t1
            n1 = t1 * t1 * dot(Self.grad2[gi1], SIMD2(x1, y1))
        }

        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 >= 0 {
            t2 *= t2
            n2 = t2 * t2 * dot(Self.grad2[gi2], SIMD2(x2, y2))
        }

        // Scale to [-1, 1]
        return 70.0 * (n0 + n1 + n2)
    }

    func fBm(x: Float, y: Float, octaves: Int = 6, lacunarity: Float = 2.0, gain: Float = 0.5) -> Float {
        var sum: Float = 0
        var amplitude: Float = 1
        var frequency: Float = 1
        var maxAmplitude: Float = 0

        for _ in 0..<octaves {
            sum += simplex2D(x: x * frequency, y: y * frequency) * amplitude
            maxAmplitude += amplitude
            amplitude *= gain
            frequency *= lacunarity
        }

        return sum / maxAmplitude
    }
}
