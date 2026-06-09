import SwiftUI

struct ScopeDividerRepresentable: NSViewRepresentable {
    let split: ScopeMonitorSplit
    let isVisible: Bool
    let onSplitChanged: (ScopeMonitorSplit, Bool) -> Void

    func makeNSView(context: Context) -> ScopeDividerOverlay {
        let view = ScopeDividerOverlay { split, isDragEnd in
            onSplitChanged(split, isDragEnd)
        }
        view.updateLayout(split: split)
        view.isHidden = !isVisible
        return view
    }

    func updateNSView(_ nsView: ScopeDividerOverlay, context: Context) {
        nsView.isHidden = !isVisible
        nsView.updateLayout(split: split)
    }
}
