import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - CartographDocumentData

struct CartographDocumentData: Codable {
    var version: Int = 1
    var seed: UInt64
    var plateCount: Int
    var seaLevel: Float
    var erosionParticleCount: Int
    var erosionRate: Float
    var settlements: [Settlement]
}

// MARK: - CartographDocument

/// Saves and loads .cartograph directory bundles.
/// Bundle:
///   MyWorld.cartograph/
///   ├── metadata.json    — CartographDocumentData
///   ├── heightmap.bin    — raw Float32[width×height]
///   ├── biomes.bin       — raw UInt8[width×height]
///   ├── rivers.json      — [CodableRiverNode]
///   ├── settlements.json — [Settlement]
///   └── preview.png      — 512×512 RGBA thumbnail
struct CartographDocument {

    enum DocumentError: LocalizedError {
        case cannotCreateBundle(URL)
        case missingFile(String)
        case decodingFailed(String, Error)
        case encodingFailed(String, Error)

        var errorDescription: String? {
            switch self {
            case .cannotCreateBundle(let url): return "Cannot create bundle at \(url.path)"
            case .missingFile(let name):       return "Missing required file: \(name)"
            case .decodingFailed(let n, let e): return "Failed to decode \(n): \(e)"
            case .encodingFailed(let n, let e): return "Failed to encode \(n): \(e)"
            }
        }
    }

    // MARK: - Save

    static func save(
        metadata: CartographDocumentData,
        heightData: [Float],
        biomeData: [Biome],
        riverNodes: [RiverNode],
        previewRGBA: [UInt8],      // 512×512 RGBA8
        to url: URL
    ) throws {
        let fm = FileManager.default

        let tempURL = url.deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent + ".tmp-\(UUID().uuidString)")

        try fm.createDirectory(at: tempURL, withIntermediateDirectories: true)

        var writeError: Error?
        defer {
            if writeError != nil { try? fm.removeItem(at: tempURL) }
        }

        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(metadata).write(to: tempURL.appendingPathComponent("metadata.json"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("metadata.json", error)
        }

        do {
            var copy = heightData
            let data = Data(bytes: &copy, count: copy.count * MemoryLayout<Float>.size)
            try data.write(to: tempURL.appendingPathComponent("heightmap.bin"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("heightmap.bin", error)
        }

        do {
            let bytes = biomeData.map { $0.rawValue }
            try Data(bytes).write(to: tempURL.appendingPathComponent("biomes.bin"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("biomes.bin", error)
        }

        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            let codable = riverNodes.map { CodableRiverNode(from: $0) }
            try enc.encode(codable).write(to: tempURL.appendingPathComponent("rivers.json"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("rivers.json", error)
        }

        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted]
            // settlements are already in metadata; write separately for convenience
            try enc.encode(metadata.settlements).write(to: tempURL.appendingPathComponent("settlements.json"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("settlements.json", error)
        }

        do {
            try writePreviewPNG(rgba: previewRGBA, width: 512, height: 512,
                                to: tempURL.appendingPathComponent("preview.png"))
        } catch {
            writeError = error
            throw DocumentError.encodingFailed("preview.png", error)
        }

        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.moveItem(at: tempURL, to: url)
    }

    // MARK: - Load

    struct LoadResult {
        var metadata: CartographDocumentData
        var heightData: [Float]
        var biomeData: [Biome]
        var riverNodes: [RiverNode]
    }

    static func load(from url: URL) throws -> LoadResult {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            throw DocumentError.missingFile(url.path)
        }

        let metadata: CartographDocumentData
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("metadata.json"))
            metadata = try JSONDecoder().decode(CartographDocumentData.self, from: data)
        } catch {
            throw DocumentError.decodingFailed("metadata.json", error)
        }

        let heightData: [Float]
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("heightmap.bin"))
            let floatCount = data.count / MemoryLayout<Float>.size
            heightData = data.withUnsafeBytes {
                Array($0.bindMemory(to: Float.self).prefix(floatCount))
            }
        } catch {
            throw DocumentError.decodingFailed("heightmap.bin", error)
        }

        let biomeData: [Biome]
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("biomes.bin"))
            biomeData = data.map { Biome(rawValue: $0) ?? .deepOcean }
        } catch {
            throw DocumentError.decodingFailed("biomes.bin", error)
        }

        let riverNodes: [RiverNode]
        do {
            let data = try Data(contentsOf: url.appendingPathComponent("rivers.json"))
            let codable = try JSONDecoder().decode([CodableRiverNode].self, from: data)
            riverNodes = codable.map { $0.toRiverNode() }
        } catch {
            throw DocumentError.decodingFailed("rivers.json", error)
        }

        return LoadResult(
            metadata: metadata,
            heightData: heightData,
            biomeData: biomeData,
            riverNodes: riverNodes
        )
    }

    // MARK: - Preview PNG

    private static func writePreviewPNG(rgba: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard rgba.count == width * height * 4 else { return }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let provider = CGDataProvider(data: Data(rgba) as CFData),
            let cgImage = CGImage(
                width: width, height: height,
                bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil,
                shouldInterpolate: false, intent: .defaultIntent
            ),
            let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.png.identifier as CFString, 1, nil
            )
        else { return }
        CGImageDestinationAddImage(dest, cgImage, nil)
        CGImageDestinationFinalize(dest)
    }
}

// MARK: - CodableRiverNode

private struct CodableRiverNode: Codable {
    let id: String
    let posX: Float
    let posY: Float
    let elevation: Float
    let flowAccumulation: Int
    let downstream: String?

    init(from node: RiverNode) {
        id = node.id.uuidString
        posX = node.position.x
        posY = node.position.y
        elevation = node.elevation
        flowAccumulation = node.flowAccumulation
        downstream = node.downstream?.uuidString
    }

    func toRiverNode() -> RiverNode {
        RiverNode(
            id: UUID(uuidString: id) ?? UUID(),
            position: SIMD2(posX, posY),
            elevation: elevation,
            flowAccumulation: flowAccumulation,
            downstream: downstream.flatMap { UUID(uuidString: $0) }
        )
    }
}
