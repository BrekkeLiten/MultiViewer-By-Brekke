import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: MonitorAppModel?
    private var didSetup = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppBranding.installApplicationName()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppBranding.installApplicationName()
    }

    func attach(model: MonitorAppModel) {
        self.model = model
        guard !didSetup else { return }
        didSetup = true
        AppBranding.installApplicationIcon()
        model.finishLaunchSetup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
