import SwiftUI
import MetalKit

struct ContentView: View {
    @State private var renderer = MapRenderer()
    @State private var engine = TerrainEngine()
    @State private var params = WorldParameters()

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

    private func generate() {
        engine.runFullPipeline(params: params)
    }

    private func updateRendererTexture() {
        let rgba = engine.debugTextureDataRGBA()
        renderer.updateDebugTexture(from: rgba, width: 1024, height: 1024)
    }
}
