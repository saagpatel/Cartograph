import SwiftUI
import MetalKit

struct MetalMapView: NSViewRepresentable {

    let renderer: MapRenderer

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

        return mtkView
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(renderer: renderer)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject {
        let renderer: MapRenderer

        init(renderer: MapRenderer) {
            self.renderer = renderer
        }

        @objc func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
            renderer.camera.zoom *= (1.0 + Float(gesture.magnification))
            renderer.camera.zoom  = max(0.5, min(8.0, renderer.camera.zoom))
            gesture.magnification = 0
            gesture.view?.needsDisplay = true
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
