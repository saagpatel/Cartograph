import SwiftUI

struct ProgressOverlayView: View {
    let progress: Double
    let stageName: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView(value: progress) {
                Text(stageName.isEmpty ? "Generating..." : stageName)
                    .font(.headline)
                    .fontWeight(.light)
            }
            .progressViewStyle(.linear)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 280)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
