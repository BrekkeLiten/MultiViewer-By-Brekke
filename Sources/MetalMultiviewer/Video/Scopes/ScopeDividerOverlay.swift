import AppKit

/// Draggable column / row dividers for 1-up scope monitor layout.
@MainActor
final class ScopeDividerOverlay: NSView {
    static let hitThickness: CGFloat = 8

    private enum DragAxis {
        case column
        case row
    }

    private var split = ScopeMonitorSplit.defaults
    private var activeDrag: DragAxis?
    private let onSplitChanged: (ScopeMonitorSplit, Bool) -> Void

    init(onSplitChanged: @escaping (ScopeMonitorSplit, Bool) -> Void) {
        self.onSplitChanged = onSplitChanged
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateLayout(split: ScopeMonitorSplit) {
        self.split = split
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.001, bounds.contains(point) else { return nil }
        if dividerAxis(at: point) != nil { return self }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, bounds.width > 4, bounds.height > 4 else { return }
        let columnX = CGFloat(split.columnFraction) * bounds.width
        let rowY = CGFloat(split.rowFraction) * bounds.height
        let lineColor = NSColor(calibratedWhite: 0.42, alpha: 0.35)
        lineColor.setStroke()

        let vertical = NSBezierPath()
        vertical.move(to: NSPoint(x: columnX, y: 0))
        vertical.line(to: NSPoint(x: columnX, y: bounds.height))
        vertical.lineWidth = 1
        vertical.stroke()

        let horizontal = NSBezierPath()
        horizontal.move(to: NSPoint(x: 0, y: rowY))
        horizontal.line(to: NSPoint(x: bounds.width, y: rowY))
        horizontal.lineWidth = 1
        horizontal.stroke()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !isHidden else { return }
        let columnX = CGFloat(split.columnFraction) * bounds.width
        let rowY = CGFloat(split.rowFraction) * bounds.height
        let half = Self.hitThickness * 0.5
        addCursorRect(
            NSRect(x: columnX - half, y: 0, width: Self.hitThickness, height: bounds.height),
            cursor: .resizeLeftRight
        )
        addCursorRect(
            NSRect(x: 0, y: rowY - half, width: bounds.width, height: Self.hitThickness),
            cursor: .resizeUpDown
        )
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activeDrag = dividerAxis(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let axis = activeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        // Route through the clamping init so edge-drags can't produce invalid panel geometry.
        let next: ScopeMonitorSplit
        switch axis {
        case .column:
            next = ScopeMonitorSplit(
                columnFraction: Float(point.x / max(bounds.width, 1)),
                rowFraction: split.rowFraction
            )
        case .row:
            next = ScopeMonitorSplit(
                columnFraction: split.columnFraction,
                rowFraction: Float(point.y / max(bounds.height, 1))
            )
        }
        split = next
        onSplitChanged(next, false)
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard activeDrag != nil else { return }
        activeDrag = nil
        onSplitChanged(split, true)
    }

    private func dividerAxis(at point: NSPoint) -> DragAxis? {
        guard bounds.width > 4, bounds.height > 4 else { return nil }
        let columnX = CGFloat(split.columnFraction) * bounds.width
        let rowY = CGFloat(split.rowFraction) * bounds.height
        let half = Self.hitThickness * 0.5
        let onColumn = abs(point.x - columnX) <= half
        let onRow = abs(point.y - rowY) <= half
        if onColumn && onRow {
            return abs(point.x - columnX) >= abs(point.y - rowY) ? .column : .row
        }
        if onColumn { return .column }
        if onRow { return .row }
        return nil
    }
}

/// AppKit panel rects (top-left origin) for 1-up scope monitor overlays.
struct ScopeMonitorPanelFrames: Equatable {
    var picture: CGRect
    var vectorscope: CGRect
    var rgbWaveform: CGRect
    var rgbParade: CGRect

    static func from(split: ScopeMonitorSplit, size: CGSize) -> ScopeMonitorPanelFrames {
        let w = max(size.width, 1)
        let h = max(size.height, 1)
        let leftW = CGFloat(split.columnFraction) * w
        let topH = CGFloat(split.rowFraction) * h
        return ScopeMonitorPanelFrames(
            picture: CGRect(x: 0, y: 0, width: leftW, height: topH),
            vectorscope: CGRect(x: leftW, y: 0, width: w - leftW, height: topH),
            rgbWaveform: CGRect(x: 0, y: topH, width: leftW, height: h - topH),
            rgbParade: CGRect(x: leftW, y: topH, width: w - leftW, height: h - topH)
        )
    }
}
