import Metal
import MetalKit
import simd

// MARK: - TerrainPass
//
// Composites biome colour, height-based ambient occlusion, and the parchment
// base layer into a single fullscreen terrain image.

struct TerrainPass: RenderPass {

    let label = "TerrainPass"

    private var pipeline: MTLRenderPipelineState?
    private var biomeColorTexture: MTLTexture?
    private var heightTexture: MTLTexture?

    /// Set by the host renderer after ParchmentPass.prepare() completes.
    var parchmentTexture: MTLTexture?

    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer: MTLBuffer?
    private var seaLevel: Float = 0.35

    // MARK: - RenderPass

    mutating func prepare(
        device: MTLDevice,
        library: MTLLibrary,
        engine: TerrainEngine,
        sharedQuadVertexBuffer: MTLBuffer,
        sharedQuadIndexBuffer: MTLBuffer
    ) {
        self.quadVertexBuffer = sharedQuadVertexBuffer
        self.quadIndexBuffer  = sharedQuadIndexBuffer
        self.seaLevel         = engine.heightMap.seaLevel

        // -----------------------------------------------------------------------
        // Pipeline: terrain_color_vertex + terrain_color_fragment, alpha blending
        // -----------------------------------------------------------------------
        guard
            let vert = library.makeFunction(name: "terrain_color_vertex"),
            let frag = library.makeFunction(name: "terrain_color_fragment")
        else {
            print("[TerrainPass] ERROR: could not find terrain shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "TerrainColor"
        pipeDesc.vertexFunction   = vert
        pipeDesc.fragmentFunction = frag

        let ca = pipeDesc.colorAttachments[0]!
        ca.pixelFormat                 = .bgra8Unorm
        ca.isBlendingEnabled           = true
        ca.sourceRGBBlendFactor        = .sourceAlpha
        ca.destinationRGBBlendFactor   = .oneMinusSourceAlpha
        ca.sourceAlphaBlendFactor      = .one
        ca.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipeline = try device.makeRenderPipelineState(descriptor: pipeDesc)
        } catch {
            print("[TerrainPass] ERROR creating pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // Biome colour texture: 1024×1024 RGBA8, one texel per height-map cell
        // -----------------------------------------------------------------------
        let width  = engine.heightMap.width
        let height = engine.heightMap.height
        let count  = width * height

        var biomeRGBA = [UInt8](repeating: 0, count: count * 4)

        if let bm = engine.biomeMap {
            for i in 0..<count {
                let biome = bm.data[i]
                let color = BiomeMap.colorTable[biome] ?? SIMD4<Float>(0, 0, 0, 1)
                biomeRGBA[i * 4]     = UInt8(clamping: Int(color.x * 255))
                biomeRGBA[i * 4 + 1] = UInt8(clamping: Int(color.y * 255))
                biomeRGBA[i * 4 + 2] = UInt8(clamping: Int(color.z * 255))
                biomeRGBA[i * 4 + 3] = UInt8(clamping: Int(color.w * 255))
            }
        } else {
            // Fallback: uniform grey land / blue ocean before biome data is ready
            let sl = engine.heightMap.seaLevel
            for i in 0..<count {
                let h = engine.heightMap.data[i]
                if h < sl {
                    biomeRGBA[i * 4] = 30; biomeRGBA[i * 4 + 1] = 60
                    biomeRGBA[i * 4 + 2] = 120; biomeRGBA[i * 4 + 3] = 255
                } else {
                    let v = UInt8(clamping: Int(h * 200))
                    biomeRGBA[i * 4] = v; biomeRGBA[i * 4 + 1] = v
                    biomeRGBA[i * 4 + 2] = v; biomeRGBA[i * 4 + 3] = 255
                }
            }
        }

        biomeColorTexture = makeRGBA8Texture(device: device, rgba: biomeRGBA, width: width, height: height, label: "BiomeColor")

        // -----------------------------------------------------------------------
        // Height texture: 1024×1024 R32Float
        // -----------------------------------------------------------------------
        let heightDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: width,
            height: height,
            mipmapped: false
        )
        heightDesc.usage       = .shaderRead
        heightDesc.storageMode = .managed

        if let tex = device.makeTexture(descriptor: heightDesc) {
            engine.heightMap.data.withUnsafeBytes { ptr in
                tex.replace(
                    region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                     size: MTLSize(width: width, height: height, depth: 1)),
                    mipmapLevel: 0,
                    withBytes: ptr.baseAddress!,
                    bytesPerRow: width * MemoryLayout<Float>.stride
                )
            }
            heightTexture = tex
        }
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline        = pipeline,
            let biomeTex        = biomeColorTexture,
            let heightTex       = heightTexture,
            let vertexBuffer    = quadVertexBuffer,
            let indexBuffer     = quadIndexBuffer
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)

        // Vertex: shared quad vertices (index 0), uniforms (index 1)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Fragment textures
        encoder.setFragmentTexture(biomeTex,       index: 0)
        encoder.setFragmentTexture(heightTex,      index: 1)
        encoder.setFragmentTexture(parchmentTexture, index: 2)

        var params = TerrainColorParams(
            aoMin: 0.6,
            aoMax: 1.0,
            oceanOpacity: 0.7,
            vignetteStrength: 0.3,
            seaLevel: seaLevel,
            _pad0: 0, _pad1: 0, _pad2: 0
        )
        encoder.setFragmentBytes(&params, length: MemoryLayout<TerrainColorParams>.stride, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.popDebugGroup()
    }

    // MARK: - Helpers

    private func makeRGBA8Texture(
        device: MTLDevice,
        rgba: [UInt8],
        width: Int,
        height: Int,
        label: String
    ) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage       = .shaderRead
        desc.storageMode = .managed

        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.label = label

        rgba.withUnsafeBufferPointer { ptr in
            tex.replace(
                region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                                  size: MTLSize(width: width, height: height, depth: 1)),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        return tex
    }
}
