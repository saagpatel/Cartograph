import Metal
import MetalKit
import simd

// MARK: - ParchmentPass
//
// Renders a procedural parchment texture into an offscreen 1024×1024 cache,
// then composites that cache onto the framebuffer as an opaque base layer.

struct ParchmentPass: RenderPass {

    let label = "ParchmentPass"

    // Pipeline for the offscreen parchment generation (parchment_vertex + parchment_fragment)
    private var generatePipeline: MTLRenderPipelineState?
    // Pipeline for drawing the cached texture to the screen (heightmap_vertex + debug_rgba_fragment)
    private var displayPipeline: MTLRenderPipelineState?

    // The offscreen render target — exposed so TerrainPass can read it.
    private(set) var cachedTexture: MTLTexture?

    // Stored references to the shared quad buffers (set during prepare)
    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer: MTLBuffer?

    // Tectonic seed captured during prepare, used to vary the parchment per world.
    private var parchmentSeed: UInt32 = 42

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
        self.parchmentSeed    = UInt32(engine.heightMap.seaLevel * 1000) &+ 7

        // -----------------------------------------------------------------------
        // 1. Offscreen generation pipeline: parchment_vertex + parchment_fragment
        // -----------------------------------------------------------------------
        guard
            let parchVert = library.makeFunction(name: "parchment_vertex"),
            let parchFrag = library.makeFunction(name: "parchment_fragment")
        else {
            print("[ParchmentPass] ERROR: could not find parchment shader functions")
            return
        }

        let genDesc = MTLRenderPipelineDescriptor()
        genDesc.label                                = "ParchmentGenerate"
        genDesc.vertexFunction                       = parchVert
        genDesc.fragmentFunction                     = parchFrag
        // Offscreen target uses rgba8Unorm — we'll upload to the cache manually.
        genDesc.colorAttachments[0].pixelFormat      = .rgba8Unorm
        // No blending: this is a fully-opaque procedural texture.
        genDesc.colorAttachments[0].isBlendingEnabled = false

        do {
            generatePipeline = try device.makeRenderPipelineState(descriptor: genDesc)
        } catch {
            print("[ParchmentPass] ERROR creating generate pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // 2. Display pipeline: heightmap_vertex + debug_rgba_fragment (existing)
        // -----------------------------------------------------------------------
        guard
            let dispVert = library.makeFunction(name: "heightmap_vertex"),
            let dispFrag = library.makeFunction(name: "debug_rgba_fragment")
        else {
            print("[ParchmentPass] ERROR: could not find display shader functions")
            return
        }

        let dispDesc = MTLRenderPipelineDescriptor()
        dispDesc.label                               = "ParchmentDisplay"
        dispDesc.vertexFunction                      = dispVert
        dispDesc.fragmentFunction                    = dispFrag
        dispDesc.colorAttachments[0].pixelFormat     = .bgra8Unorm
        dispDesc.colorAttachments[0].isBlendingEnabled = false

        do {
            displayPipeline = try device.makeRenderPipelineState(descriptor: dispDesc)
        } catch {
            print("[ParchmentPass] ERROR creating display pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // 3. Create offscreen render-target texture (rgba8Unorm, 1024×1024)
        // -----------------------------------------------------------------------
        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1024,
            height: 1024,
            mipmapped: false
        )
        texDesc.usage        = [.renderTarget, .shaderRead]
        texDesc.storageMode  = .private  // GPU-only; fastest

        guard let renderTarget = device.makeTexture(descriptor: texDesc) else {
            print("[ParchmentPass] ERROR: could not create offscreen texture")
            return
        }
        cachedTexture = renderTarget

        // -----------------------------------------------------------------------
        // 4. Render parchment into the offscreen texture using a one-shot command buffer.
        // -----------------------------------------------------------------------
        guard let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("[ParchmentPass] ERROR: could not create command queue/buffer for bake")
            return
        }

        let rpDesc = MTLRenderPassDescriptor()
        rpDesc.colorAttachments[0].texture     = renderTarget
        rpDesc.colorAttachments[0].loadAction  = .clear
        rpDesc.colorAttachments[0].storeAction = .store
        rpDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0.92, green: 0.87, blue: 0.72, alpha: 1)

        guard let enc = commandBuffer.makeRenderCommandEncoder(descriptor: rpDesc) else {
            print("[ParchmentPass] ERROR: could not create bake encoder")
            return
        }

        enc.setRenderPipelineState(generatePipeline!)
        enc.setVertexBuffer(sharedQuadVertexBuffer, offset: 0, index: 0)

        var params = ParchmentParams(
            baseR: 0.92,
            baseG: 0.87,
            baseB: 0.72,
            grainAmplitude: 0.04,
            edgeDarken: 0.3,
            spotThreshold: 0.75,
            seed: parchmentSeed,
            _pad0: 0
        )
        enc.setFragmentBytes(&params, length: MemoryLayout<ParchmentParams>.stride, index: 0)

        enc.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: sharedQuadIndexBuffer,
            indexBufferOffset: 0
        )
        enc.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline      = displayPipeline,
            let texture       = cachedTexture,
            let vertexBuffer  = quadVertexBuffer,
            let indexBuffer   = quadIndexBuffer
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        encoder.popDebugGroup()
    }
}
