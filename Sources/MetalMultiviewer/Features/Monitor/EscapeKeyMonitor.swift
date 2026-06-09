import AppKit
import SwiftUI

/// Local Escape handler — SwiftUI `.onExitCommand` does not fire when an `NSViewRepresentable` has focus.
@MainActor
final class EscapeKeyMonitor {
    private var monitor: Any?
    private weak var model: MonitorAppModel?

    func install(model: MonitorAppModel) {
        self.model = model
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self, let model = self.model else { return event }
            guard model.layout == .oneUp else { return event }
            if NSApp.keyWindow?.attachedSheet != nil { return event }
            model.setLayout(.fourUp)
            return nil
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        model = nil
    }
}

private struct EscapeKeyMonitorModifier: ViewModifier {
    @Bindable var model: MonitorAppModel
    @State private var keyMonitor = EscapeKeyMonitor()

    func body(content: Content) -> some View {
        content
            .onAppear { keyMonitor.install(model: model) }
            .onDisappear { keyMonitor.uninstall() }
    }
}

extension View {
    func escapeReturnsToFourUp(model: MonitorAppModel) -> some View {
        modifier(EscapeKeyMonitorModifier(model: model))
    }
}
