import Foundation

/// Draggable 1-up scope monitor column / row split (persisted in config).
struct ScopeMonitorSplit: Equatable, Codable, Sendable {
    /// Left column width fraction (preview + waveform).
    var columnFraction: Float
    /// Top row height fraction (preview + vectorscope).
    var rowFraction: Float

    static let defaults = ScopeMonitorSplit(columnFraction: 0.64, rowFraction: 0.72)
    static let columnRange: ClosedRange<Float> = 0.30 ... 0.85
    static let rowRange: ClosedRange<Float> = 0.35 ... 0.90

    init(columnFraction: Float, rowFraction: Float) {
        self.columnFraction = Self.clamp(columnFraction, to: Self.columnRange)
        self.rowFraction = Self.clamp(rowFraction, to: Self.rowRange)
    }

    static func clamped(columnFraction: Float?, rowFraction: Float?) -> ScopeMonitorSplit {
        ScopeMonitorSplit(
            columnFraction: columnFraction ?? defaults.columnFraction,
            rowFraction: rowFraction ?? defaults.rowFraction
        )
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

/// NDC layout for 1-up scope monitor (picture-heavy top row + waveform row).
enum ScopeMonitorLayout {
    struct NDCRegion: Equatable {
        var minX: Float
        var maxX: Float
        var minY: Float
        var maxY: Float
    }

    struct Regions: Equatable {
        var picture: NDCRegion
        var vectorscope: NDCRegion
        var rgbWaveform: NDCRegion
        var rgbParade: NDCRegion
    }

    /// Vectorscope circle diameter as a fraction of its layout cell (square fit).
    static let vectorscopeDiameterFraction: Float = 0.92
    /// Vectorscope gain (1.0 = full field; >1 zooms into center chroma).
    static let vectorscopeZoom: Float = 1.0
    /// Inscribed chroma plot radius (leaves margin for the outer hue ring).
    static let vectorscopeDataEdge: Float = 0.86
    static let vectorscopeHueRingRadius: Float = 0.955

    static func regions(from split: ScopeMonitorSplit) -> Regions {
        let pictureMaxX = -1 + 2 * split.columnFraction
        let topRowMinY = 1 - 2 * split.rowFraction
        return Regions(
            picture: NDCRegion(minX: -1, maxX: pictureMaxX, minY: topRowMinY, maxY: 1),
            vectorscope: NDCRegion(minX: pictureMaxX, maxX: 1, minY: topRowMinY, maxY: 1),
            rgbWaveform: NDCRegion(minX: -1, maxX: pictureMaxX, minY: -1, maxY: topRowMinY),
            rgbParade: NDCRegion(minX: pictureMaxX, maxX: 1, minY: -1, maxY: topRowMinY)
        )
    }

    /// Resolve-style scope chrome (muted captions, faint graticule).
    enum ResolveStyle {
        static let captionGray = (red: CGFloat(0.55), green: CGFloat(0.55), blue: CGFloat(0.58))
        static let captionAlpha: CGFloat = 0.88
        static let targetLetterAlpha: CGFloat = 0.42
        static let vectorscopeTargetLetters = ["R", "Y", "G", "C", "B", "M"]
    }
}

/// Vectorscope circle + SMPTE label positions for AppKit overlays (top-left origin).
enum VectorscopeOverlayLayout {
    static let targetRadiusFraction = CGFloat(0.75 * ScopeMonitorLayout.vectorscopeDataEdge)

    static func circleRect(in containerBounds: CGRect, split: ScopeMonitorSplit) -> CGRect {
        let panelLeft = containerBounds.width * CGFloat(split.columnFraction)
        let panelW = containerBounds.width - panelLeft
        let panelH = containerBounds.height * CGFloat(split.rowFraction)
        let side = min(panelW, panelH) * CGFloat(ScopeMonitorLayout.vectorscopeDiameterFraction)
        let cx = panelLeft + panelW * 0.5
        let cy = panelH * 0.5
        return CGRect(x: cx - side * 0.5, y: cy - side * 0.5, width: side, height: side)
    }

    static func targetLabelCenter(in circleRect: CGRect, angle: Float, outward: CGFloat = 11) -> CGPoint {
        let r = min(circleRect.width, circleRect.height) * 0.5 * targetRadiusFraction
        let cx = circleRect.midX + CGFloat(cos(angle)) * r
        let cy = circleRect.midY - CGFloat(sin(angle)) * r
        let ox = CGFloat(cos(angle)) * outward
        let oy = -CGFloat(sin(angle)) * outward
        return CGPoint(x: cx + ox, y: cy + oy)
    }
}
