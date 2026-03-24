import Metal
import MetalKit
import simd
import CoreGraphics

// MARK: - DecorPass
//
// Renders decorative cartographic elements:
//   • A double-line border frame
//   • A compass rose (bottom-right)
//   • Two stylised sea-monster glyphs placed in deep ocean regions

struct DecorPass: RenderPass {

    let label = "DecorPass"

    private var pipeline: MTLRenderPipelineState?

    // Textures
    private var borderTexture:   MTLTexture?
    private var compassTexture:  MTLTexture?
    private var monster1Texture: MTLTexture?
    private var monster2Texture: MTLTexture?

    // Fullscreen quad for border/label layers
    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer:  MTLBuffer?

    // Positioned quads for compass and monsters
    private var compassVertexBuffer:  MTLBuffer?
    private var monster1VertexBuffer: MTLBuffer?
    private var monster2VertexBuffer: MTLBuffer?
    // All positioned quads share the same 6-index buffer
    private var positionedIndexBuffer: MTLBuffer?

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

        // -----------------------------------------------------------------------
        // Pipeline: heightmap_vertex + debug_rgba_fragment, alpha blending
        // -----------------------------------------------------------------------
        guard
            let vert = library.makeFunction(name: "heightmap_vertex"),
            let frag = library.makeFunction(name: "debug_rgba_fragment")
        else {
            print("[DecorPass] ERROR: could not find display shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "DecorComposite"
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
            print("[DecorPass] ERROR creating pipeline: \(error)")
            return
        }

        // Shared index buffer for all positioned quads
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        positionedIndexBuffer = device.makeBuffer(
            bytes: indices,
            length: MemoryLayout<UInt16>.stride * indices.count,
            options: .storageModeShared
        )

        // -----------------------------------------------------------------------
        // Border texture: 2048×2048, double-line warm brown frame
        // -----------------------------------------------------------------------
        borderTexture = makeBorderTexture(device: device)

        // -----------------------------------------------------------------------
        // Compass rose texture: 512×512
        // -----------------------------------------------------------------------
        compassTexture = makeCompassTexture(device: device)

        // Compass rose positioned quad: UV centre (0.85, 0.05), half-size 0.06
        compassVertexBuffer = makePositionedQuadBuffer(
            device: device,
            centerU: 0.85, centerV: 0.05,
            halfW: 0.06, halfH: 0.06
        )

        // -----------------------------------------------------------------------
        // Sea monsters
        // -----------------------------------------------------------------------
        monster1Texture = makeMonsterTexture(device: device, variant: 1)
        monster2Texture = makeMonsterTexture(device: device, variant: 2)

        // Find 2 largest deep-ocean regions for monster placement
        let positions = findDeepOceanPositions(engine: engine, count: 2)

        let m1Pos = positions.count > 0 ? positions[0] : SIMD2<Float>(0.15, 0.65)
        let m2Pos = positions.count > 1 ? positions[1] : SIMD2<Float>(0.75, 0.70)

        monster1VertexBuffer = makePositionedQuadBuffer(
            device: device,
            centerU: m1Pos.x, centerV: m1Pos.y,
            halfW: 0.06, halfH: 0.03
        )
        monster2VertexBuffer = makePositionedQuadBuffer(
            device: device,
            centerU: m2Pos.x, centerV: m2Pos.y,
            halfW: 0.06, halfH: 0.03
        )
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline = pipeline,
            let idxBuf   = quadIndexBuffer,
            let posIdxBuf = positionedIndexBuffer
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)

        // 1. Border (fullscreen quad)
        if let borderTex = borderTexture, let vertBuf = quadVertexBuffer {
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setFragmentTexture(borderTex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: 6, indexType: .uint16,
                indexBuffer: idxBuf, indexBufferOffset: 0
            )
        }

        // 2. Sea monsters
        if let tex = monster1Texture, let vertBuf = monster1VertexBuffer {
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: 6, indexType: .uint16,
                indexBuffer: posIdxBuf, indexBufferOffset: 0
            )
        }
        if let tex = monster2Texture, let vertBuf = monster2VertexBuffer {
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: 6, indexType: .uint16,
                indexBuffer: posIdxBuf, indexBufferOffset: 0
            )
        }

        // 3. Compass rose (drawn last so it sits on top)
        if let tex = compassTexture, let vertBuf = compassVertexBuffer {
            encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
            encoder.setFragmentTexture(tex, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: 6, indexType: .uint16,
                indexBuffer: posIdxBuf, indexBufferOffset: 0
            )
        }

        encoder.popDebugGroup()
    }

    // MARK: - Border Texture

    private func makeBorderTexture(device: MTLDevice) -> MTLTexture? {
        let size = 2048
        guard let ctx = makeBitmapContext(size: size) else { return nil }

        // Warm brown stroke colour
        ctx.setStrokeColor(CGColor(red: 0.35, green: 0.22, blue: 0.12, alpha: 1.0))

        // Outer rect: 16px stroke, inset 32px
        ctx.setLineWidth(16)
        let outer = CGRect(x: 32, y: 32, width: CGFloat(size) - 64, height: CGFloat(size) - 64)
        ctx.stroke(outer)

        // Inner rect: 8px stroke, inset 48px
        ctx.setLineWidth(8)
        let inner = CGRect(x: 48, y: 48, width: CGFloat(size) - 96, height: CGFloat(size) - 96)
        ctx.stroke(inner)

        return uploadCGContext(ctx, size: size, device: device, label: "BorderTexture")
    }

    // MARK: - Compass Rose Texture

    private func makeCompassTexture(device: MTLDevice) -> MTLTexture? {
        let size = 512
        guard let ctx = makeBitmapContext(size: size) else { return nil }

        let cx = CGFloat(size) / 2
        let cy = CGFloat(size) / 2

        // Fill colour: warm off-white
        let fillColor  = CGColor(red: 0.95, green: 0.90, blue: 0.78, alpha: 1.0)
        // Stroke colour: dark brown
        let strokeColor = CGColor(red: 0.25, green: 0.14, blue: 0.06, alpha: 1.0)

        // Centre circle
        ctx.setFillColor(strokeColor)
        ctx.addEllipse(in: CGRect(x: cx - 18, y: cy - 18, width: 36, height: 36))
        ctx.fillPath()

        // 4 cardinal points (N tallest = 180px, E/W = 130px, S = 150px)
        let cardinalHeights: [(angle: CGFloat, height: CGFloat)] = [
            (-.pi / 2,  180),   // N  (up)
            (0,         130),   // E
            (.pi / 2,   150),   // S
            (.pi,       130),   // W
        ]

        for (angle, height) in cardinalHeights {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: angle)

            // Triangle: tip at (0, -height), base ±22 at y=0
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -height))
            path.addLine(to: CGPoint(x: -22, y: 0))
            path.addLine(to: CGPoint(x:  22, y: 0))
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(2.5)
            ctx.strokePath()

            ctx.restoreGState()
        }

        // 4 intercardinal points (100px, 45° offset)
        let intercardinalAngles: [CGFloat] = [
            -.pi / 4,     // NE
            .pi / 4,      // SE
            3 * .pi / 4,  // SW
            -3 * .pi / 4  // NW
        ]

        for angle in intercardinalAngles {
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: angle)

            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -100))
            path.addLine(to: CGPoint(x: -15, y: 0))
            path.addLine(to: CGPoint(x:  15, y: 0))
            path.closeSubpath()

            ctx.addPath(path)
            ctx.setFillColor(fillColor)
            ctx.fillPath()
            ctx.addPath(path)
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(2.0)
            ctx.strokePath()

            ctx.restoreGState()
        }

        // "N" label above north pointer
        let nFont = CTFontCreateWithName("Georgia-Bold" as CFString, 40, nil)
        let nAttrs: [CFString: Any] = [
            kCTFontAttributeName: nFont,
            kCTForegroundColorAttributeName: strokeColor
        ]
        let nStr  = CFAttributedStringCreate(nil, "N" as CFString, nAttrs as CFDictionary)!
        let nLine = CTLineCreateWithAttributedString(nStr)
        let nBounds = CTLineGetImageBounds(nLine, ctx)
        ctx.saveGState()
        ctx.textPosition = CGPoint(
            x: cx - nBounds.width / 2,
            y: cy - 180 - nBounds.height - 8
        )
        CTLineDraw(nLine, ctx)
        ctx.restoreGState()

        return uploadCGContext(ctx, size: size, device: device, label: "CompassTexture")
    }

    // MARK: - Sea Monster Textures

    private func makeMonsterTexture(device: MTLDevice, variant: Int) -> MTLTexture? {
        let w = 1024
        let h = 512
        guard let ctx = makeBitmapContext(width: w, height: h) else { return nil }

        let fillColor   = CGColor(red: 0.12, green: 0.22, blue: 0.28, alpha: 0.85)
        let strokeColor = CGColor(red: 0.15, green: 0.10, blue: 0.05, alpha: 1.0)

        ctx.setFillColor(fillColor)
        ctx.setStrokeColor(strokeColor)
        ctx.setLineWidth(3.0)

        let cx = CGFloat(w) / 2
        let cy = CGFloat(h) / 2

        if variant == 1 {
            // Variant 1: S-curve serpent body
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 80, y: cy))
            body.addCurve(
                to:      CGPoint(x: cx,    y: cy - 80),
                control1: CGPoint(x: cx / 2,  y: cy - 120),
                control2: CGPoint(x: cx / 2,  y: cy - 40)
            )
            body.addCurve(
                to:      CGPoint(x: CGFloat(w) - 80, y: cy),
                control1: CGPoint(x: cx + cx / 2, y: cy + 40),
                control2: CGPoint(x: cx + cx / 2, y: cy + 120)
            )

            ctx.setLineWidth(28)
            ctx.addPath(body)
            ctx.replacePathWithStrokedPath()
            ctx.fillPath()

            // Dorsal fins
            let finPositions: [CGFloat] = [0.25, 0.45, 0.65]
            for t in finPositions {
                let px = 80 + t * CGFloat(w - 160)
                let finPath = CGMutablePath()
                finPath.move(to: CGPoint(x: px, y: cy - 30))
                finPath.addCurve(
                    to:      CGPoint(x: px + 25, y: cy - 80),
                    control1: CGPoint(x: px - 10, y: cy - 70),
                    control2: CGPoint(x: px + 10, y: cy - 80)
                )
                finPath.addCurve(
                    to:      CGPoint(x: px + 50, y: cy - 25),
                    control1: CGPoint(x: px + 40, y: cy - 80),
                    control2: CGPoint(x: px + 55, y: cy - 50)
                )
                ctx.addPath(finPath)
                ctx.setFillColor(fillColor)
                ctx.fillPath()
                ctx.addPath(finPath)
                ctx.setStrokeColor(strokeColor)
                ctx.setLineWidth(2.0)
                ctx.strokePath()
            }

            // Head — simple elongated ellipse
            ctx.setFillColor(fillColor)
            ctx.addEllipse(in: CGRect(x: 40, y: cy - 22, width: 80, height: 44))
            ctx.fillPath()
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(2.5)
            ctx.addEllipse(in: CGRect(x: 40, y: cy - 22, width: 80, height: 44))
            ctx.strokePath()

        } else {
            // Variant 2: coiled/spiral creature
            let coilPath = CGMutablePath()
            let startAngle: CGFloat = 0
            let endAngle:   CGFloat = 3 * .pi

            let coilCX: CGFloat = cx
            let coilCY: CGFloat = cy

            for i in 0..<200 {
                let t        = CGFloat(i) / 200.0
                let angle    = startAngle + t * (endAngle - startAngle)
                let radius   = 40 + t * 140
                let px       = coilCX + cos(angle) * radius
                let py       = coilCY + sin(angle) * radius

                if i == 0 {
                    coilPath.move(to: CGPoint(x: px, y: py))
                } else {
                    coilPath.addLine(to: CGPoint(x: px, y: py))
                }
            }

            ctx.setLineWidth(22)
            ctx.setStrokeColor(fillColor)
            ctx.addPath(coilPath)
            ctx.strokePath()

            ctx.setLineWidth(3)
            ctx.setStrokeColor(strokeColor)
            ctx.addPath(coilPath)
            ctx.strokePath()

            // Head at centre
            ctx.setFillColor(fillColor)
            ctx.addEllipse(in: CGRect(x: coilCX - 28, y: coilCY - 18, width: 56, height: 36))
            ctx.fillPath()
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(2.5)
            ctx.addEllipse(in: CGRect(x: coilCX - 28, y: coilCY - 18, width: 56, height: 36))
            ctx.strokePath()
        }

        return uploadCGContext(ctx, width: w, height: h, device: device, label: "MonsterTexture\(variant)")
    }

    // MARK: - Ocean Detection

    private func findDeepOceanPositions(engine: TerrainEngine, count: Int) -> [SIMD2<Float>] {
        let hm         = engine.heightMap
        let w          = hm.width
        let h          = hm.height
        let deepThresh: Float = 0.20
        let flowThresh: Float = 0.1

        // Flood fill to find connected deep-ocean regions
        var visited = [Bool](repeating: false, count: w * h)
        var regions: [(centroid: SIMD2<Float>, size: Int)] = []

        for startY in stride(from: 10, to: h - 10, by: 20) {
            for startX in stride(from: 10, to: w - 10, by: 20) {
                let idx = startY * w + startX
                guard !visited[idx] else { continue }
                let elev = hm.data[idx]
                let flow = engine.flowAccumulationMap.isEmpty ? Float(0) : engine.flowAccumulationMap[idx]
                guard elev < deepThresh && flow < flowThresh else { continue }

                // BFS flood fill
                var queue  = [(x: startX, y: startY)]
                var pixels = [(x: Int, y: Int)]()
                visited[idx] = true

                var head = 0
                while head < queue.count {
                    let (cx, cy) = (queue[head].x, queue[head].y)
                    head += 1
                    pixels.append((cx, cy))

                    let neighbours = [(cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)]
                    for (nx, ny) in neighbours {
                        guard nx >= 0 && nx < w && ny >= 0 && ny < h else { continue }
                        let ni = ny * w + nx
                        guard !visited[ni] else { continue }
                        let ne = hm.data[ni]
                        let nf = engine.flowAccumulationMap.isEmpty ? Float(0) : engine.flowAccumulationMap[ni]
                        guard ne < deepThresh && nf < flowThresh else { continue }
                        visited[ni] = true
                        queue.append((nx, ny))
                    }
                }

                if pixels.count > 50 {
                    let sumX = pixels.reduce(0) { $0 + $1.x }
                    let sumY = pixels.reduce(0) { $0 + $1.y }
                    let centroid = SIMD2<Float>(
                        Float(sumX) / Float(pixels.count) / Float(w),
                        Float(sumY) / Float(pixels.count) / Float(h)
                    )
                    regions.append((centroid: centroid, size: pixels.count))
                }
            }
        }

        // Return centroids of the 2 largest regions
        let sorted = regions.sorted { $0.size > $1.size }
        return sorted.prefix(count).map { $0.centroid }
    }

    // MARK: - Geometry Helpers

    /// Build a Vertex buffer for a positioned quad in UV space.
    /// centerU/centerV are the UV coordinates of the quad centre; halfW/halfH are the half-extents.
    private func makePositionedQuadBuffer(
        device: MTLDevice,
        centerU: Float,
        centerV: Float,
        halfW: Float,
        halfH: Float
    ) -> MTLBuffer? {
        // Vertex.position is in clip space [-1,1]; texCoord is UV [0,1].
        // heightmap_vertex passes position straight through (x2-1 convention already set in
        // the fullscreen quad). For positioned quads we pre-compute clip coords directly.
        let u0 = centerU - halfW;  let u1 = centerU + halfW
        let v0 = centerV - halfH;  let v1 = centerV + halfH

        // UV → clip: clip_x = u*2-1, clip_y = -(v*2-1) (Metal NDC has Y up, UV has Y down)
        func toClip(_ u: Float, _ v: Float) -> SIMD2<Float> {
            SIMD2<Float>(u * 2 - 1, -(v * 2 - 1))
        }

        let vertices: [Vertex] = [
            Vertex(position: toClip(u0, v1), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: toClip(u1, v1), texCoord: SIMD2<Float>(1, 1)),
            Vertex(position: toClip(u1, v0), texCoord: SIMD2<Float>(1, 0)),
            Vertex(position: toClip(u0, v0), texCoord: SIMD2<Float>(0, 0)),
        ]

        return device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
    }

    // MARK: - CGContext / Texture Helpers

    private func makeBitmapContext(size: Int) -> CGContext? {
        makeBitmapContext(width: size, height: size)
    }

    private func makeBitmapContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        return CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )
    }

    private func uploadCGContext(
        _ ctx: CGContext,
        size: Int,
        device: MTLDevice,
        label: String
    ) -> MTLTexture? {
        uploadCGContext(ctx, width: size, height: size, device: device, label: label)
    }

    private func uploadCGContext(
        _ ctx: CGContext,
        width: Int,
        height: Int,
        device: MTLDevice,
        label: String
    ) -> MTLTexture? {
        guard
            let cgImage      = ctx.makeImage(),
            let dataProvider = cgImage.dataProvider,
            let rawData      = dataProvider.data
        else {
            print("[DecorPass] ERROR: could not extract CGImage data for \(label)")
            return nil
        }

        let byteCount = CFDataGetLength(rawData)
        let bytePtr   = CFDataGetBytePtr(rawData)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage       = .shaderRead
        texDesc.storageMode = .managed

        guard let tex = device.makeTexture(descriptor: texDesc) else { return nil }
        tex.label = label

        bytePtr?.withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
            tex.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: width, height: height, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr,
                bytesPerRow: width * 4
            )
        }
        return tex
    }
}
