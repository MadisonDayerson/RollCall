import MetalKit
import SwiftUI

/// Draws the fire as it is `time` seconds in; clear before it starts.
struct FireView: UIViewRepresentable {
    let fire: Fire
    let time: Double

    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: fire.device)
        v.colorPixelFormat = Fire.format
        v.isOpaque = false
        v.isPaused = true
        v.enableSetNeedsDisplay = true
        v.isUserInteractionEnabled = false
        v.delegate = context.coordinator
        return v
    }

    func updateUIView(_ v: MTKView, context: Context) {
        context.coordinator.time = time
        v.setNeedsDisplay()
    }

    func makeCoordinator() -> Artist { Artist(fire: fire) }

    final class Artist: NSObject, MTKViewDelegate {
        let fire: Fire
        var time = 0.0

        init(fire: Fire) { self.fire = fire }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard time >= 0, let drawable = view.currentDrawable else { return }
            fire.draw(at: time, into: drawable.texture) { $0.present(drawable) }
        }
    }
}
