import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var renderer = MapRenderer()
    @State private var engine   = TerrainEngine()
    @State private var params   = WorldParameters()
    @State private var renderRevision = 0

    var body: some View {
        NavigationSplitView {
            SidebarView(
                params: $params,
                debugMode: $engine.debugMode,
                isGenerating: engine.isGenerating,
                onGenerate: { generate() }
            )
        } detail: {
            ZStack {
                MetalMapView(renderer: renderer, redrawRevision: renderRevision) { uv in
                    addSettlement(at: uv)
                }

                // Settlement dots overlay (portolan mode only)
                if engine.debugMode == .portolan && !engine.isGenerating {
                    SettlementOverlayView(
                        settlements: $engine.settlements,
                        camera: renderer.camera
                    )
                    .allowsHitTesting(true)
                }

                if engine.isGenerating {
                    ProgressOverlayView(
                        progress: engine.progress,
                        stageName: engine.stageName
                    )
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Save") {
                    saveDocument()
                }
                .disabled(engine.isGenerating)

                Button("Open") {
                    openDocument()
                }
                .disabled(engine.isGenerating)

                Divider()

                Button("Export PNG") {
                    exportPNG()
                }
                .disabled(engine.debugMode != .portolan || engine.isGenerating)
            }
        }
        .onAppear {
            params.tectonic.seed = UInt64.random(in: 0...UInt64.max)
            generate()
        }
        .onChange(of: engine.isGenerating) {
            if !engine.isGenerating {
                updateRendererTexture()
            }
        }
        .onChange(of: engine.debugMode) {
            if !engine.isGenerating {
                updateRendererTexture()
            }
        }
        .onChange(of: engine.progress) {
            if engine.isGenerating {
                updateRendererTexture()
            }
        }
    }

    // MARK: - Actions

    private func generate() {
        engine.runFullPipeline(params: params)
    }

    private func updateRendererTexture() {
        if engine.debugMode == .portolan {
            renderer.renderMode = .portolan
            renderer.preparePasses(engine: engine)
        } else {
            renderer.renderMode = .debug
            let rgba = engine.debugTextureDataRGBA()
            renderer.updateDebugTexture(from: rgba, width: 1024, height: 1024)
        }
        renderRevision &+= 1
    }

    // MARK: - Settlement add (Cmd+Click)

    private func addSettlement(at uv: SIMD2<Float>) {
        guard engine.debugMode == .portolan, !engine.isGenerating else { return }
        let i = engine.settlements.count + 1
        engine.settlements.append(Settlement(
            name: "Settlement_\(i)",
            position: uv,
            type: .village,
            placementScore: 0
        ))
        // Rebuild label pass to include new settlement
        renderer.preparePasses(engine: engine)
        renderRevision &+= 1
    }

    // MARK: - Save / Load

    private func saveDocument() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cartograph") ?? .folder]
        panel.nameFieldStringValue = "MyWorld.cartograph"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await performSave(to: url)
            }
        }
    }

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cartograph") ?? .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await performLoad(from: url)
            }
        }
    }

    @MainActor
    private func performSave(to url: URL) async {
        let metadata = CartographDocumentData(
            seed: params.tectonic.seed,
            plateCount: params.tectonic.plateCount,
            seaLevel: params.tectonic.seaLevel,
            erosionParticleCount: params.erosion.particleCount,
            erosionRate: params.erosion.strength,
            settlements: engine.settlements
        )
        // 512×512 preview: downsample 1024×1024 debug RGBA by 2×
        let preview = makePreviewRGBA()

        do {
            try CartographDocument.save(
                metadata: metadata,
                heightData: engine.heightMap.data,
                biomeData: engine.biomeMap?.data ?? [],
                riverNodes: engine.riverNodes,
                previewRGBA: preview,
                to: url
            )
        } catch {
            print("[ContentView] Save failed: \(error)")
        }
    }

    @MainActor
    private func performLoad(from url: URL) async {
        do {
            let result = try CartographDocument.load(from: url)
            // Restore params
            params.tectonic.seed = result.metadata.seed
            params.tectonic.plateCount = result.metadata.plateCount
            params.tectonic.seaLevel = result.metadata.seaLevel
            params.erosion.particleCount = result.metadata.erosionParticleCount
            params.erosion.strength = result.metadata.erosionRate
            // Restore engine state
            var hm = HeightMap()
            hm.data = result.heightData
            hm.seaLevel = result.metadata.seaLevel
            engine.heightMap = hm
            if !result.biomeData.isEmpty {
                var bm = BiomeMap()
                bm.data = result.biomeData
                engine.biomeMap = bm
            }
            engine.riverNodes = result.riverNodes
            engine.settlements = result.metadata.settlements
            engine.debugMode = .portolan
            updateRendererTexture()
        } catch {
            print("[ContentView] Load failed: \(error)")
        }
    }

    private func makePreviewRGBA() -> [UInt8] {
        // Downsample 1024×1024 debug RGBA to 512×512 (2× box filter)
        let full = engine.debugTextureDataRGBA()
        let srcW = 1024, srcH = 1024
        let dstW = 512,  dstH = 512
        guard full.count == srcW * srcH * 4 else {
            return [UInt8](repeating: 180, count: dstW * dstH * 4)
        }
        var out = [UInt8](repeating: 0, count: dstW * dstH * 4)
        for y in 0..<dstH {
            for x in 0..<dstW {
                let sx = x * 2, sy = y * 2
                var r = 0, g = 0, b = 0, a = 0
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        let i = ((sy + dy) * srcW + (sx + dx)) * 4
                        r += Int(full[i]); g += Int(full[i+1])
                        b += Int(full[i+2]); a += Int(full[i+3])
                    }
                }
                let o = (y * dstW + x) * 4
                out[o] = UInt8(r / 4); out[o+1] = UInt8(g / 4)
                out[o+2] = UInt8(b / 4); out[o+3] = UInt8(a / 4)
            }
        }
        return out
    }

    // MARK: - Export PNG

    private func exportPNG() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "world_map.png"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    try? await ExportEngine.export(renderer: renderer, engine: engine, to: url)
                }
            }
        }
    }
}
