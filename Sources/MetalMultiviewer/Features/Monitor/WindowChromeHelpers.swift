import AppKit
import SwiftUI

/// Sets the host window title; optional min size and activation for the main monitor window.
struct WindowChromeConfigurator: NSViewRepresentable {
    let title: String
    var minimumSize: NSSize?
    var activateOnAppear = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.title = title
            if let minimumSize {
                window.minSize = minimumSize
            }
            if activateOnAppear {
                window.makeKeyAndOrderFront(nil)
                NSRunningApplication.current.activate()
            }
        }
    }
}
