import XCTest
import simd
@testable import Cartograph

final class StrokeGeometryTests: XCTestCase {

    // MARK: - Helpers

    private func makePoints(count: Int, width: Float = 0.01) -> [StrokeGeometry.PolylinePoint] {
        (0..<count).map { i in
            StrokeGeometry.PolylinePoint(
                position: SIMD2<Float>(Float(i) * 0.1, 0.5),
                width: width,
                noise: 0.0
            )
        }
    }

    // MARK: - Tests

    /// For N input points the quad strip should contain 2N vertices and (N-1)*6 indices.
    func testVertexAndIndexCountForNPoints() {
        let n = 5
        let pts = makePoints(count: n)
        let (vertices, indices) = StrokeGeometry.buildQuadStrip(from: pts)

        XCTAssertEqual(vertices.count, n * 2, "Each input point should produce exactly 2 vertices (left + right)")
        XCTAssertEqual(indices.count, (n - 1) * 6, "Each consecutive quad needs 6 indices (2 triangles)")
    }

    /// Left and right vertices should be offset by exactly ±width from the centreline.
    func testVertexWidthOffsetMatchesInput() {
        let halfW: Float = 0.02
        let pts: [StrokeGeometry.PolylinePoint] = [
            StrokeGeometry.PolylinePoint(position: SIMD2(0.1, 0.5), width: halfW, noise: 0.0),
            StrokeGeometry.PolylinePoint(position: SIMD2(0.9, 0.5), width: halfW, noise: 0.0)
        ]
        let (vertices, _) = StrokeGeometry.buildQuadStrip(from: pts)

        // The line is horizontal → normal is (0, 1).
        // Left vertex: y = 0.5 + halfW, right vertex: y = 0.5 - halfW
        XCTAssertEqual(vertices.count, 4)

        let leftY  = vertices[0].position.y
        let rightY = vertices[1].position.y
        XCTAssertEqual(leftY,  0.5 + halfW, accuracy: 1e-5, "Left vertex should be +width from centreline")
        XCTAssertEqual(rightY, 0.5 - halfW, accuracy: 1e-5, "Right vertex should be -width from centreline")
    }

    /// A single-point input should return empty arrays (cannot form a quad).
    func testSinglePointReturnsEmpty() {
        let pts = makePoints(count: 1)
        let (vertices, indices) = StrokeGeometry.buildQuadStrip(from: pts)
        XCTAssertTrue(vertices.isEmpty, "Single point cannot form a quad strip")
        XCTAssertTrue(indices.isEmpty, "Single point cannot form any indices")
    }

    /// An empty input should return empty arrays without crashing.
    func testEmptyInputReturnsEmpty() {
        let (vertices, indices) = StrokeGeometry.buildQuadStrip(from: [])
        XCTAssertTrue(vertices.isEmpty, "Empty input should produce no vertices")
        XCTAssertTrue(indices.isEmpty, "Empty input should produce no indices")
    }
}
