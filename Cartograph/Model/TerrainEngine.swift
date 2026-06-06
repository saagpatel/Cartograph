import Foundation
import Observation
import simd

// MARK: - Parameters

struct ErosionParameters {
    var particleCount: Int = 500_000
    var strength: Float = 0.3
}

struct WorldParameters {
    var tectonic = TectonicParameters()
    var erosion = ErosionParameters()
}

// MARK: - Engine

@Observable
class TerrainEngine {
    var heightMap = HeightMap()
    var biomeMap: BiomeMap?
    var riverNodes: [RiverNode] = []
    var settlements: [Settlement] = []
    var isGenerating = false
    var progress: Double = 0
    var stageName: String = ""
    var plateIndex: [Int] = []
    var moistureMap: [Float] = []
    var flowAccumulationMap: [Float] = []

    enum DebugMode: String, CaseIterable {
        case heightMap = "Height Map"
        case plateIndex = "Plates"
        case biomeMap = "Biomes"
        case moisture = "Moisture"
        case flowAccumulation = "Flow"
        case portolan = "Portolan"
    }
    var debugMode: DebugMode = .portolan

    // MARK: - Full Pipeline

    func runFullPipeline(params: WorldParameters) {
        guard !isGenerating else { return }
        isGenerating = true
        progress = 0
        stageName = "Generating plates..."

        let capturedParams = params

        Task.detached { [self] in
            // Stage 1: Tectonic (0.0 → 0.15)
            let (tecResult, plateIdx) = TectonicSimulator.run(params: capturedParams.tectonic)
            await MainActor.run {
                self.heightMap = tecResult
                self.plateIndex = plateIdx
                self.progress = 0.15
                self.stageName = "Eroding terrain..."
            }

            // Stage 2: Erosion (0.15 → 0.65)
            let erosionEngine = ErosionEngine()
            var erodedData = tecResult.data
            let batchCount = 10
            let particlesPerBatch = capturedParams.erosion.particleCount / batchCount

            for batch in 0..<batchCount {
                erodedData = erosionEngine.runBatch(
                    heightData: erodedData,
                    width: 1024,
                    height: 1024,
                    particleCount: particlesPerBatch,
                    erosionRate: capturedParams.erosion.strength,
                    seed: capturedParams.tectonic.seed + UInt64(batch),
                    batchIndex: batch
                )
                let batchProgress = 0.15 + (Double(batch + 1) / Double(batchCount)) * 0.50
                let snapshot = erodedData
                await MainActor.run {
                    self.heightMap.data = snapshot
                    self.progress = batchProgress
                }
            }

            await MainActor.run {
                self.stageName = "Tracing rivers..."
            }

            // Stage 3: Rivers (0.65 → 0.85)
            let seaLevel = capturedParams.tectonic.seaLevel
            let (riverNodes, flowMap) = RiverNetworkGenerator.generate(
                heightData: erodedData,
                width: 1024,
                height: 1024,
                seaLevel: seaLevel,
                seed: capturedParams.tectonic.seed
            )
            await MainActor.run {
                self.riverNodes = riverNodes
                self.flowAccumulationMap = flowMap
                self.progress = 0.85
                self.stageName = "Assigning biomes..."
            }

            // Stage 4: Climate (0.85 → 0.92)
            let (biomes, moisture) = ClimateModel.generate(
                heightData: erodedData,
                width: 1024,
                height: 1024,
                seaLevel: seaLevel,
                riverNodes: riverNodes
            )
            let finalHeightData = erodedData
            await MainActor.run {
                var finalMap = HeightMap()
                finalMap.data = finalHeightData
                finalMap.seaLevel = seaLevel
                self.heightMap = finalMap
                self.biomeMap = biomes
                self.moistureMap = moisture
                self.progress = 0.92
                self.stageName = "Placing settlements..."
            }

            // Stage 5: Settlements (0.92 → 1.0)
            let settlements = SettlementPlacer.place(
                heightData: erodedData,
                biomeData: biomes.data,
                riverNodes: riverNodes,
                width: 1024,
                height: 1024,
                seaLevel: seaLevel,
                plateCount: capturedParams.tectonic.plateCount,
                seed: capturedParams.tectonic.seed
            )
            await MainActor.run {
                self.settlements = settlements
                self.isGenerating = false
                self.progress = 1.0
                self.stageName = ""
            }
        }
    }

    // MARK: - Tectonic Only (backward compat)

    func runTectonicPass(params: TectonicParameters) {
        guard !isGenerating else { return }
        isGenerating = true
        progress = 0

        let capturedParams = params

        Task.detached { [self] in
            let (result, plateIdx) = TectonicSimulator.run(params: capturedParams)

            await MainActor.run {
                self.heightMap = result
                self.plateIndex = plateIdx
                self.isGenerating = false
                self.progress = 1.0
            }
        }
    }

    // MARK: - Debug Visualization

    func debugTextureDataRGBA() -> [UInt8] {
        let count = heightMap.width * heightMap.height
        var rgba = [UInt8](repeating: 0, count: count * 4)

        switch debugMode {
        case .heightMap:
            for i in 0..<count {
                let v = UInt8(clamping: Int(heightMap.data[i] * 255))
                rgba[i * 4] = v
                rgba[i * 4 + 1] = v
                rgba[i * 4 + 2] = v
                rgba[i * 4 + 3] = 255
            }
        case .plateIndex:
            guard !plateIndex.isEmpty else { return grayscaleFallback() }
            let maxIdx = Float(max(1, plateIndex.max() ?? 0))
            for i in 0..<count {
                let hue = Float(plateIndex[i]) / maxIdx
                let (r, g, b) = hsvToRGB(h: hue, s: 0.8, v: 1.0)
                rgba[i * 4] = UInt8(clamping: Int(r * 255))
                rgba[i * 4 + 1] = UInt8(clamping: Int(g * 255))
                rgba[i * 4 + 2] = UInt8(clamping: Int(b * 255))
                rgba[i * 4 + 3] = 255
            }
        case .biomeMap:
            guard let bm = biomeMap else { return grayscaleFallback() }
            for i in 0..<count {
                let isRiver = !flowAccumulationMap.isEmpty && flowAccumulationMap[i] > 0.3
                if isRiver {
                    rgba[i * 4] = 26
                    rgba[i * 4 + 1] = 31
                    rgba[i * 4 + 2] = 89
                    rgba[i * 4 + 3] = 255
                } else {
                    let color = BiomeMap.colorTable[bm.data[i]] ?? SIMD4<Float>(0, 0, 0, 1)
                    rgba[i * 4] = UInt8(clamping: Int(color.x * 255))
                    rgba[i * 4 + 1] = UInt8(clamping: Int(color.y * 255))
                    rgba[i * 4 + 2] = UInt8(clamping: Int(color.z * 255))
                    rgba[i * 4 + 3] = 255
                }
            }
        case .moisture:
            for i in 0..<count {
                let v = moistureMap.isEmpty ? UInt8(0) : UInt8(clamping: Int(moistureMap[i] * 255))
                rgba[i * 4] = v
                rgba[i * 4 + 1] = v
                rgba[i * 4 + 2] = v
                rgba[i * 4 + 3] = 255
            }
        case .flowAccumulation:
            for i in 0..<count {
                let v = flowAccumulationMap.isEmpty ? UInt8(0) : UInt8(clamping: Int(flowAccumulationMap[i] * 255))
                rgba[i * 4] = v
                rgba[i * 4 + 1] = v
                rgba[i * 4 + 2] = v
                rgba[i * 4 + 3] = 255
            }
        case .portolan:
            // Portolan mode is rendered entirely on the GPU; return a blank buffer.
            // The renderer will not call this path when debugMode == .portolan.
            break
        }
        return rgba
    }

    private func grayscaleFallback() -> [UInt8] {
        let count = heightMap.width * heightMap.height
        var rgba = [UInt8](repeating: 0, count: count * 4)
        for i in 0..<count {
            let v = UInt8(clamping: Int(heightMap.data[i] * 255))
            rgba[i * 4] = v; rgba[i * 4 + 1] = v; rgba[i * 4 + 2] = v; rgba[i * 4 + 3] = 255
        }
        return rgba
    }

    private func hsvToRGB(h: Float, s: Float, v: Float) -> (Float, Float, Float) {
        let c = v * s
        let x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0))
        let m = v - c
        let (r1, g1, b1): (Float, Float, Float)
        switch Int(h * 6.0) % 6 {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }
        return (r1 + m, g1 + m, b1 + m)
    }
}
