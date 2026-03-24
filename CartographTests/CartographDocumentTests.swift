import XCTest
@testable import Cartograph

final class CartographDocumentTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartographDocTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSaveAndLoadRoundTrip() throws {
        let settlement = Settlement(
            id: UUID(),
            name: "Port Auryn",
            position: .init(0.4, 0.6),
            type: .port,
            placementScore: 0.85
        )
        let metadata = CartographDocumentData(
            version: 1,
            seed: 12345,
            plateCount: 8,
            seaLevel: 0.35,
            erosionParticleCount: 500_000,
            erosionRate: 0.3,
            settlements: [settlement]
        )

        let width = 16, height = 16, count = width * height
        let heightData = (0..<count).map { Float($0) / Float(count) }
        let biomeData = [Biome](repeating: .grassland, count: count)
        let riverNodes: [RiverNode] = []
        let preview = [UInt8](repeating: 128, count: 512 * 512 * 4)

        let bundleURL = tempDir.appendingPathComponent("TestWorld.cartograph")

        try CartographDocument.save(
            metadata: metadata,
            heightData: heightData,
            biomeData: biomeData,
            riverNodes: riverNodes,
            previewRGBA: preview,
            to: bundleURL
        )

        // Verify bundle exists with all 6 files
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("metadata.json").path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("heightmap.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("biomes.bin").path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("rivers.json").path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("settlements.json").path))
        XCTAssertTrue(fm.fileExists(atPath: bundleURL.appendingPathComponent("preview.png").path))

        let result = try CartographDocument.load(from: bundleURL)
        XCTAssertEqual(result.metadata.seed, 12345)
        XCTAssertEqual(result.metadata.plateCount, 8)
        XCTAssertEqual(result.metadata.seaLevel, 0.35, accuracy: 1e-6)
        XCTAssertEqual(result.heightData.count, count)
        XCTAssertEqual(result.biomeData.count, count)
        XCTAssertEqual(result.metadata.settlements.count, 1)
        XCTAssertEqual(result.metadata.settlements[0].name, "Port Auryn")
        XCTAssertEqual(result.heightData[7], heightData[7], accuracy: 1e-6)
        XCTAssertEqual(result.biomeData[0], .grassland)
    }

    func testMissingFileThrows() {
        let missing = tempDir.appendingPathComponent("DoesNotExist.cartograph")
        XCTAssertThrowsError(try CartographDocument.load(from: missing))
    }

    func testSettlementsRoundTrip() throws {
        let s1 = Settlement(id: UUID(), name: "Ironhold", position: .init(0.3, 0.7), type: .fortress, placementScore: 0.9)
        let s2 = Settlement(id: UUID(), name: "Riverton", position: .init(0.6, 0.4), type: .city, placementScore: 0.75)
        let metadata = CartographDocumentData(
            seed: 99, plateCount: 4, seaLevel: 0.4,
            erosionParticleCount: 100_000, erosionRate: 0.2,
            settlements: [s1, s2]
        )
        let bundleURL = tempDir.appendingPathComponent("Settlements.cartograph")

        try CartographDocument.save(
            metadata: metadata,
            heightData: [Float](repeating: 0.5, count: 16),
            biomeData: [Biome](repeating: .grassland, count: 16),
            riverNodes: [],
            previewRGBA: [UInt8](repeating: 0, count: 512 * 512 * 4),
            to: bundleURL
        )

        let result = try CartographDocument.load(from: bundleURL)
        XCTAssertEqual(result.metadata.settlements.count, 2)
        XCTAssertEqual(result.metadata.settlements[0].name, "Ironhold")
        XCTAssertEqual(result.metadata.settlements[1].name, "Riverton")
        XCTAssertEqual(result.metadata.settlements[0].position.x, 0.3, accuracy: 1e-5)
        XCTAssertEqual(result.metadata.settlements[1].type, .city)
    }
}
