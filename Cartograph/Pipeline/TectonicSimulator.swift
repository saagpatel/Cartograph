import Foundation
import simd

struct TectonicPlate: Identifiable {
    let id: UUID
    var center: SIMD2<Float>
    var velocity: SIMD2<Float>
    var isOceanic: Bool
    var cells: [SIMD2<Int>]
}

struct PlateBoundary {
    enum BoundaryType {
        case convergent, divergent, transform
    }

    var type: BoundaryType
    var plates: (UUID, UUID)
    var points: [SIMD2<Float>]
}
