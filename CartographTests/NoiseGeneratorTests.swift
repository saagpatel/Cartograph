import XCTest
@testable import Cartograph

final class NoiseGeneratorTests: XCTestCase {

    func testSimplex2DOutputRange() {
        let noise = NoiseGenerator(seed: 42)
        for i in 0..<100 {
            let x = Float(i) * 0.37 + 0.1
            let y = Float(i) * 0.53 + 0.2
            let value = noise.simplex2D(x: x, y: y)
            XCTAssertGreaterThanOrEqual(value, -1.0, "simplex2D out of range at (\(x), \(y)): \(value)")
            XCTAssertLessThanOrEqual(value, 1.0, "simplex2D out of range at (\(x), \(y)): \(value)")
        }
    }

    func testSimplex2DDeterminism() {
        let noise1 = NoiseGenerator(seed: 42)
        let noise2 = NoiseGenerator(seed: 42)
        for i in 0..<20 {
            let x = Float(i) * 0.5
            let y = Float(i) * 0.3
            XCTAssertEqual(noise1.simplex2D(x: x, y: y), noise2.simplex2D(x: x, y: y))
        }
    }

    func testSimplex2DDifferentSeeds() {
        let noise1 = NoiseGenerator(seed: 42)
        let noise2 = NoiseGenerator(seed: 99)
        let v1 = noise1.simplex2D(x: 0.5, y: 0.5)
        let v2 = noise2.simplex2D(x: 0.5, y: 0.5)
        XCTAssertNotEqual(v1, v2, "Different seeds should produce different values")
    }

    func testFBmDifferentPositions() {
        let noise = NoiseGenerator(seed: 42)
        let v1 = noise.fBm(x: 0.0, y: 0.0, octaves: 6, lacunarity: 2.0, gain: 0.5)
        let v2 = noise.fBm(x: 0.1, y: 0.0, octaves: 6, lacunarity: 2.0, gain: 0.5)
        XCTAssertNotEqual(v1, v2, "fBm should vary with position")
    }

    func testFBmOutputRange() {
        let noise = NoiseGenerator(seed: 42)
        for i in 0..<100 {
            let x = Float(i) * 0.37 + 0.1
            let y = Float(i) * 0.53 + 0.2
            let value = noise.fBm(x: x, y: y)
            XCTAssertGreaterThanOrEqual(value, -1.0, "fBm out of range at (\(x), \(y)): \(value)")
            XCTAssertLessThanOrEqual(value, 1.0, "fBm out of range at (\(x), \(y)): \(value)")
        }
    }
}
