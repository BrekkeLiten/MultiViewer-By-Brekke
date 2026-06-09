import AppKit

enum AppBranding {
    static let displayName = "MultiViewer by Brekke"
    static let settingsWindowTitle = "\(displayName) Settings"

    /// Menu bar, About panel, and standard app-menu items when no `.app` bundle supplies Info.plist.
    @MainActor
    static func installApplicationName() {
        guard Bundle.main.bundleURL.pathExtension != "app" else { return }

        if let mainMenu = NSApp.mainMenu,
           let appMenuItem = mainMenu.items.first {
            appMenuItem.title = displayName
            appMenuItem.submenu?.items.forEach { updateStandardAppMenuItem($0) }
        }
    }

    @MainActor
    private static func updateStandardAppMenuItem(_ item: NSMenuItem) {
        switch item.action {
        case #selector(NSApplication.orderFrontStandardAboutPanel(_:)):
            item.title = "About \(displayName)"
        case #selector(NSApplication.hide(_:)):
            item.title = "Hide \(displayName)"
        case #selector(NSApplication.terminate(_:)):
            item.title = "Quit \(displayName)"
        default:
            break
        }
    }

    /// Dock icon when running via `swift run` (bare executable has no `.app` bundle icon).
    @MainActor
    static func installApplicationIcon() {
        // A bundled .app uses AppIcon.icns; macOS applies the squircle mask itself.
        if Bundle.main.bundleURL.pathExtension == "app" {
            return
        }
        guard let image = AppIconImage.loadMaskedApplicationIcon() else {
            return
        }
        NSApp.applicationIconImage = image
    }
}
