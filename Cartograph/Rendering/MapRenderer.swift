import Metal
import MetalKit
import simd

final class MapRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let debugPipeline: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private(set) var debugTexture: MTLTexture?

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
        guard let vertexFunction = library.makeFunction(name: "heightmap_vertex"),
              let fragmentFunction = library.makeFunction(name: "debug_rgba_fragment") else {
            fatalError("Could not find debug shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
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

    func updateDebugTexture(from rgba: [UInt8], width: Int, height: Int) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
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

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
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

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
