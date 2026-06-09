import AppKit
import MetalKit
import SwiftUI

struct MetalCanvasView: NSViewRepresentable {
    let coordinator: MetalRenderCoordinator

    func makeCoordinator() -> Coordinator {
        Coordinator(coordinator: coordinator)
    }

    func makeNSView(context: Context) -> NSView {
        let container = MetalCanvasContainerView()
        let renderCoordinator = context.coordinator.coordinator
        container.onLayout = {
            Task { @MainActor in
                renderCoordinator.noteViewportSizeChanged()
            }
        }
        let mtkView = coordinator.mtkView
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            mtkView.topAnchor.constraint(equalTo: container.topAnchor),
            mtkView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        coordinator.requestDisplay()
    }

    final class Coordinator {
        let coordinator: MetalRenderCoordinator

        init(coordinator: MetalRenderCoordinator) {
            self.coordinator = coordinator
        }
    }
}

/// Host view that tracks SwiftUI layout size and forwards drawable updates to Metal.
private final class MetalCanvasContainerView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        guard let mtkView = subviews.first as? MTKView else { return }
        let scale = mtkView.window?.backingScaleFactor ?? 1
        let newSize = CGSize(
            width: max(bounds.width * scale, 1),
            height: max(bounds.height * scale, 1)
        )
        if mtkView.drawableSize != newSize {
            mtkView.drawableSize = newSize
            mtkView.setNeedsDisplay(mtkView.bounds)
            onLayout?()
        }
    }
}
