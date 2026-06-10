import SwiftUI

struct GridDividerRepresentable: NSViewRepresentable {
    let gridLayout: GridLayout
    let split: GridSplit
    let isVisible: Bool
    let onSplitChanged: (GridSplit, Bool) -> Void

    func makeNSView(context: Context) -> GridDividerHostView {
        let host = GridDividerHostView()
        let overlay = GridDividerOverlay { split, isDragEnd in
            onSplitChanged(split, isDragEnd)
        }
        overlay.updateLayout(grid: gridLayout, split: split)
        overlay.isHidden = !isVisible
        host.overlay = overlay
        host.addSubview(overlay)
        return host
    }

    func updateNSView(_ nsView: GridDividerHostView, context: Context) {
        guard let overlay = nsView.overlay else { return }
        overlay.isHidden = !isVisible
        overlay.updateLayout(grid: gridLayout, split: split)
        overlay.frame = nsView.bounds
    }
}

/// Forwards hits only to divider lines so cell taps reach SwiftUI below.
@MainActor
final class GridDividerHostView: NSView {
    var overlay: GridDividerOverlay?

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        overlay?.frame = bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let overlay else { return nil }
        let local = convert(point, to: overlay)
        return overlay.hitTest(local)
    }
}
