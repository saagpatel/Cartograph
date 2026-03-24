import XCTest
import simd
@testable import Cartograph

final class MarchingSquaresTests: XCTestCase {

    // MARK: - Helpers

    /// Build a width×height height field filled with `fill`, then paint a cone
    /// whose peak = 1.0 at the centre and falls off linearly to 0.0 at the edges.
    private func makeConeField(width: Int = 32, height: Int = 32) -> [Float] {
        var data = [Float](repeating: 0.0, count: width * height)
        let cx = Float(width) / 2.0
        let cy = Float(height) / 2.0
        let maxDist = min(cx, cy)
        for y in 0..<height {
            for x in 0..<width {
                let d = sqrt(pow(Float(x) - cx, 2) + pow(Float(y) - cy, 2))
                data[y * width + x] = max(0.0, 1.0 - d / maxDist)
            }
        }
        return data
    }

    /// Build a flat field with all values equal to `value`.
    private func makeFlatField(value: Float, width: Int = 32, height: Int = 32) -> [Float] {
        [Float](repeating: value, count: width * height)
    }

    /// Build a field with two separate circular islands above `threshold`.
    private func makeTwoIslandField(width: Int = 64, height: Int = 64, threshold: Float = 0.5) -> [Float] {
        var data = [Float](repeating: 0.0, count: width * height)
        // Island 1: centre at (16, 32)
        let c1 = SIMD2<Float>(16, 32)
        // Island 2: centre at (48, 32)
        let c2 = SIMD2<Float>(48, 32)
        let radius: Float = 8.0
        for y in 0..<height {
            for x in 0..<width {
                let p = SIMD2<Float>(Float(x), Float(y))
                let d1 = simd_distance(p, c1)
                let d2 = simd_distance(p, c2)
                let v1 = max(0.0, 1.0 - d1 / radius)
                let v2 = max(0.0, 1.0 - d2 / radius)
                data[y * width + x] = max(v1, v2)
            }
        }
        return data
    }

    // MARK: - Tests

    /// A cone-shaped field should yield exactly one closed contour polygon.
    func testConeYieldsOnePolygon() {
        let data = makeConeField()
        let polygons = MarchingSquares.extractContours(
            heightData: data, width: 32, height: 32, threshold: 0.5
        )
        XCTAssertEqual(polygons.count, 1, "A single cone should produce exactly one contour polygon")
    }

    /// A completely flat field below the threshold should yield no polygons.
    func testFlatFieldBelowThresholdYieldsNoPolygons() {
        let data = makeFlatField(value: 0.1)
        let polygons = MarchingSquares.extractContours(
            heightData: data, width: 32, height: 32, threshold: 0.5
        )
        XCTAssertTrue(polygons.isEmpty, "A field entirely below the threshold should produce no contours")
    }

    /// A completely flat field above the threshold should yield no polygons
    /// (no crossings at all).
    func testFlatFieldAboveThresholdYieldsNoPolygons() {
        let data = makeFlatField(value: 0.9)
        let polygons = MarchingSquares.extractContours(
            heightData: data, width: 32, height: 32, threshold: 0.5
        )
        XCTAssertTrue(polygons.isEmpty, "A field entirely above the threshold has no crossings → no contours")
    }

    /// Two separated circular islands should produce two distinct polygons.
    func testTwoSeparatedIslandsYieldTwoPolygons() {
        let data = makeTwoIslandField()
        let polygons = MarchingSquares.extractContours(
            heightData: data, width: 64, height: 64, threshold: 0.5
        )
        XCTAssertEqual(polygons.count, 2, "Two separated islands should produce exactly two contour polygons")
    }

    /// Smoothing a closed polygon must return a polygon whose first and last
    /// point are not identical (the caller treats the array as a closed loop
    /// and should not double-count the closing vertex).
    func testSmoothPolygonPreservesClosure() {
        // Simple square in UV space
        let square: [SIMD2<Float>] = [
            SIMD2(0.2, 0.2),
            SIMD2(0.8, 0.2),
            SIMD2(0.8, 0.8),
            SIMD2(0.2, 0.8)
        ]
        let smoothed = MarchingSquares.smoothPolygon(square, tension: 0.5, subdivisions: 4)

        // Should have exactly count × subdivisions points
        XCTAssertEqual(smoothed.count, square.count * 4)

        // First and last should NOT be identical — the loop closes implicitly
        if let first = smoothed.first, let last = smoothed.last {
            XCTAssertNotEqual(first.x, last.x, "First and last smoothed points must differ (no explicit closing vertex)")
        }

        // All points should remain within the convex hull of the input (±some tolerance)
        for p in smoothed {
            XCTAssertGreaterThan(p.x, 0.1, "Smoothed point x should stay near the input polygon")
            XCTAssertLessThan(p.x, 0.9, "Smoothed point x should stay near the input polygon")
            XCTAssertGreaterThan(p.y, 0.1, "Smoothed point y should stay near the input polygon")
            XCTAssertLessThan(p.y, 0.9, "Smoothed point y should stay near the input polygon")
        }
    }
}
