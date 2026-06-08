import AppKit

enum AppBranding {
    static let displayName = "MultiViewer by Brekke"

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
