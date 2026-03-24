import Foundation
import simd

extension SIMD2 where Scalar == Float {
    /// Distance between two 2D points
    func distance(to other: SIMD2<Float>) -> Float {
        simd_distance(self, other)
    }
}
