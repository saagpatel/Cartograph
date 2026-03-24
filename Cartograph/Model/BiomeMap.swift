import Foundation
import simd

enum Biome: UInt8 {
    case deepOcean = 0, shallowOcean = 1, beach = 2
    case desert = 3, savanna = 4, tropicalRainforest = 5
    case grassland = 6, temperateForest = 7, borealForest = 8
    case tundra = 9, glacier = 10, mountain = 11, volcano = 12
}

struct BiomeMap {
    let width = 1024
    let height = 1024
    var data: [Biome]

    init() {
        data = [Biome](repeating: .deepOcean, count: 1024 * 1024)
    }

    static let colorTable: [Biome: SIMD4<Float>] = [
        .deepOcean:          SIMD4(0.08, 0.18, 0.32, 1.0),
        .shallowOcean:       SIMD4(0.15, 0.28, 0.48, 1.0),
        .beach:              SIMD4(0.76, 0.70, 0.50, 1.0),
        .desert:             SIMD4(0.82, 0.72, 0.45, 1.0),
        .savanna:            SIMD4(0.68, 0.65, 0.35, 1.0),
        .tropicalRainforest: SIMD4(0.12, 0.38, 0.15, 1.0),
        .grassland:          SIMD4(0.55, 0.68, 0.38, 1.0),
        .temperateForest:    SIMD4(0.25, 0.48, 0.22, 1.0),
        .borealForest:       SIMD4(0.20, 0.35, 0.25, 1.0),
        .tundra:             SIMD4(0.60, 0.62, 0.55, 1.0),
        .glacier:            SIMD4(0.88, 0.92, 0.95, 1.0),
        .mountain:           SIMD4(0.55, 0.50, 0.45, 1.0),
        .volcano:            SIMD4(0.35, 0.15, 0.10, 1.0),
    ]
}
