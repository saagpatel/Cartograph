import XCTest
@testable import Cartograph

final class HeightMapTests: XCTestCase {

    func testInitialDataLength() {
        let hm = HeightMap()
        XCTAssertEqual(hm.data.count, 1_048_576)
    }

    func testSubscriptMatchesRowMajor() {
        var hm = HeightMap()
        hm[10, 20] = 0.75
        XCTAssertEqual(hm.data[20 * 1024 + 10], 0.75)
    }

    func testUVConversionCorners() {
        let hm = HeightMap()
        let origin = hm.uv(x: 0, y: 0)
        XCTAssertEqual(origin.x, 0.0)
        XCTAssertEqual(origin.y, 0.0)

        let farCorner = hm.uv(x: 1023, y: 1023)
        XCTAssertEqual(farCorner.x, 1023.0 / 1024.0, accuracy: 0.0001)
        XCTAssertEqual(farCorner.y, 1023.0 / 1024.0, accuracy: 0.0001)
    }

    func testDefaultSeaLevel() {
        let hm = HeightMap()
        XCTAssertEqual(hm.seaLevel, 0.35)
    }
}
