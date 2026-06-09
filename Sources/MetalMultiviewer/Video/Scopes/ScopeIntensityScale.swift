import Foundation

/// Waveform / parade intensity scale in IRE with broadcast headroom/footroom.
enum ScopeIntensityScale {
    static let ireMin = -20
    static let ireMax = 120
    static let ireSpan: Float = Float(ireMax - ireMin)

    /// Tick labels top → bottom (120 IRE at top, −20 at bottom).
    static let ireTickValues: [Int] = [120, 100, 80, 60, 40, 20, 0, -20]

    /// Position on the graph: 0 = top (120 IRE), 1 = bottom (−20 IRE).
    static func displayFractionFromTop(ire: Int) -> Float {
        Float(ireMax - min(max(ire, ireMin), ireMax)) / ireSpan
    }

    /// Legal signal peaks: 0…1 display-referred RGB maps to 0…100 IRE (not 120).
    static let signalPeakIRE = 100

    /// Map a normalized signal sample (0 = black, 1 = peak white) to an IRE value.
    static func ireForSignalValue(_ value: Float) -> Float {
        min(max(value, 0), 1) * Float(signalPeakIRE)
    }

    /// Graph Y fraction (0 = top) for a normalized signal sample.
    static func displayFractionFromSignalValue(_ value: Float) -> Float {
        displayFractionFromTop(ire: Int(ireForSignalValue(value).rounded(.down)))
    }

    /// Left column for IRE tick numerals (−20 is widest).
    static let labelColumnWidthPx: Float = 30

    /// Clear gap between numerals and the trace area.
    static let labelGraphGapPx: Float = 6

    /// Total left inset before the waveform / parade trace begins.
    static var traceLeftInsetPx: Float { labelColumnWidthPx + labelGraphGapPx }

    /// AppKit overlay insets matching `ScopePanelLabelOverlay` scale rail layout.
    static let scaleTopInsetPx: Float = 28
    static let scaleBottomInsetPx: Float = 4

    /// Scope panel titles sit just below the 120 IRE graticule (top of scale rail + gap).
    static let scopeTitleTopInsetPx: Float = scaleTopInsetPx + 8

    /// Pixels from the left edge of the label column to the numeral origin.
    static let labelColumnPaddingPx: Float = 2

    /// Pixels below a graticule line before the numeral top edge.
    static let labelBelowLinePx: Float = 2

    /// Left NDC inset for the trace quad (label column + gap).
    static func traceLeftInsetNDC(cellWidthNdc: Float, panelWidthPx: Float) -> Float {
        guard panelWidthPx > 1 else { return 0 }
        return (traceLeftInsetPx / panelWidthPx) * cellWidthNdc
    }
}
