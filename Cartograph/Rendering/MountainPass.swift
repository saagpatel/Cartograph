import Metal
import MetalKit
import simd

// MARK: - MountainPass
//
// Detects ridge cells in the height map using a local-maximum test in an 11×11
// window, computes ridge direction from the gradient, and renders instanced
// mountain glyph quads via MountainStroke.metal.

struct MountainPass: RenderPass {

    let label = "MountainPass"

    private var pipeline: MTLRenderPipelineState?

    // Unit quad buffers owned by this pass (separate from the fullscreen quad)
    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer:  MTLBuffer?

    // Per-instance data
    private var instanceBuffer: MTLBuffer?
    private var instanceCount:  Int = 0

    // Uniforms buffer reference (set during prepare for encoding)
    // We hold the shared quad buffers for the encoding call pattern.

    // MARK: - RenderPass

    mutating func prepare(
        device: MTLDevice,
        library: MTLLibrary,
        engine: TerrainEngine,
        sharedQuadVertexBuffer: MTLBuffer,
        sharedQuadIndexBuffer: MTLBuffer
    ) {
        // -----------------------------------------------------------------------
        // Pipeline: mountain_vertex + mountain_fragment, alpha blending
        // -----------------------------------------------------------------------
        guard
            let vert = library.makeFunction(name: "mountain_vertex"),
            let frag = library.makeFunction(name: "mountain_fragment")
        else {
            print("[MountainPass] ERROR: could not find mountain shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "MountainGlyph"
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
            print("[MountainPass] ERROR creating pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // Unit quad: local coords in [-0.5, 0.5] — the mountain shader reads
        // the `position` field of Vertex as the local offset.
        // -----------------------------------------------------------------------
        let unitVertices: [Vertex] = [
            Vertex(position: simd_float2(-0.5, -0.5), texCoord: simd_float2(0, 0)),
            Vertex(position: simd_float2( 0.5, -0.5), texCoord: simd_float2(1, 0)),
            Vertex(position: simd_float2( 0.5,  0.5), texCoord: simd_float2(1, 1)),
            Vertex(position: simd_float2(-0.5,  0.5), texCoord: simd_float2(0, 1)),
        ]
        let unitIndices: [UInt16] = [0, 1, 2, 0, 2, 3]

        quadVertexBuffer = device.makeBuffer(
            bytes: unitVertices,
            length: MemoryLayout<Vertex>.stride * unitVertices.count,
            options: .storageModeShared
        )
        quadIndexBuffer = device.makeBuffer(
            bytes: unitIndices,
            length: MemoryLayout<UInt16>.stride * unitIndices.count,
            options: .storageModeShared
        )

        // -----------------------------------------------------------------------
        // Ridge detection: 11×11 local maximum test above seaLevel + 0.3
        // -----------------------------------------------------------------------
        let hm       = engine.heightMap
        let w        = hm.width
        let h        = hm.height
        let seaLevel = hm.seaLevel
        let halfWin  = 5  // 11×11 window half-size

        var instances: [MountainInstance] = []
        instances.reserveCapacity(512)

        let step = 8  // sample every 8 cells to avoid over-dense placement

        for cy in stride(from: halfWin, to: h - halfWin, by: step) {
            for cx in stride(from: halfWin, to: w - halfWin, by: step) {
                let elev = hm.data[cy * w + cx]
                guard elev >= seaLevel + 0.3 else { continue }

                // Local maximum test in 11×11 window
                var isMax = true
                outerLoop: for dy in -halfWin...halfWin {
                    for dx in -halfWin...halfWin {
                        if dx == 0 && dy == 0 { continue }
                        let nx = cx + dx
                        let ny = cy + dy
                        guard nx >= 0 && nx < w && ny >= 0 && ny < h else { continue }
                        if hm.data[ny * w + nx] > elev {
                            isMax = false
                            break outerLoop
                        }
                    }
                }
                guard isMax else { continue }

                // Gradient via central differences for ridge direction
                let left  = cx > 0     ? hm.data[cy * w + (cx - 1)] : elev
                let right = cx < w - 1 ? hm.data[cy * w + (cx + 1)] : elev
                let up    = cy > 0     ? hm.data[(cy - 1) * w + cx]  : elev
                let down  = cy < h - 1 ? hm.data[(cy + 1) * w + cx]  : elev

                let gradX = (right - left) * 0.5
                let gradY = (down  - up)   * 0.5

                // Perpendicular to gradient = ridge direction
                let ridgeAngle: Float
                if abs(gradX) < 1e-6 && abs(gradY) < 1e-6 {
                    ridgeAngle = 0
                } else {
                    // 90° CCW from gradient
                    ridgeAngle = atan2(gradX, -gradY)
                }

                // Size mapped from elevation: 0.008 at seaLevel+0.3 → 0.02 at 1.0
                let elevNorm = (elev - (seaLevel + 0.3)) / max(1.0 - (seaLevel + 0.3), 0.01)
                let size     = 0.008 + elevNorm * (0.02 - 0.008)

                let centerUV = SIMD2<Float>(Float(cx) / Float(w), Float(cy) / Float(h))

                instances.append(MountainInstance(
                    center: centerUV,
                    size: size,
                    rotation: ridgeAngle
                ))
            }
        }

        instanceCount = instances.count
        guard instanceCount > 0 else { return }

        instanceBuffer = device.makeBuffer(
            bytes: instances,
            length: MemoryLayout<MountainInstance>.stride * instances.count,
            options: .storageModeShared
        )
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline    = pipeline,
            let quadVerts   = quadVertexBuffer,
            let quadIdxs    = quadIndexBuffer,
            let instBuf     = instanceBuffer,
            instanceCount > 0
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)

        encoder.setVertexBuffer(quadVerts, offset: 0, index: 0)
        encoder.setVertexBuffer(instBuf,   offset: 0, index: 1)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 2)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: quadIdxs,
            indexBufferOffset: 0,
            instanceCount: instanceCount
        )
        encoder.popDebugGroup()
    }
}
