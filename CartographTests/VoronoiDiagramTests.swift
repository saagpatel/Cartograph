import XCTest
@testable import Cartograph

final class VoronoiDiagramTests: XCTestCase {

    func testSingleSeedAllZero() {
        let seeds: [SIMD2<Float>] = [SIMD2(0.5, 0.5)]
        let result = VoronoiDiagram.assign(seeds: seeds, width: 64, height: 64)
        XCTAssertTrue(result.allSatisfy { $0 == 0 })
    }

    func testTwoSeedsPartition() {
        let seeds: [SIMD2<Float>] = [SIMD2(0.25, 0.5), SIMD2(0.75, 0.5)]
        let result = VoronoiDiagram.assign(seeds: seeds, width: 64, height: 64)
        // Left quarter should be 0, right quarter should be 1
        for y in 0..<64 {
            XCTAssertEqual(result[y * 64 + 0], 0, "Far left should be seed 0")
            XCTAssertEqual(result[y * 64 + 63], 1, "Far right should be seed 1")
        }
    }

    func testCellAtSeedPosition() {
        let seeds: [SIMD2<Float>] = [
            SIMD2(0.2, 0.3),
            SIMD2(0.7, 0.8),
            SIMD2(0.5, 0.1)
        ]
        let width = 1024, height = 1024
        let result = VoronoiDiagram.assign(seeds: seeds, width: width, height: height)
        for (i, seed) in seeds.enumerated() {
            let x = Int(seed.x * Float(width))
            let y = Int(seed.y * Float(height))
            let clampedX = min(x, width - 1)
            let clampedY = min(y, height - 1)
            XCTAssertEqual(result[clampedY * width + clampedX], i,
                           "Cell at seed \(i) position should map to index \(i)")
        }
    }

    func testAllIndicesValid() {
        var rng = Xorshift64(seed: 123)
        var seeds = [SIMD2<Float>]()
        for _ in 0..<10 {
            seeds.append(SIMD2(rng.nextFloat(), rng.nextFloat()))
        }
        let result = VoronoiDiagram.assign(seeds: seeds, width: 128, height: 128)
        for idx in result {
            XCTAssertGreaterThanOrEqual(idx, 0)
            XCTAssertLessThan(idx, 10)
        }
    }
}
