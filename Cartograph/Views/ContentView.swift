import SwiftUI
import MetalKit
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var renderer = MapRenderer()
    @State private var engine   = TerrainEngine()
    @State private var params   = WorldParameters()

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
                MetalMapView(renderer: renderer)

                if engine.isGenerating {
                    ProgressOverlayView(
                        progress: engine.progress,
                        stageName: engine.stageName
                    )
                }
            }
        }
        .toolbar {
            Button("Export PNG") {
                exportPNG()
            }
            .disabled(engine.debugMode != .portolan || engine.isGenerating)
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
    }

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
