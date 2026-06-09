import SwiftUI

/// Shared broadcast-monitor design tokens for SwiftUI chrome.
enum MonitorDesign {
    static let canvasBackground = Color(red: 0.04, green: 0.04, blue: 0.04)
    static let panelDivider = Color.white.opacity(0.12)
    static let badgeBackground = Color.black.opacity(0.70)
    static let badgeCornerRadius: CGFloat = 6
    static let badgeFontSize: CGFloat = 11
    static let statusNoSignal = Color(red: 1, green: 0.45, blue: 0.45)
    static let statusNoSource = Color(white: 0.55)
    static let hoverTint = Color.white.opacity(0.08)
    static let toolbarGroupSpacing: CGFloat = 8
    static let toolbarSectionSpacing: CGFloat = 12
    static let formMargin: CGFloat = 20
    static let panelHeaderInset: CGFloat = 8
    static let scopeCaption = Color(
        red: ScopeMonitorLayout.ResolveStyle.captionGray.red,
        green: ScopeMonitorLayout.ResolveStyle.captionGray.green,
        blue: ScopeMonitorLayout.ResolveStyle.captionGray.blue,
        opacity: ScopeMonitorLayout.ResolveStyle.captionAlpha
    )
    static let scopeTargetLetter = Color(
        red: ScopeMonitorLayout.ResolveStyle.captionGray.red,
        green: ScopeMonitorLayout.ResolveStyle.captionGray.green,
        blue: ScopeMonitorLayout.ResolveStyle.captionGray.blue,
        opacity: ScopeMonitorLayout.ResolveStyle.targetLetterAlpha
    )
    static let scopeScaleNumeral = Color(red: 0.82, green: 0.62, blue: 0.38, opacity: 0.95)
}
