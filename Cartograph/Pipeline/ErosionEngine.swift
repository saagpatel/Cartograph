import Foundation
import Metal

final class ErosionEngine {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let computePipeline: MTLComputePipelineState

    static let fixedPointScale: Float = 65536.0

    init() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported")
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = queue
        guard let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "erosion_kernel") else {
            fatalError("Could not load erosion_kernel")
        }
        do {
            self.computePipeline = try device.makeComputePipelineState(function: function)
        } catch {
            fatalError("Could not create compute pipeline: \(error)")
        }
    }

    /// Run one batch of erosion particles on the height data.
    /// Returns the modified height data.
    func runBatch(
        heightData: [Float],
        width: Int,
        height: Int,
        particleCount: Int,
        erosionRate: Float,
        seed: UInt64,
        batchIndex: Int
    ) -> [Float] {
        let cellCount = width * height

        // Convert float to fixed-point int32
        var intData = heightData.map { Int32($0 * Self.fixedPointScale) }

        // Create GPU buffer (shared mode for unified memory readback)
        guard let heightBuffer = device.makeBuffer(
            bytes: &intData,
            length: cellCount * MemoryLayout<Int32>.size,
            options: .storageModeShared
        ) else {
            return heightData
        }

        // Build ErosionParams
        var params = ErosionParams()
        params.mapWidth = UInt32(width)
        params.mapHeight = UInt32(height)
        params.particleCount = UInt32(particleCount)
        params.inertia = 0.05
        params.sedimentCapacity = 4.0
        params.minSlope = 0.01
        params.erosionRate = erosionRate
        params.depositRate = erosionRate
        params.evaporationRate = 0.01
        params.seed = UInt32(seed & 0xFFFFFFFF)

        var batchIdx = UInt32(batchIndex)

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return heightData
        }

        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(heightBuffer, offset: 0, index: 0)
        encoder.setBytes(&params, length: MemoryLayout<ErosionParams>.size, index: 1)
        encoder.setBytes(&batchIdx, length: MemoryLayout<UInt32>.size, index: 2)

        let threadgroupWidth = min(computePipeline.maxTotalThreadsPerThreadgroup, 64)
        let threadgroupSize = MTLSize(width: threadgroupWidth, height: 1, depth: 1)
        let gridSize = MTLSize(width: particleCount, height: 1, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadgroupSize)
        encoder.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Readback: convert fixed-point int32 back to float
        let bufferPtr = heightBuffer.contents().bindMemory(to: Int32.self, capacity: cellCount)
        var result = [Float](repeating: 0, count: cellCount)
        for i in 0..<cellCount {
            result[i] = max(0.0, min(1.0, Float(bufferPtr[i]) / Self.fixedPointScale))
        }

        return result
    }
}
