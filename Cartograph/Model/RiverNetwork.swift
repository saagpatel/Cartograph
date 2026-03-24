import Foundation
import simd

struct RiverNode: Identifiable {
    let id: UUID
    var position: SIMD2<Float>
    var elevation: Float
    var flowAccumulation: Int
    var downstream: UUID?
}
