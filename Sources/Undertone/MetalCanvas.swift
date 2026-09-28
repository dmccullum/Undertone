import MetalKit
import SwiftUI

/// The canvas preview on the GPU: the same kernel as export, written straight into the view's drawable
/// at full Retina resolution. It draws only when the recipe or size changes. The layer is tagged sRGB,
/// so the preview shows exactly the colors an export contains, on any display.
struct MetalCanvas: NSViewRepresentable {
    let recipe: GradientRecipe
    let renderer: MetalRenderer

    func makeCoordinator() -> Coordinator { Coordinator(renderer: renderer) }

    func makeNSView(context: Context) -> MTKView {
        let view = PassthroughMetalView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        // The kernel writes into the drawable directly.
        view.framebufferOnly = false
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.autoResizeDrawable = true
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        context.coordinator.recipe = recipe
        return view
    }

    func updateNSView(_ view: MTKView, context: Context) {
        guard context.coordinator.recipe != recipe else { return }
        context.coordinator.recipe = recipe
        view.needsDisplay = true
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        let renderer: MetalRenderer
        var recipe: GradientRecipe?

        init(renderer: MetalRenderer) { self.renderer = renderer }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { view.needsDisplay = true }

        func draw(in view: MTKView) {
            guard let recipe, let drawable = view.currentDrawable, let commands = renderer.makeCommandBuffer(),
                  let scene = try? GradientRenderer.Scene(recipe, width: drawable.texture.width, height: drawable.texture.height),
                  (try? renderer.encodePreview(scene, into: drawable.texture, on: commands)) != nil else { return }
            commands.present(drawable)
            commands.commit()
        }
    }
}

/// Leaves mouse events to the SwiftUI handles, drag source and focus above it.
private final class PassthroughMetalView: MTKView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
