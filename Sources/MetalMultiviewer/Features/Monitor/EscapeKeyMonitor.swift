import AppKit
import SwiftUI

/// Local Escape handler — SwiftUI `.onExitCommand` does not fire when an `NSViewRepresentable` has focus.
@MainActor
final class EscapeKeyMonitor {
    private var monitor: Any?
    private weak var model: MonitorAppModel?

    private var windowRole: MonitorWindowRole = .single

    func install(model: MonitorAppModel, windowRole: MonitorWindowRole) {
        self.model = model
        self.windowRole = windowRole
        guard monitor == nil else { return }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            guard let self, let model = self.model else { return event }
            guard !model.dualMonitorMode else { return event }
            guard windowRole == .single else { return event }
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
    let windowRole: MonitorWindowRole
    @State private var keyMonitor = EscapeKeyMonitor()

    func body(content: Content) -> some View {
        content
            .onAppear { keyMonitor.install(model: model, windowRole: windowRole) }
            .onDisappear { keyMonitor.uninstall() }
    }
}

extension View {
    func escapeReturnsToFourUp(model: MonitorAppModel, windowRole: MonitorWindowRole = .single) -> some View {
        modifier(EscapeKeyMonitorModifier(model: model, windowRole: windowRole))
    }
}
