import Metal
import MetalKit
import simd
import CoreGraphics
import ImageIO

// MARK: - ExportEngine
//
// Performs an offscreen 4096×4096 render of the full portolan style pipeline
// and writes the result to a PNG file at the given URL.

struct ExportEngine {

    enum ExportError: Error {
        case metalSetupFailed
        case textureCreationFailed
        case bufferCreationFailed
        case encoderCreationFailed
        case imageCreationFailed
        case fileWriteFailed
    }

    static func export(
        renderer: MapRenderer,
        engine: TerrainEngine,
        to url: URL,
        size: Int = 4096
    ) async throws {
        let device = renderer.device

        guard let library      = device.makeDefaultLibrary(),
              let commandQueue = device.makeCommandQueue() else {
            throw ExportError.metalSetupFailed
        }

        // -----------------------------------------------------------------------
        // Offscreen render target: rgba8Unorm (CPU-readable via .managed)
        // -----------------------------------------------------------------------
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: size,
            height: size,
            mipmapped: false
        )
        desc.usage       = [.renderTarget, .shaderRead]
        desc.storageMode = .managed

        guard let target = device.makeTexture(descriptor: desc) else {
            throw ExportError.textureCreationFailed
        }

        // -----------------------------------------------------------------------
        // Shared quad buffers (resolution-independent UV-space quad)
        // -----------------------------------------------------------------------
        let vertices: [Vertex] = [
            Vertex(position: simd_float2(-1, -1), texCoord: simd_float2(0, 1)),
            Vertex(position: simd_float2( 1, -1), texCoord: simd_float2(1, 1)),
            Vertex(position: simd_float2( 1,  1), texCoord: simd_float2(1, 0)),
            Vertex(position: simd_float2(-1,  1), texCoord: simd_float2(0, 0)),
        ]
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]

        guard let vb = device.makeBuffer(
                  bytes: vertices,
                  length: MemoryLayout<Vertex>.stride * 4,
                  options: .storageModeShared),
              let ib = device.makeBuffer(
                  bytes: indices,
                  length: MemoryLayout<UInt16>.stride * 6,
                  options: .storageModeShared) else {
            throw ExportError.bufferCreationFailed
        }

        // -----------------------------------------------------------------------
        // Prepare all passes
        // -----------------------------------------------------------------------
        var parchment = ParchmentPass()
        var terrain   = TerrainPass()
        var coastline = CoastlinePass()
        var river     = RiverPass()
        var mountain  = MountainPass()
        var label     = LabelPass()
        var decor     = DecorPass()

        parchment.prepare(device: device, library: library, engine: engine,
                          sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        terrain.parchmentTexture = parchment.cachedTexture
        terrain.prepare(device: device, library: library, engine: engine,
                        sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        coastline.prepare(device: device, library: library, engine: engine,
                          sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        river.prepare(device: device, library: library, engine: engine,
                      sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        mountain.prepare(device: device, library: library, engine: engine,
                         sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        label.landmassPolygons = coastline.landmassPolygons
        label.prepare(device: device, library: library, engine: engine,
                      sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)
        decor.prepare(device: device, library: library, engine: engine,
                      sharedQuadVertexBuffer: vb, sharedQuadIndexBuffer: ib)

        // -----------------------------------------------------------------------
        // Render to offscreen target
        // -----------------------------------------------------------------------
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = target
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].storeAction = .store
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let cb  = commandQueue.makeCommandBuffer(),
              let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else {
            throw ExportError.encoderCreationFailed
        }

        var uniforms = Uniforms()
        uniforms.mapSize             = simd_float2(Float(size), Float(size))
        uniforms.seaLevel            = engine.heightMap.seaLevel
        uniforms.modelViewProjection = matrix_identity_float4x4
        uniforms.time                = 0

        parchment.encode(encoder: enc, uniforms: &uniforms)
        terrain.encode(encoder: enc, uniforms: &uniforms)
        coastline.encode(encoder: enc, uniforms: &uniforms)
        river.encode(encoder: enc, uniforms: &uniforms)
        mountain.encode(encoder: enc, uniforms: &uniforms)
        label.encode(encoder: enc, uniforms: &uniforms)
        decor.encode(encoder: enc, uniforms: &uniforms)
        enc.endEncoding()

        // Synchronize managed texture back to CPU
        if let blit = cb.makeBlitCommandEncoder() {
            blit.synchronize(resource: target)
            blit.endEncoding()
        }
        await withCheckedContinuation { continuation in
            cb.addCompletedHandler { _ in
                continuation.resume()
            }
            cb.commit()
        }

        // -----------------------------------------------------------------------
        // Read back pixels → CGImage → PNG
        // -----------------------------------------------------------------------
        let bytesPerRow = size * 4
        var pixelData   = [UInt8](repeating: 0, count: bytesPerRow * size)
        target.getBytes(
            &pixelData,
            bytesPerRow: bytesPerRow,
            from: MTLRegion(
                origin: MTLOrigin(x: 0, y: 0, z: 0),
                size: MTLSize(width: size, height: size, depth: 1)
            ),
            mipmapLevel: 0
        )

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgCtx = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
              let cgImage = cgCtx.makeImage() else {
            throw ExportError.imageCreationFailed
        }

        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ExportError.fileWriteFailed
        }

        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            throw ExportError.fileWriteFailed
        }
    }
}
