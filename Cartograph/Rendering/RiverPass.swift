import Metal
import MetalKit
import simd

// MARK: - RiverPass
//
// Traces each river chain from headwater to terminus using the RiverNode graph,
// builds wobbled quad-strip geometry, and renders with the coastline stroke shader
// using a blue-black ink colour.

struct RiverPass: RenderPass {

    let label = "RiverPass"

    private var pipeline: MTLRenderPipelineState?
    private var strokeVertexBuffer: MTLBuffer?
    private var strokeIndexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    // MARK: - RenderPass

    mutating func prepare(
        device: MTLDevice,
        library: MTLLibrary,
        engine: TerrainEngine,
        sharedQuadVertexBuffer: MTLBuffer,
        sharedQuadIndexBuffer: MTLBuffer
    ) {
        // -----------------------------------------------------------------------
        // Pipeline: reuse coastline_vertex + coastline_fragment, alpha blending
        // -----------------------------------------------------------------------
        guard
            let vert = library.makeFunction(name: "coastline_vertex"),
            let frag = library.makeFunction(name: "coastline_fragment")
        else {
            print("[RiverPass] ERROR: could not find coastline shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "RiverStroke"
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
            print("[RiverPass] ERROR creating pipeline: \(error)")
            return
        }

        let nodes = engine.riverNodes
        guard !nodes.isEmpty else { return }

        // -----------------------------------------------------------------------
        // Build UUID → node lookup
        // -----------------------------------------------------------------------
        let nodeMap: [UUID: RiverNode] = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        // Find headwaters: nodes whose ID does not appear as a downstream of any other node
        let downstreamIDs = Set(nodes.compactMap { $0.downstream })
        let headwaters    = nodes.filter { !downstreamIDs.contains($0.id) }

        // -----------------------------------------------------------------------
        // Trace chains and build geometry
        // -----------------------------------------------------------------------
        var allVertices: [StrokeVertex] = []
        var allIndices:  [UInt16]       = []

        for headwater in headwaters {
            // Walk downstream until terminus or cycle
            var chain: [RiverNode] = []
            var visited: Set<UUID>  = []
            var current: RiverNode? = headwater

            while let node = current {
                guard !visited.contains(node.id) else { break }
                visited.insert(node.id)
                chain.append(node)

                if let dsID = node.downstream {
                    current = nodeMap[dsID]
                } else {
                    break
                }
            }

            guard chain.count >= 2 else { continue }

            // Per-node width based on flow accumulation
            let polylinePoints: [StrokeGeometry.PolylinePoint] = chain.map { node in
                let fa    = Float(node.flowAccumulation)
                let w     = min(2.5, max(0.5, log(max(fa, 1)) * 0.3)) / 1024.0
                // noise reused as a stroke profile modulator
                let n     = Float(0)
                return StrokeGeometry.PolylinePoint(position: node.position, width: w, noise: n)
            }

            // Extract positions for wobble
            let positions = polylinePoints.map { $0.position }
            let wobbled   = StrokeGeometry.applyWobble(
                to: positions,
                amplitude: 0.001,
                seed: 99887
            )

            // Rebuild with wobbled positions
            let finalPoints: [StrokeGeometry.PolylinePoint] = zip(wobbled, polylinePoints).map { pos, orig in
                StrokeGeometry.PolylinePoint(position: pos, width: orig.width, noise: orig.noise)
            }

            let (verts, idxs) = StrokeGeometry.buildQuadStrip(from: finalPoints)
            guard !verts.isEmpty, !idxs.isEmpty else { continue }

            let vertexOffset = UInt16(allVertices.count)
            let offsetIdxs   = idxs.map { $0 &+ vertexOffset }

            guard allVertices.count + verts.count <= 65535 else { continue }

            allVertices.append(contentsOf: verts)
            allIndices.append(contentsOf: offsetIdxs)
        }

        guard !allVertices.isEmpty else { return }

        strokeVertexBuffer = device.makeBuffer(
            bytes: allVertices,
            length: MemoryLayout<StrokeVertex>.stride * allVertices.count,
            options: .storageModeShared
        )
        strokeIndexBuffer = device.makeBuffer(
            bytes: allIndices,
            length: MemoryLayout<UInt16>.stride * allIndices.count,
            options: .storageModeShared
        )
        indexCount = allIndices.count
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline = pipeline,
            let vertBuf  = strokeVertexBuffer,
            let idxBuf   = strokeIndexBuffer,
            indexCount > 0
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)

        encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        // Blue-black ink
        var colorParams = StrokeColorParams(color: SIMD4<Float>(0.1, 0.12, 0.25, 1.0))
        encoder.setFragmentBytes(&colorParams, length: MemoryLayout<StrokeColorParams>.stride, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: idxBuf,
            indexBufferOffset: 0
        )
        encoder.popDebugGroup()
    }
}
