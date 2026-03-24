import Metal
import MetalKit
import simd

final class MapRenderer: NSObject, MTKViewDelegate {

    // MARK: - Render mode

    enum RenderMode {
        case debug
        case portolan
    }

    var renderMode: RenderMode = .debug
    var camera = CameraState()

    // MARK: - Core Metal objects

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let debugPipeline: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    private(set) var debugTexture: MTLTexture?

    // MARK: - Portolan render passes

    private var parchmentPass = ParchmentPass()
    private var terrainPass   = TerrainPass()
    private var coastlinePass = CoastlinePass()
    private var riverPass     = RiverPass()
    private var mountainPass  = MountainPass()
    private var labelPass     = LabelPass()
    private var decorPass     = DecorPass()
    private var passesReady   = false

    // MARK: - Init

    override init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device

        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create Metal command queue")
        }
        self.commandQueue = commandQueue

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library")
        }
        guard let vertexFunction   = library.makeFunction(name: "heightmap_vertex"),
              let fragmentFunction = library.makeFunction(name: "debug_rgba_fragment") else {
            fatalError("Could not find debug shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction   = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            debugPipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state: \(error)")
        }

        // Full-screen quad: 4 vertices covering clip space
        let vertices: [Vertex] = [
            Vertex(position: simd_float2(-1, -1), texCoord: simd_float2(0, 1)),
            Vertex(position: simd_float2( 1, -1), texCoord: simd_float2(1, 1)),
            Vertex(position: simd_float2( 1,  1), texCoord: simd_float2(1, 0)),
            Vertex(position: simd_float2(-1,  1), texCoord: simd_float2(0, 0)),
        ]

        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            fatalError("Could not create vertex buffer")
        }
        self.vertexBuffer = vb

        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        guard let ib = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared
        ) else {
            fatalError("Could not create index buffer")
        }
        self.indexBuffer = ib

        super.init()
    }

    // MARK: - Debug texture update

    func updateDebugTexture(from rgba: [UInt8], width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage       = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else { return }

        rgba.withUnsafeBufferPointer { ptr in
            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        debugTexture = texture
    }

    // MARK: - Portolan pass setup

    func preparePasses(engine: TerrainEngine) {
        guard let library = device.makeDefaultLibrary() else { return }
        parchmentPass.prepare(device: device, library: library, engine: engine,
                              sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        terrainPass.parchmentTexture = parchmentPass.cachedTexture
        terrainPass.prepare(device: device, library: library, engine: engine,
                            sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        coastlinePass.prepare(device: device, library: library, engine: engine,
                              sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        riverPass.prepare(device: device, library: library, engine: engine,
                          sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        mountainPass.prepare(device: device, library: library, engine: engine,
                             sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        labelPass.landmassPolygons = coastlinePass.landmassPolygons
        labelPass.prepare(device: device, library: library, engine: engine,
                          sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        decorPass.prepare(device: device, library: library, engine: engine,
                          sharedQuadVertexBuffer: vertexBuffer, sharedQuadIndexBuffer: indexBuffer)
        passesReady = true
    }

    // MARK: - Camera MVP

    private func buildMVP() -> simd_float4x4 {
        let scale = camera.zoom
        let tx    = -camera.offset.x * 2.0
        let ty    = -camera.offset.y * 2.0
        return simd_float4x4(columns: (
            SIMD4<Float>(scale, 0,     0, 0),
            SIMD4<Float>(0,     scale, 0, 0),
            SIMD4<Float>(0,     0,     1, 0),
            SIMD4<Float>(tx * scale, ty * scale, 0, 1)
        ))
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable            = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer        = commandQueue.makeCommandBuffer() else {
            return
        }

        if renderMode == .portolan && passesReady {
            // --- Portolan render path ---
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].loadAction = .clear

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.commit()
                return
            }

            var uniforms = Uniforms()
            uniforms.modelViewProjection = buildMVP()
            uniforms.mapSize = simd_float2(Float(view.drawableSize.width),
                                           Float(view.drawableSize.height))
            uniforms.seaLevel = 0.35
            uniforms.time = 0

            parchmentPass.encode(encoder: encoder, uniforms: &uniforms)
            terrainPass.encode(encoder: encoder, uniforms: &uniforms)
            coastlinePass.encode(encoder: encoder, uniforms: &uniforms)
            riverPass.encode(encoder: encoder, uniforms: &uniforms)
            mountainPass.encode(encoder: encoder, uniforms: &uniforms)
            labelPass.encode(encoder: encoder, uniforms: &uniforms)
            decorPass.encode(encoder: encoder, uniforms: &uniforms)

            encoder.endEncoding()
        } else {
            // --- Debug render path (unchanged) ---
            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                commandBuffer.commit()
                return
            }

            encoder.setRenderPipelineState(debugPipeline)
            encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

            if let texture = debugTexture {
                encoder.setFragmentTexture(texture, index: 0)
            }

            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: 6,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
