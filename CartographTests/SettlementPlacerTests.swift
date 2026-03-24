import XCTest
import simd
@testable import Cartograph

final class SettlementPlacerTests: XCTestCase {

    // 32×32 synthetic heightmap: land island in the center, ocean around edges
    private func makeTestHeightmap(size: Int = 32, seaLevel: Float = 0.35) -> (heights: [Float], biomes: [Biome]) {
        let count = size * size
        var heights = [Float](repeating: 0.2, count: count)  // ocean
        var biomes = [Biome](repeating: .deepOcean, count: count)

        let center = size / 2
        for y in 0..<size {
            for x in 0..<size {
                let dx = Float(x - center) / Float(size)
                let dy = Float(y - center) / Float(size)
                let dist = sqrt(dx * dx + dy * dy)
                let h = max(0.1, 0.7 - dist * 3.0)
                heights[y * size + x] = h
                if h >= seaLevel {
                    biomes[y * size + x] = h > seaLevel + 0.2 ? .mountain : .grassland
                } else if h >= seaLevel - 0.05 {
                    biomes[y * size + x] = .shallowOcean
                }
            }
        }
        return (heights, biomes)
    }

    func testPlacementProducesAtLeastThreeSettlements() {
        let (heights, biomes) = makeTestHeightmap(size: 64, seaLevel: 0.35)
        let result = SettlementPlacer.place(
            heightData: heights,
            biomeData: biomes,
            riverNodes: [],
            width: 64,
            height: 64,
            seaLevel: 0.35,
            plateCount: 8,
            seed: 42
        )
        XCTAssertGreaterThanOrEqual(result.count, 3, "Expected at least 3 settlements for plateCount=8")
    }

    func testNoTwoSettlementsWithin0_05() {
        let (heights, biomes) = makeTestHeightmap(size: 128, seaLevel: 0.35)
        let result = SettlementPlacer.place(
            heightData: heights,
            biomeData: biomes,
            riverNodes: [],
            width: 128,
            height: 128,
            seaLevel: 0.35,
            plateCount: 6,
            seed: 99
        )
        for i in 0..<result.count {
            for j in (i+1)..<result.count {
                let dist = simd_distance(result[i].position, result[j].position)
                XCTAssertGreaterThan(dist, 0.04, "Settlements \(i) and \(j) are too close: \(dist)")
            }
        }
    }

    func testDeterminism() {
        let (heights, biomes) = makeTestHeightmap(size: 64, seaLevel: 0.35)
        let result1 = SettlementPlacer.place(
            heightData: heights, biomeData: biomes, riverNodes: [],
            width: 64, height: 64, seaLevel: 0.35, plateCount: 5, seed: 42
        )
        let result2 = SettlementPlacer.place(
            heightData: heights, biomeData: biomes, riverNodes: [],
            width: 64, height: 64, seaLevel: 0.35, plateCount: 5, seed: 42
        )
        XCTAssertEqual(result1.count, result2.count)
        for i in 0..<result1.count {
            XCTAssertEqual(result1[i].position.x, result2[i].position.x, accuracy: 1e-6)
            XCTAssertEqual(result1[i].position.y, result2[i].position.y, accuracy: 1e-6)
            XCTAssertEqual(result1[i].type, result2[i].type)
        }
    }

    func testAllSettlementsAreOnLand() {
        let seaLevel: Float = 0.35
        let (heights, biomes) = makeTestHeightmap(size: 64, seaLevel: seaLevel)
        let result = SettlementPlacer.place(
            heightData: heights, biomeData: biomes, riverNodes: [],
            width: 64, height: 64, seaLevel: seaLevel, plateCount: 4, seed: 7
        )
        for s in result {
            let x = Int(s.position.x * 64)
            let y = Int(s.position.y * 64)
            let clampedX = max(0, min(63, x))
            let clampedY = max(0, min(63, y))
            let h = heights[clampedY * 64 + clampedX]
            XCTAssertGreaterThanOrEqual(h, seaLevel, "Settlement at \(s.position) is in ocean (h=\(h))")
        }
    }
}
