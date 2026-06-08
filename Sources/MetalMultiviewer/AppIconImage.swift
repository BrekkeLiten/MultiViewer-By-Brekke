import AppKit

enum AppIconImage {
    /// macOS Big Sur+ app icon corner radius as a fraction of side length.
    private static let cornerRadiusFraction: CGFloat = 0.2237

    @MainActor
    static func loadMaskedApplicationIcon() -> NSImage? {
        guard let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
              let source = NSImage(contentsOf: url) else {
            return nil
        }
        return applyApplicationIconMask(to: source)
    }

    /// Clips a square icon to a squircle-like shape with transparent corners (Dock-style).
    @MainActor
    static func applyApplicationIconMask(to source: NSImage) -> NSImage {
        let side = max(source.size.width, source.size.height)
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        let pixels = Int(side.rounded())

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return source
        }
        rep.size = bounds.size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.set()
        bounds.fill()

        let radius = side * cornerRadiusFraction
        let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        clip.addClip()
        source.draw(
            in: bounds,
            from: NSRect(origin: .zero, size: source.size),
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: false,
            hints: nil
        )
        NSGraphicsContext.restoreGraphicsState()

        let masked = NSImage(size: bounds.size)
        masked.addRepresentation(rep)
        return masked
    }
}
