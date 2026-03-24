import XCTest
@testable import Cartograph

final class ClimateModelTests: XCTestCase {

    // MARK: - Unit tests for assignBiome

    func testDeepOcean() {
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.2, moisture: 0.5, seaLevel: 0.35)
        XCTAssertEqual(biome, .deepOcean)
    }

    func testShallowOcean() {
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.30, moisture: 0.5, seaLevel: 0.35)
        XCTAssertEqual(biome, .shallowOcean)
    }

    func testBeach() {
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.36, moisture: 0.5, seaLevel: 0.35)
        XCTAssertEqual(biome, .beach)
    }

    func testTropicalRainforest() {
        // Near equator (lat=0.5), high moisture
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.5, moisture: 0.6, seaLevel: 0.35)
        XCTAssertEqual(biome, .tropicalRainforest)
    }

    func testDesert() {
        // Near equator, low moisture
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.5, moisture: 0.3, seaLevel: 0.35)
        XCTAssertEqual(biome, .desert)
    }

    func testTemperateForest() {
        // Mid latitude (~0.3 or 0.7), high moisture
        let biome = ClimateModel.assignBiome(latitude: 0.35, elevation: 0.5, moisture: 0.5, seaLevel: 0.35)
        XCTAssertEqual(biome, .temperateForest)
    }

    func testTundra() {
        // Near pole, some moisture
        let biome = ClimateModel.assignBiome(latitude: 0.1, elevation: 0.5, moisture: 0.4, seaLevel: 0.35)
        XCTAssertEqual(biome, .tundra)
    }

    func testGlacierHighElevation() {
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.90, moisture: 0.5, seaLevel: 0.35)
        XCTAssertEqual(biome, .glacier)
    }

    func testMountainHighElevationDry() {
        let biome = ClimateModel.assignBiome(latitude: 0.5, elevation: 0.90, moisture: 0.3, seaLevel: 0.35)
        XCTAssertEqual(biome, .mountain)
    }

    // MARK: - Integration tests

    func testOceanCellsGetOceanBiomes() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (heightMap, _) = TectonicSimulator.run(params: params)
        let (biomeMap, _) = ClimateModel.generate(
            heightData: heightMap.data, width: 1024, height: 1024,
            seaLevel: heightMap.seaLevel, riverNodes: []
        )
        for i in 0..<biomeMap.data.count {
            if heightMap.data[i] < heightMap.seaLevel {
                let biome = biomeMap.data[i]
                XCTAssertTrue(
                    biome == .deepOcean || biome == .shallowOcean,
                    "Cell \(i) below sea level should be ocean, got \(biome)"
                )
            }
        }
    }

    func testDeterminism() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (heightMap, _) = TectonicSimulator.run(params: params)
        let (biome1, moisture1) = ClimateModel.generate(
            heightData: heightMap.data, width: 1024, height: 1024,
            seaLevel: heightMap.seaLevel, riverNodes: []
        )
        let (biome2, moisture2) = ClimateModel.generate(
            heightData: heightMap.data, width: 1024, height: 1024,
            seaLevel: heightMap.seaLevel, riverNodes: []
        )
        XCTAssertEqual(biome1.data, biome2.data)
        XCTAssertEqual(moisture1, moisture2)
    }

    func testMoistureRange() {
        let params = TectonicParameters(seed: 42, plateCount: 8)
        let (heightMap, _) = TectonicSimulator.run(params: params)
        let (_, moisture) = ClimateModel.generate(
            heightData: heightMap.data, width: 1024, height: 1024,
            seaLevel: heightMap.seaLevel, riverNodes: []
        )
        for (i, m) in moisture.enumerated() {
            XCTAssertGreaterThanOrEqual(m, 0.0, "Moisture at \(i) below 0: \(m)")
            XCTAssertLessThanOrEqual(m, 1.0, "Moisture at \(i) above 1: \(m)")
        }
    }
}
