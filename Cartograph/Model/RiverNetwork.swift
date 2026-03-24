import Foundation
import simd

struct RiverNode: Identifiable {
    let id: UUID
    var position: SIMD2<Float>
    var elevation: Float
    var flowAccumulation: Int
    var downstream: UUID?

    init(id: UUID = UUID(), position: SIMD2<Float>, elevation: Float, flowAccumulation: Int, downstream: UUID?) {
        self.id = id
        self.position = position
        self.elevation = elevation
        self.flowAccumulation = flowAccumulation
        self.downstream = downstream
    }
}
