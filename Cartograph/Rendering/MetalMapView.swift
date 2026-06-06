import SwiftUI
import MetalKit

struct MetalMapView: NSViewRepresentable {

    let renderer: MapRenderer
    let redrawRevision: Int
    /// Called with a UV-space position when the user Cmd+Clicks on the canvas.
    var onCmdClick: ((SIMD2<Float>) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = renderer.device  // Use renderer's existing device
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        // Pinch-to-zoom
        let magnification = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnification(_:))
        )
        mtkView.addGestureRecognizer(magnification)

        // Pan
        let pan = NSPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        mtkView.addGestureRecognizer(pan)

        // Cmd+Click to add settlement
        let click = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleClick(_:))
        )
        mtkView.addGestureRecognizer(click)

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.onCmdClick = onCmdClick
        nsView.setNeedsDisplay(nsView.bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer, onCmdClick: onCmdClick)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let renderer: MapRenderer
        var onCmdClick: ((SIMD2<Float>) -> Void)?

        init(renderer: MapRenderer, onCmdClick: ((SIMD2<Float>) -> Void)?) {
            self.renderer = renderer
            self.onCmdClick = onCmdClick
        }

        @objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            renderer.camera.zoom *= (1.0 + Float(gesture.magnification))
            renderer.camera.zoom  = max(0.5, min(8.0, renderer.camera.zoom))
            gesture.magnification = 0
            gesture.view?.needsDisplay = true
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            // Only respond to Cmd+Click
            guard NSEvent.modifierFlags.contains(.command) else { return }
            guard let view = gesture.view else { return }
            let loc = gesture.location(in: view)
            let w = Float(view.bounds.width)
            let h = Float(view.bounds.height)
            // screen → NDC
            let ndcX = Float(loc.x) / w * 2 - 1
            let ndcY = 1 - Float(loc.y) / h * 2
            // NDC → pre-MVP clip → UV
            let scale = renderer.camera.zoom
            let uvX = (ndcX / scale + renderer.camera.offset.x * 2 + 1) / 2
            let uvY = (1 - ndcY / scale - renderer.camera.offset.y * 2) / 2
            let uv = SIMD2<Float>(max(0, min(1, uvX)), max(0, min(1, uvY)))
            onCmdClick?(uv)
        }

        @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            renderer.camera.offset.x += Float(translation.x) / Float(view.bounds.width) / renderer.camera.zoom
            renderer.camera.offset.y -= Float(translation.y) / Float(view.bounds.height) / renderer.camera.zoom
            renderer.camera.offset.x = max(-1.0, min(1.0, renderer.camera.offset.x))
            renderer.camera.offset.y = max(-1.0, min(1.0, renderer.camera.offset.y))
            gesture.setTranslation(.zero, in: view)
            view.needsDisplay = true
        }
    }
}
