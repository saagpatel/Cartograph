import Foundation
import simd

extension SIMD2 where Scalar == Float {
    /// Distance between two 2D points
    func distance(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }
}

/// Deterministic xorshift64 PRNG — same algorithm used in NoiseGenerator.init
struct Xorshift64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Returns a Float in [0, 1)
    mutating func nextFloat() -> Float {
        Float(next() & 0xFFFFFF) / Float(0x1000000)
    }
}

/// Canonicalized pair of plate indices for boundary tracking
struct IntPair: Hashable {
    let a: Int
    let b: Int

    init(_ p1: Int, _ p2: Int) {
        a = min(p1, p2)
        b = max(p1, p2)
    }
}
