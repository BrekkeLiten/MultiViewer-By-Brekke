import AppKit

/// Draggable column / row dividers for multiview grid layout.
@MainActor
final class GridDividerOverlay: NSView {
    static let hitThickness: CGFloat = 14

    /// Shared hit test for SwiftUI overlays that sit beneath this view.
    static func isNearDivider(_ point: CGPoint, split: GridSplit, in size: CGSize) -> Bool {
        guard size.width > 4, size.height > 4 else { return false }
        let half = hitThickness * 0.5
        for frac in split.columnFractions {
            let x = CGFloat(frac) * size.width
            if abs(point.x - x) <= half { return true }
        }
        for frac in split.rowFractions {
            let y = CGFloat(frac) * size.height
            if abs(point.y - y) <= half { return true }
        }
        return false
    }

    private enum DragTarget {
        case column(Int)
        case row(Int)
    }

    private var gridLayout = GridLayout.default2x2
    private var split = GridSplit.equal(columns: 2, rows: 2)
    private var activeDrag: DragTarget?
    private let onSplitChanged: (GridSplit, Bool) -> Void

    init(onSplitChanged: @escaping (GridSplit, Bool) -> Void) {
        self.onSplitChanged = onSplitChanged
        super.init(frame: .zero)
        wantsLayer = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateLayout(grid: GridLayout, split: GridSplit) {
        gridLayout = grid
        self.split = split
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.001, bounds.contains(point) else { return nil }
        if dividerTarget(at: point) != nil { return self }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, bounds.width > 4, bounds.height > 4 else { return }
        let lineColor = NSColor(calibratedWhite: 0.55, alpha: 0.55)
        lineColor.setStroke()

        for i in 0 ..< split.columnFractions.count {
            let x = CGFloat(split.columnFractions[i]) * bounds.width
            let path = NSBezierPath()
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: bounds.height))
            path.lineWidth = 2
            path.stroke()
        }

        for i in 0 ..< split.rowFractions.count {
            let y = CGFloat(split.rowFractions[i]) * bounds.height
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y))
            path.line(to: NSPoint(x: bounds.width, y: y))
            path.lineWidth = 2
            path.stroke()
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !isHidden else { return }
        let half = Self.hitThickness * 0.5
        for frac in split.columnFractions {
            let x = CGFloat(frac) * bounds.width
            addCursorRect(
                NSRect(x: x - half, y: 0, width: Self.hitThickness, height: bounds.height),
                cursor: .resizeLeftRight
            )
        }
        for frac in split.rowFractions {
            let y = CGFloat(frac) * bounds.height
            addCursorRect(
                NSRect(x: 0, y: y - half, width: bounds.width, height: Self.hitThickness),
                cursor: .resizeUpDown
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        activeDrag = dividerTarget(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let target = activeDrag else { return }
        let point = convert(event.locationInWindow, from: nil)
        var next = split
        switch target {
        case let .column(index):
            guard index < next.columnFractions.count else { return }
            next.columnFractions[index] = Float(point.x / max(bounds.width, 1))
            next = GridSplit(
                columnFractions: next.columnFractions,
                rowFractions: next.rowFractions
            )
        case let .row(index):
            guard index < next.rowFractions.count else { return }
            next.rowFractions[index] = Float(point.y / max(bounds.height, 1))
            next = GridSplit(
                columnFractions: next.columnFractions,
                rowFractions: next.rowFractions
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

    private func dividerTarget(at point: NSPoint) -> DragTarget? {
        guard bounds.width > 4, bounds.height > 4 else { return nil }
        let half = Self.hitThickness * 0.5
        var bestCol: (Int, CGFloat)?
        for (i, frac) in split.columnFractions.enumerated() {
            let x = CGFloat(frac) * bounds.width
            let dist = abs(point.x - x)
            if dist <= half, bestCol == nil || dist < bestCol!.1 {
                bestCol = (i, dist)
            }
        }
        var bestRow: (Int, CGFloat)?
        for (i, frac) in split.rowFractions.enumerated() {
            let y = CGFloat(frac) * bounds.height
            let dist = abs(point.y - y)
            if dist <= half, bestRow == nil || dist < bestRow!.1 {
                bestRow = (i, dist)
            }
        }
        if let col = bestCol, let row = bestRow {
            return col.1 <= row.1 ? .column(col.0) : .row(row.0)
        }
        if let col = bestCol { return .column(col.0) }
        if let row = bestRow { return .row(row.0) }
        return nil
    }
}
