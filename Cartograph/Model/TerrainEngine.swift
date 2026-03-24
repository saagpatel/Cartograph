import Foundation
import Observation
import simd

@Observable
class TerrainEngine {
    var heightMap = HeightMap()
    var biomeMap: BiomeMap?
    var riverNodes: [RiverNode] = []
    var settlements: [Settlement] = []
    var isGenerating = false
    var progress: Double = 0

    func generateWorld(seed: UInt64) {
        isGenerating = true
        progress = 0

        Task.detached { [self] in
            let noise = NoiseGenerator(seed: seed)
            let width = 1024
            let height = 1024
            var newData = [Float](repeating: 0, count: width * height)

            for y in 0..<height {
                for x in 0..<width {
                    let nx = Float(x) / 256.0
                    let ny = Float(y) / 256.0
                    let value = noise.fBm(x: nx, y: ny, octaves: 6, lacunarity: 2.0, gain: 0.5)
                    newData[y * width + x] = (value + 1.0) / 2.0
                }
            }

            await MainActor.run {
                self.heightMap.data = newData
                self.isGenerating = false
                self.progress = 1.0
            }
        }
    }
}
