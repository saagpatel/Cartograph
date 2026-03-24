import Metal
import MetalKit
import simd

final class MapRenderer: NSObject, MTKViewDelegate {

    let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let vertexBuffer: MTLBuffer
    private let indexBuffer: MTLBuffer
    private(set) var heightMapTexture: MTLTexture?

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
              let fragmentFunction = library.makeFunction(name: "heightmap_fragment") else {
            fatalError("Could not find heightmap shader functions")
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create render pipeline state: \(error)")
        }

        // Full-screen quad: 4 vertices covering clip space
        let vertices: [Vertex] = [
            Vertex(position: simd_float2(-1, -1), texCoord: simd_float2(0, 1)),  // bottom-left
            Vertex(position: simd_float2( 1, -1), texCoord: simd_float2(1, 1)),  // bottom-right
            Vertex(position: simd_float2( 1,  1), texCoord: simd_float2(1, 0)),  // top-right
            Vertex(position: simd_float2(-1,  1), texCoord: simd_float2(0, 0)),  // top-left
        ]

        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        ) else {
            fatalError("Could not create vertex buffer")
        }
        self.vertexBuffer = vb

        // Two triangles: bottom-left → bottom-right → top-right, bottom-left → top-right → top-left
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

    func updateHeightMapTexture(from heightMap: HeightMap) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float,
            width: heightMap.width,
            height: heightMap.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .managed

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return
        }

        heightMap.data.withUnsafeBufferPointer { ptr in
            texture.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: heightMap.width, height: heightMap.height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: heightMap.width * MemoryLayout<Float>.size
            )
        }

        heightMapTexture = texture
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

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        if let texture = heightMapTexture {
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
