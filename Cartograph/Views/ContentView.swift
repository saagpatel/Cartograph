import SwiftUI
import MetalKit

struct ContentView: View {
    @State private var renderer = MapRenderer()
    @State private var engine = TerrainEngine()

    var body: some View {
        MetalMapView(renderer: renderer)
            .onAppear {
                engine.generateWorld(seed: UInt64.random(in: 0...UInt64.max))
            }
            .onChange(of: engine.isGenerating) {
                if !engine.isGenerating {
                    renderer.updateHeightMapTexture(from: engine.heightMap)
                }
            }
    }
}
