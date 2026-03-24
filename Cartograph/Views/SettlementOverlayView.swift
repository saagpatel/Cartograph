import SwiftUI
import simd

// MARK: - SettlementOverlayView
//
// SwiftUI overlay drawn on top of MetalMapView.
// Renders settlement dots in screen-space using UV→screen coordinate mapping
// derived from the camera state.  Each dot supports:
//   • Tap  → popover with rename field, type picker, remove button
//   • Drag → reposition settlement (UV clamped to [0,1])

struct SettlementOverlayView: View {

    @Binding var settlements: [Settlement]
    let camera: CameraState

    @State private var selectedID: UUID? = nil
    @State private var draggingID: UUID? = nil
    @State private var dragCurrentScreen: CGPoint = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Array(settlements.enumerated()), id: \.element.id) { idx, settlement in
                    let basePos = uvToScreen(settlement.position, size: geo.size)
                    let screenPos: CGPoint = {
                        if draggingID == settlement.id {
                            return dragCurrentScreen
                        }
                        return basePos
                    }()
                    let isSelected = selectedID == settlement.id

                    settlementDot(
                        settlement: settlement,
                        index: idx,
                        screenPos: screenPos,
                        isSelected: isSelected,
                        geoSize: geo.size
                    )
                }
            }
        }
        // Dismiss popover when clicking empty area
        .contentShape(Rectangle())
        .onTapGesture { selectedID = nil }
    }

    // MARK: - Dot view

    @ViewBuilder
    private func settlementDot(
        settlement: Settlement,
        index: Int,
        screenPos: CGPoint,
        isSelected: Bool,
        geoSize: CGSize
    ) -> some View {
        let dotSize: CGFloat = settlement.type == .capital ? 10 : 7
        let dotColor: Color = dotColor(for: settlement.type)

        ZStack {
            // Dot
            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)

            // Selection ring
            if isSelected {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: dotSize + 6, height: dotSize + 6)
            }
        }
        // Popover on tap (not on drag end)
        .popover(isPresented: Binding(
            get: { selectedID == settlement.id },
            set: { if !$0 { selectedID = nil } }
        ), arrowEdge: .bottom) {
            SettlementPopover(settlement: settlementBinding(id: settlement.id)) {
                // Remove
                settlements.removeAll { $0.id == settlement.id }
                selectedID = nil
            }
        }
        // Drag to reposition
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    draggingID = settlement.id
                    dragCurrentScreen = CGPoint(
                        x: uvToScreen(settlement.position, size: geoSize).x + value.translation.width,
                        y: uvToScreen(settlement.position, size: geoSize).y + value.translation.height
                    )
                }
                .onEnded { value in
                    if let i = settlements.firstIndex(where: { $0.id == settlement.id }) {
                        let finalScreen = CGPoint(
                            x: uvToScreen(settlement.position, size: geoSize).x + value.translation.width,
                            y: uvToScreen(settlement.position, size: geoSize).y + value.translation.height
                        )
                        let newUV = screenToUV(finalScreen, size: geoSize)
                        settlements[i].position = newUV
                    }
                    draggingID = nil
                }
        )
        // Tap to select (after drag guard)
        .onTapGesture {
            selectedID = settlement.id
        }
        .position(screenPos)
    }

    // MARK: - Binding helper

    private func settlementBinding(id: UUID) -> Binding<Settlement> {
        Binding(
            get: { settlements.first(where: { $0.id == id }) ?? Settlement(name: "", position: .zero, type: .village, placementScore: 0) },
            set: { newVal in
                if let i = settlements.firstIndex(where: { $0.id == id }) {
                    settlements[i] = newVal
                }
            }
        )
    }

    // MARK: - Coordinate conversion

    /// UV space (0–1) → SwiftUI screen point, accounting for camera pan/zoom.
    func uvToScreen(_ uv: SIMD2<Float>, size: CGSize) -> CGPoint {
        let scale = camera.zoom
        let outX = scale * (uv.x * 2 - 1 - camera.offset.x * 2)
        let outY = scale * (1 - 2 * uv.y - camera.offset.y * 2)
        let sx = CGFloat((outX + 1) / 2) * size.width
        let sy = CGFloat((1 - outY) / 2) * size.height
        return CGPoint(x: sx, y: sy)
    }

    /// SwiftUI screen point → UV space, inverse of uvToScreen.
    func screenToUV(_ point: CGPoint, size: CGSize) -> SIMD2<Float> {
        let outX = Float(point.x / size.width) * 2 - 1
        let outY = 1 - Float(point.y / size.height) * 2
        let scale = camera.zoom
        let uvX = (outX / scale + camera.offset.x * 2 + 1) / 2
        let uvY = (1 - outY / scale - camera.offset.y * 2) / 2
        return SIMD2(max(0, min(1, uvX)), max(0, min(1, uvY)))
    }

    // MARK: - Helpers

    private func dotColor(for type: Settlement.SettlementType) -> Color {
        switch type {
        case .capital:  return Color(red: 0.7, green: 0.1, blue: 0.1)
        case .city:     return Color(red: 0.2, green: 0.2, blue: 0.6)
        case .town:     return Color(red: 0.2, green: 0.45, blue: 0.2)
        case .fortress: return Color(red: 0.4, green: 0.25, blue: 0.1)
        case .port:     return Color(red: 0.1, green: 0.35, blue: 0.55)
        case .village:  return Color(red: 0.45, green: 0.4, blue: 0.3)
        }
    }
}

// MARK: - SettlementPopover

struct SettlementPopover: View {
    @Binding var settlement: Settlement
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Name", text: $settlement.name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Picker("Type", selection: $settlement.type) {
                ForEach(Settlement.SettlementType.allCases, id: \.self) { t in
                    Text(t.rawValue.capitalized).tag(t)
                }
            }
            .pickerStyle(.menu)

            Divider()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("Remove", systemImage: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }
}

// MARK: - SettlementType + CaseIterable

extension Settlement.SettlementType: CaseIterable {
    public static var allCases: [Settlement.SettlementType] {
        [.capital, .city, .town, .village, .port, .fortress]
    }
}
