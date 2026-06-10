import Foundation

/// Computes how many pixels each slot needs uploaded before GPU handoff (aspect-fit within layout cell).
enum DisplayUploadGeometry {
    enum Layout {
        case oneUp(primarySlot: Int)
        case oneUpScopeMonitor(primarySlot: Int, split: ScopeMonitorSplit)
        case grid(columns: Int, rows: Int, split: GridSplit)
    }

    /// Pixel size of the layout cell for `slot` (before aspect-fit of content).
    static func cellPixelSize(
        slot: Int,
        layout: Layout,
        viewportWidth: Int,
        viewportHeight: Int
    ) -> (width: Int, height: Int) {
        let vw = max(viewportWidth, 1)
        let vh = max(viewportHeight, 1)
        switch layout {
        case let .oneUp(primary):
            guard slot == primary else { return (0, 0) }
            return (vw, vh)
        case let .oneUpScopeMonitor(primary, split):
            guard slot == primary else { return (0, 0) }
            return (max(Int(Float(vw) * split.columnFraction), 1),
                    max(Int(Float(vh) * split.rowFraction), 1))
        case let .grid(columns, rows, split):
            let grid = GridLayout(columns: columns, rows: rows)
            guard slot >= 1, slot <= grid.slotCount else { return (0, 0) }
            let size = CGSize(width: CGFloat(vw), height: CGFloat(vh))
            let frame = MultiviewSlotLayout.cellFrame(
                slot: slot,
                columns: columns,
                rows: rows,
                split: split,
                in: size
            )
            return (max(Int(frame.width.rounded()), 1), max(Int(frame.height.rounded()), 1))
        }
    }

    /// Aspect-fit `contentWidthOverHeight` inside `cellWidth`×`cellHeight` (pixel units).
    static func aspectFitPixelSize(
        cellWidth: Int,
        cellHeight: Int,
        contentWidthOverHeight: Float?
    ) -> (width: Int, height: Int) {
        let cw = max(cellWidth, 0)
        let ch = max(cellHeight, 0)
        guard cw > 0, ch > 0 else { return (0, 0) }

        guard let ar = contentWidthOverHeight, ar > 0.001 else {
            return (snapEven(cw), snapEven(ch))
        }

        let cellAR = Float(cw) / Float(ch)
        let fitW: Int
        let fitH: Int
        if ar > cellAR {
            fitW = cw
            fitH = max(Int((Float(cw) / ar).rounded()), 1)
        } else {
            fitH = ch
            fitW = max(Int((Float(ch) * ar).rounded()), 1)
        }
        return (snapEven(fitW), snapEven(fitH))
    }

    /// Target upload size: fit to on-screen cell, never upscale above source, minimum 2×2 when visible.
    static func uploadPixelSize(
        sourceWidth: Int,
        sourceHeight: Int,
        cellWidth: Int,
        cellHeight: Int,
        contentWidthOverHeight: Float?
    ) -> (width: Int, height: Int) {
        guard cellWidth > 0, cellHeight > 0 else { return (0, 0) }
        guard sourceWidth > 0, sourceHeight > 0 else { return (0, 0) }

        let fit = aspectFitPixelSize(
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            contentWidthOverHeight: contentWidthOverHeight
        )
        guard fit.width > 0, fit.height > 0 else { return (0, 0) }

        var w = min(fit.width, sourceWidth)
        var h = min(fit.height, sourceHeight)
        w = max(snapEven(w), 2)
        h = max(snapEven(h), 2)
        w = min(w, sourceWidth)
        h = min(h, sourceHeight)
        return (w, h)
    }

    private static func snapEven(_ value: Int) -> Int {
        let v = max(value, 2)
        return v.isMultiple(of: 2) ? v : v - 1
    }
}
