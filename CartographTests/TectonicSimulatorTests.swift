import XCTest
@testable import Cartograph

final class TectonicSimulatorTests: XCTestCase {

    func testDeterminism() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (result1, _) = TectonicSimulator.run(params: params)
        let (result2, _) = TectonicSimulator.run(params: params)
        XCTAssertEqual(result1.data, result2.data, "Same seed should produce identical results")
    }

    func testAllHeightsInRange() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (result, _) = TectonicSimulator.run(params: params)
        for (i, h) in result.data.enumerated() {
            XCTAssertGreaterThanOrEqual(h, 0.0, "Height at \(i) below 0: \(h)")
            XCTAssertLessThanOrEqual(h, 1.0, "Height at \(i) above 1: \(h)")
        }
    }

    func testBaseHeightRanges() {
        // With no mountains and no noise, heights should stay within base ranges
        var params = TectonicParameters(seed: 42, plateCount: 8)
        params.mountainHeight = 0
        params.noiseScale = 0
        let (result, plateIdx) = TectonicSimulator.run(params: params)

        // Build plate lookup
        var rng = Xorshift64(seed: params.seed)
        var isOceanic = [Bool]()
        for _ in 0..<params.plateCount {
            _ = rng.nextFloat(); _ = rng.nextFloat() // skip center
            isOceanic.append(rng.nextFloat() < 0.6)
            _ = rng.nextFloat(); _ = rng.nextFloat() // skip velocity
        }

        for i in 0..<result.data.count {
            let h = result.data[i]
            if isOceanic[plateIdx[i]] {
                XCTAssertGreaterThanOrEqual(h, 0.08, "Oceanic cell \(i) too low: \(h)")
                XCTAssertLessThanOrEqual(h, 0.40, "Oceanic cell \(i) too high: \(h)")
            } else {
                XCTAssertGreaterThanOrEqual(h, 0.30, "Continental cell \(i) too low: \(h)")
                XCTAssertLessThanOrEqual(h, 0.65, "Continental cell \(i) too high: \(h)")
            }
        }
    }

    func testMountainHeightScale0() {
        var params = TectonicParameters(seed: 42, plateCount: 8)
        params.mountainHeight = 0
        params.noiseScale = 0
        let (result, _) = TectonicSimulator.run(params: params)
        let maxHeight = result.data.max() ?? 0
        XCTAssertLessThanOrEqual(maxHeight, 0.60, "No mountains should mean max height near continental max")
    }

    func testMountainHeightScale1() {
        var params = TectonicParameters(seed: 42, plateCount: 8)
        params.mountainHeight = 1.0
        params.noiseScale = 0
        let (result, _) = TectonicSimulator.run(params: params)
        let maxHeight = result.data.max() ?? 0
        XCTAssertGreaterThan(maxHeight, 0.55, "Full mountain height should produce peaks above 0.55")
    }

    func testSeaLevelPropagated() {
        var params = TectonicParameters(seed: 42, plateCount: 8)
        params.seaLevel = 0.40
        let (result, _) = TectonicSimulator.run(params: params)
        XCTAssertEqual(result.seaLevel, 0.40)
    }

    func testAllHeightsPositive() {
        let params = TectonicParameters(seed: 99, plateCount: 12)
        let (result, _) = TectonicSimulator.run(params: params)
        for h in result.data {
            XCTAssertGreaterThanOrEqual(h, 0.0)
            XCTAssertLessThanOrEqual(h, 1.0)
        }
    }

    func testPerformance() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        measure {
            _ = TectonicSimulator.run(params: params)
        }
    }
}
