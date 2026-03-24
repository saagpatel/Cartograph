import SwiftUI

struct SidebarView: View {
    @Binding var params: WorldParameters
    @Binding var debugMode: TerrainEngine.DebugMode
    var isGenerating: Bool
    var onGenerate: () -> Void

    var body: some View {
        Form {
            Section("Tectonic") {
                Slider(
                    value: Binding(
                        get: { Double(params.tectonic.plateCount) },
                        set: { params.tectonic.plateCount = Int($0) }
                    ),
                    in: 4...20,
                    step: 1
                ) {
                    Text("Plates: \(params.tectonic.plateCount)")
                }

                Slider(value: $params.tectonic.seaLevel, in: 0.25...0.50) {
                    Text("Sea Level: \(params.tectonic.seaLevel, specifier: "%.2f")")
                }

                Slider(value: $params.tectonic.mountainHeight, in: 0...1) {
                    Text("Mountains: \(params.tectonic.mountainHeight, specifier: "%.2f")")
                }

                Slider(value: $params.tectonic.noiseScale, in: 0...1) {
                    Text("Noise: \(params.tectonic.noiseScale, specifier: "%.2f")")
                }
            }

            Section("Erosion") {
                Slider(
                    value: Binding(
                        get: { Double(params.erosion.particleCount) },
                        set: { params.erosion.particleCount = Int($0) }
                    ),
                    in: 100_000...1_000_000,
                    step: 50_000
                ) {
                    Text("Iterations: \(params.erosion.particleCount / 1000)K")
                }

                Slider(value: $params.erosion.strength, in: 0.1...1.0) {
                    Text("Strength: \(params.erosion.strength, specifier: "%.1f")")
                }
            }

            Section("Debug") {
                Picker("View", selection: $debugMode) {
                    ForEach(TerrainEngine.DebugMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 220, maxWidth: 280)
        .safeAreaInset(edge: .bottom) {
            Button(action: onGenerate) {
                Text("Generate World")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isGenerating)
            .keyboardShortcut(.return, modifiers: .command)
            .padding()
        }
    }
}
