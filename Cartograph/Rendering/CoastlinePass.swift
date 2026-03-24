import Metal
import MetalKit
import simd

// MARK: - CoastlinePass
//
// Extracts iso-contours at sea level from the height map, smooths and wobbles
// them, then renders them as inked quad-strip strokes using CoastlineStroke.metal.
// Exposes landmassPolygons for use by LabelPass.

struct CoastlinePass: RenderPass {

    let label = "CoastlinePass"

    private var pipeline: MTLRenderPipelineState?
    private var strokeVertexBuffer: MTLBuffer?
    private var strokeIndexBuffer: MTLBuffer?
    private var indexCount: Int = 0

    /// Smoothed landmass polygons — populated during prepare, read by LabelPass.
    private(set) var landmassPolygons: [LandmassPolygon] = []

    // MARK: - RenderPass

    mutating func prepare(
        device: MTLDevice,
        library: MTLLibrary,
        engine: TerrainEngine,
        sharedQuadVertexBuffer: MTLBuffer,
        sharedQuadIndexBuffer: MTLBuffer
    ) {
        // -----------------------------------------------------------------------
        // Pipeline: coastline_vertex + coastline_fragment, alpha blending
        // -----------------------------------------------------------------------
        guard
            let vert = library.makeFunction(name: "coastline_vertex"),
            let frag = library.makeFunction(name: "coastline_fragment")
        else {
            print("[CoastlinePass] ERROR: could not find coastline shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "CoastlineStroke"
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
            print("[CoastlinePass] ERROR creating pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // Extract contours at sea level from the height map
        // -----------------------------------------------------------------------
        let hm     = engine.heightMap
        let contours = MarchingSquares.extractContours(
            heightData: hm.data,
            width: hm.width,
            height: hm.height,
            threshold: hm.seaLevel
        )

        // -----------------------------------------------------------------------
        // Build stroke geometry for all polygons
        // -----------------------------------------------------------------------
        let noise = NoiseGenerator(seed: 12345)
        var allVertices: [StrokeVertex] = []
        var allIndices:  [UInt16]       = []
        var smoothedPolygons: [LandmassPolygon] = []

        for polygon in contours {
            // Smooth with Catmull-Rom
            let smoothed = MarchingSquares.smoothPolygon(
                polygon.points,
                tension: 0.5,
                subdivisions: 4
            )
            guard smoothed.count >= 2 else { continue }

            // Apply wobble perpendicular to each vertex tangent
            let wobbled = StrokeGeometry.applyWobble(
                to: smoothed,
                amplitude: 0.002,
                seed: 12345
            )

            // Build PolylinePoint array with per-vertex width varied by noise
            let baseWidth: Float = 2.5 / 1024.0
            let minWidth:  Float = 1.5 / 1024.0
            let maxWidth:  Float = 3.5 / 1024.0

            var polylinePoints: [StrokeGeometry.PolylinePoint] = wobbled.map { uv in
                let n = (noise.simplex2D(x: uv.x * 300, y: uv.y * 300) + 1) * 0.5  // [0,1]
                let w = minWidth + n * (maxWidth - minWidth)
                return StrokeGeometry.PolylinePoint(position: uv, width: w, noise: n * 2 - 1)
            }
            _ = baseWidth  // used via range above

            let (verts, idxs) = StrokeGeometry.buildQuadStrip(from: polylinePoints)
            guard !verts.isEmpty, !idxs.isEmpty else { continue }

            // Offset indices by current vertex count before concatenating
            let vertexOffset = UInt16(allVertices.count)
            let offsetIdxs   = idxs.map { $0 &+ vertexOffset }

            // Guard against UInt16 overflow
            guard allVertices.count + verts.count <= 65535 else { continue }

            allVertices.append(contentsOf: verts)
            allIndices.append(contentsOf: offsetIdxs)

            // Re-compute smoothed polygon's centroid and area from wobbled points
            let area     = shoelaceArea(wobbled)
            let centroid = wobbled.reduce(.zero, +) / Float(wobbled.count)
            smoothedPolygons.append(LandmassPolygon(points: wobbled, centroid: centroid, area: area))
        }

        landmassPolygons = smoothedPolygons

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
            let pipeline     = pipeline,
            let vertBuf      = strokeVertexBuffer,
            let idxBuf       = strokeIndexBuffer,
            indexCount > 0
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)

        encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        var colorParams = StrokeColorParams(color: SIMD4<Float>(0.15, 0.10, 0.05, 1.0))
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

    // MARK: - Helpers

    private func shoelaceArea(_ points: [SIMD2<Float>]) -> Float {
        var area: Float = 0
        let n = points.count
        for i in 0..<n {
            let j = (i + 1) % n
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        return abs(area) / 2.0
    }
}
