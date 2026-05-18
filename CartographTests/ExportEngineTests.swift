import CoreGraphics
import ImageIO
import Metal
import simd
import XCTest
@testable import Cartograph

final class ExportEngineTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CartographExportTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    @MainActor
    func testExportWritesReadablePNG() async throws {
        guard MTLCreateSystemDefaultDevice() != nil else {
            throw XCTSkip("Export PNG requires Metal support")
        }

        let renderer = MapRenderer()
        let engine = makePortolanEngine()
        let outputURL = tempDir.appendingPathComponent("portolan-export.png")
        let exportSize = 256

        try await ExportEngine.export(
            renderer: renderer,
            engine: engine,
            to: outputURL,
            size: exportSize
        )

        let data = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(data.count, 8)
        XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        guard let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return XCTFail("Exported file should be a readable PNG")
        }

        XCTAssertEqual(image.width, exportSize)
        XCTAssertEqual(image.height, exportSize)
    }

    private func makePortolanEngine() -> TerrainEngine {
        let engine = TerrainEngine()
        var heightMap = HeightMap()
        var biomeMap = BiomeMap()

        let width = heightMap.width
        let height = heightMap.height
        let seaLevel: Float = 0.35

        for y in 0..<height {
            for x in 0..<width {
                let nx = (Float(x) / Float(width - 1)) * 2 - 1
                let ny = (Float(y) / Float(height - 1)) * 2 - 1
                let radius = sqrt((nx * nx) + (ny * ny))
                let elevation = max(0.08, 0.9 - radius)
                let index = y * width + x

                heightMap.data[index] = elevation
                if elevation < seaLevel {
                    biomeMap.data[index] = .shallowOcean
                } else if elevation > 0.72 {
                    biomeMap.data[index] = .mountain
                } else {
                    biomeMap.data[index] = .grassland
                }
            }
        }

        let downstreamID = UUID(uuidString: "E6BAF6B9-4FD2-4424-83B2-03FC6191A3D5")!

        heightMap.seaLevel = seaLevel
        engine.heightMap = heightMap
        engine.biomeMap = biomeMap
        engine.riverNodes = [
            RiverNode(
                id: UUID(uuidString: "48A18AC2-B460-45EF-A61F-6D4453B06C2B")!,
                position: SIMD2<Float>(0.45, 0.35),
                elevation: 0.62,
                flowAccumulation: 380,
                downstream: downstreamID
            ),
            RiverNode(
                id: downstreamID,
                position: SIMD2<Float>(0.58, 0.63),
                elevation: 0.32,
                flowAccumulation: 640,
                downstream: nil
            )
        ]
        engine.settlements = [
            Settlement(
                id: UUID(uuidString: "825AB3F1-1F6C-482C-A6E3-04A4B357E35F")!,
                name: "Port Auryn",
                position: SIMD2<Float>(0.56, 0.62),
                type: .port,
                placementScore: 0.86
            )
        ]
        engine.debugMode = .portolan

        return engine
    }
}
