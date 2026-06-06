import Metal
import MetalKit
import simd
import CoreText
import CoreGraphics

// MARK: - LabelPass
//
// Renders continent and ocean labels into a 2048×2048 CGBitmapContext,
// then uploads the result as an RGBA8 texture and composites it over the map
// with alpha blending.

struct LabelPass: RenderPass {

    let label = "LabelPass"

    private var pipeline: MTLRenderPipelineState?
    private var labelTexture: MTLTexture?

    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer:  MTLBuffer?

    /// Set by the host renderer after CoastlinePass.prepare() completes.
    var landmassPolygons: [LandmassPolygon] = []

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
            print("[LabelPass] ERROR: could not find display shader functions")
            return
        }

        let pipeDesc = MTLRenderPipelineDescriptor()
        pipeDesc.label            = "LabelComposite"
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
            print("[LabelPass] ERROR creating pipeline: \(error)")
            return
        }

        // -----------------------------------------------------------------------
        // Register bundled fonts
        // -----------------------------------------------------------------------
        registerBundledFonts()

        // -----------------------------------------------------------------------
        // Create 2048×2048 CGBitmapContext (premultiplied alpha)
        // -----------------------------------------------------------------------
        let bitmapSize = 2048
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: bitmapSize,
            height: bitmapSize,
            bitsPerComponent: 8,
            bytesPerRow: bitmapSize * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            print("[LabelPass] ERROR: could not create CGBitmapContext")
            return
        }

        // Transparent background
        ctx.clear(CGRect(x: 0, y: 0, width: bitmapSize, height: bitmapSize))

        // Flip coordinate system so Y=0 is top (matching UV conventions)
        ctx.translateBy(x: 0, y: CGFloat(bitmapSize))
        ctx.scaleBy(x: 1, y: -1)

        // Dark brown ink colour for labels
        let inkColor = CGColor(
            colorSpace: colorSpace,
            components: [0.18, 0.12, 0.08, 1.0]
        )!

        // 32×32 overlap grid to avoid collisions (each cell = 64×64 px)
        let gridCols = 32
        let gridRows = 32
        var occupied = [Bool](repeating: false, count: gridCols * gridRows)

        let cellW = CGFloat(bitmapSize) / CGFloat(gridCols)
        let cellH = CGFloat(bitmapSize) / CGFloat(gridRows)

        // -----------------------------------------------------------------------
        // Continent labels — up to 8, sorted largest landmass first
        // -----------------------------------------------------------------------
        let continentNames = [
            "Terra I", "Terra II", "Terra III", "Terra IV",
            "Terra V", "Terra VI", "Terra VII", "Terra VIII"
        ]

        let continentFont = makeCTFont(name: "CinzelDecorative-Regular", size: 36)
            ?? makeCTFont(name: "Georgia-Italic", size: 36)

        let sorted = landmassPolygons.sorted { $0.area > $1.area }
        let continentCount = min(8, sorted.count)

        for i in 0..<continentCount {
            let poly   = sorted[i]
            let name   = continentNames[i]
            let px     = poly.centroid.x * Float(bitmapSize)
            let py     = poly.centroid.y * Float(bitmapSize)

            if let font = continentFont {
                drawLabel(
                    ctx: ctx,
                    text: name,
                    font: font,
                    color: inkColor,
                    centerX: CGFloat(px),
                    centerY: CGFloat(py),
                    rotation: 0,
                    occupied: &occupied,
                    gridCols: gridCols,
                    gridRows: gridRows,
                    cellW: cellW,
                    cellH: cellH,
                    bitmapSize: CGFloat(bitmapSize)
                )
            }
        }

        // -----------------------------------------------------------------------
        // Ocean labels — one per quadrant where elevation is below sea level
        // -----------------------------------------------------------------------
        let oceanNames: [(name: String, quadX: Float, quadY: Float)] = [
            ("Mare Occidentale", 0.25, 0.5),
            ("Mare Orientale",   0.75, 0.5),
            ("Mare Boreale",     0.5,  0.25),
            ("Mare Australe",    0.5,  0.75),
        ]

        let oceanFont = makeCTFont(name: "IMFellEnglish-Regular", size: 28)
            ?? makeCTFont(name: "IM Fell English", size: 28)
            ?? makeCTFont(name: "Georgia-Italic", size: 28)

        let hm = engine.heightMap
        let rotAngle: CGFloat = -15.0 * .pi / 180.0  // 15° counter-clockwise

        for entry in oceanNames {
            // Find a deep ocean cell near this quadrant center
            let targetX = Int(entry.quadX * Float(hm.width))
            let targetY = Int(entry.quadY * Float(hm.height))
            let clampedX = max(0, min(hm.width  - 1, targetX))
            let clampedY = max(0, min(hm.height - 1, targetY))
            let elevation = hm.data[clampedY * hm.width + clampedX]

            // Only label if the quadrant centre is in the ocean
            guard elevation < hm.seaLevel else { continue }

            let px = entry.quadX * Float(bitmapSize)
            let py = entry.quadY * Float(bitmapSize)

            if let font = oceanFont {
                drawLabel(
                    ctx: ctx,
                    text: entry.name,
                    font: font,
                    color: inkColor,
                    centerX: CGFloat(px),
                    centerY: CGFloat(py),
                    rotation: rotAngle,
                    occupied: &occupied,
                    gridCols: gridCols,
                    gridRows: gridRows,
                    cellW: cellW,
                    cellH: cellH,
                    bitmapSize: CGFloat(bitmapSize)
                )
            }
        }

        // -----------------------------------------------------------------------
        // Settlement labels — dot + name below, IM Fell English 14pt
        // -----------------------------------------------------------------------
        let settlementFont = makeCTFont(name: "IMFellEnglish-Regular", size: 14)
            ?? makeCTFont(name: "Georgia-Italic", size: 14)
            ?? makeCTFont(name: "Georgia", size: 14)

        if let font = settlementFont {
            for settlement in engine.settlements {
                // Symbol prefix by type
                let prefix: String
                switch settlement.type {
                case .capital:  prefix = "★ "
                case .city:     prefix = "● "
                case .town:     prefix = "◆ "
                case .fortress: prefix = "▲ "
                case .port:     prefix = "⚓ "
                case .village:  prefix = "· "
                }
                let text = prefix + settlement.name
                let px = settlement.position.x * Float(bitmapSize)
                let py = settlement.position.y * Float(bitmapSize)

                drawLabel(
                    ctx: ctx,
                    text: text,
                    font: font,
                    color: inkColor,
                    centerX: CGFloat(px),
                    centerY: CGFloat(py) + 12,  // offset below dot position
                    rotation: 0,
                    occupied: &occupied,
                    gridCols: gridCols,
                    gridRows: gridRows,
                    cellW: cellW,
                    cellH: cellH,
                    bitmapSize: CGFloat(bitmapSize)
                )
            }
        }

        // -----------------------------------------------------------------------
        // Upload bitmap to MTLTexture
        // -----------------------------------------------------------------------
        guard
            let cgImage = ctx.makeImage(),
            let dataProvider = cgImage.dataProvider,
            let rawData = dataProvider.data
        else {
            print("[LabelPass] ERROR: could not extract bitmap data")
            return
        }

        let byteCount = CFDataGetLength(rawData)
        let bytePtr   = CFDataGetBytePtr(rawData)

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: bitmapSize,
            height: bitmapSize,
            mipmapped: false
        )
        texDesc.usage       = .shaderRead
        texDesc.storageMode = .managed

        guard let tex = device.makeTexture(descriptor: texDesc) else {
            print("[LabelPass] ERROR: could not create label texture")
            return
        }

        bytePtr?.withMemoryRebound(to: UInt8.self, capacity: byteCount) { ptr in
            tex.replace(
                region: MTLRegion(
                    origin: MTLOrigin(x: 0, y: 0, z: 0),
                    size: MTLSize(width: bitmapSize, height: bitmapSize, depth: 1)
                ),
                mipmapLevel: 0,
                withBytes: ptr,
                bytesPerRow: bitmapSize * 4
            )
        }

        labelTexture = tex
    }

    // MARK: - encode

    func encode(encoder: MTLRenderCommandEncoder, uniforms: inout Uniforms) {
        guard
            let pipeline    = pipeline,
            let texture     = labelTexture,
            let vertBuf     = quadVertexBuffer,
            let idxBuf      = quadIndexBuffer
        else { return }

        encoder.pushDebugGroup(label)
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertBuf, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: idxBuf,
            indexBufferOffset: 0
        )
        encoder.popDebugGroup()
    }

    // MARK: - Font Helpers

    private func registerBundledFonts() {
        let fontNames = ["IMFellEnglish-Regular", "CinzelDecorative-Regular"]
        for name in fontNames {
            guard
                let url = Bundle.main.url(
                    forResource: name,
                    withExtension: "ttf",
                    subdirectory: "Resources/Fonts"
                ) ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            else {
                print("[LabelPass] WARNING: font file not found: \(name).ttf")
                continue
            }
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            if !registered, let err = error {
                let cfError = err.takeRetainedValue()
                // CoreText returns 105 when a bundled font is already registered for this process.
                if CFErrorGetCode(cfError) == 105 {
                    continue
                }
                print("[LabelPass] WARNING: font registration failed for \(name): \(cfError)")
            }
        }
    }

    private func makeCTFont(name: String, size: CGFloat) -> CTFont? {
        let font = CTFontCreateWithName(name as CFString, size, nil)
        // Verify the font resolved (not a fallback generic)
        let actualName = CTFontCopyPostScriptName(font) as String
        // If the returned name is totally different, CoreText fell back to system default
        if actualName.lowercased().contains("helvetica") && !name.lowercased().contains("helvetica") {
            return nil
        }
        return font
    }

    // MARK: - Drawing Helpers

    private func drawLabel(
        ctx: CGContext,
        text: String,
        font: CTFont,
        color: CGColor,
        centerX: CGFloat,
        centerY: CGFloat,
        rotation: CGFloat,
        occupied: inout [Bool],
        gridCols: Int,
        gridRows: Int,
        cellW: CGFloat,
        cellH: CGFloat,
        bitmapSize: CGFloat
    ) {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName:            font,
            kCTForegroundColorAttributeName: color
        ]

        let attrStr = CFAttributedStringCreate(
            nil,
            text as CFString,
            attrs as CFDictionary
        )!
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetImageBounds(line, ctx)
        let lineW = bounds.width
        let lineH = bounds.height

        // Overlap grid check
        let gx0 = max(0, Int((centerX - lineW / 2) / cellW))
        let gy0 = max(0, Int((centerY - lineH / 2) / cellH))
        let gx1 = min(gridCols - 1, Int((centerX + lineW / 2) / cellW))
        let gy1 = min(gridRows - 1, Int((centerY + lineH / 2) / cellH))

        for gy in gy0...gy1 {
            for gx in gx0...gx1 {
                let idx = gy * gridCols + gx
                guard idx < occupied.count else { continue }
                if occupied[idx] { return }
            }
        }

        // Mark cells as occupied
        for gy in gy0...gy1 {
            for gx in gx0...gx1 {
                let idx = gy * gridCols + gx
                if idx < occupied.count { occupied[idx] = true }
            }
        }

        // Draw with optional rotation
        ctx.saveGState()
        ctx.translateBy(x: centerX, y: centerY)
        if abs(rotation) > 1e-6 {
            ctx.rotate(by: rotation)
        }
        // CoreText text origin is at the baseline-left; offset so text is centred
        ctx.textPosition = CGPoint(x: -lineW / 2, y: -lineH / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
