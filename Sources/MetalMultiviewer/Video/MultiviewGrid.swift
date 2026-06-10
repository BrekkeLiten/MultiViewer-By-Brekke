import CoreGraphics
import Foundation

enum MultiviewLimits {
    static let maxSlots = 16
}

/// Configurable multiview grid dimensions (columns × rows ≤ 16).
struct GridLayout: Equatable, Codable, Sendable {
    var columns: Int
    var rows: Int

    static let default2x2 = GridLayout(columns: 2, rows: 2)

    init(columns: Int, rows: Int) {
        self.columns = Self.clampColumns(columns)
        self.rows = Self.clampRows(rows, columns: self.columns)
    }

    var slotCount: Int {
        min(columns * rows, MultiviewLimits.maxSlots)
    }

    static func isValid(columns: Int, rows: Int) -> Bool {
        guard columns >= 1, rows >= 1 else { return false }
        guard columns <= MultiviewLimits.maxSlots, rows <= MultiviewLimits.maxSlots else { return false }
        return columns * rows <= MultiviewLimits.maxSlots
    }

    static func clampColumns(_ value: Int) -> Int {
        min(max(value, 1), MultiviewLimits.maxSlots)
    }

    static func clampRows(_ value: Int, columns: Int) -> Int {
        let maxRows = max(MultiviewLimits.maxSlots / max(columns, 1), 1)
        return min(max(value, 1), maxRows)
    }

    static func from(config: AppConfig?) -> GridLayout {
        let cols = config?.gridColumns ?? 2
        let rows = config?.gridRows ?? 2
        if config?.layout == 4 || config?.layout == nil {
            if config?.gridColumns == nil, config?.gridRows == nil {
                return .default2x2
            }
        }
        return GridLayout(columns: cols, rows: rows)
    }
}

/// Draggable row/column split fractions for multiview grid cells.
struct GridSplit: Equatable, Codable, Sendable {
    /// Cumulative column boundary fractions (length = columns - 1).
    var columnFractions: [Float]
    /// Cumulative row boundary fractions (length = rows - 1).
    var rowFractions: [Float]

    static let boundaryRange: ClosedRange<Float> = 0.15 ... 0.85

    static func equal(columns: Int, rows: Int) -> GridSplit {
        GridSplit(
            columnFractions: Self.equalFractions(count: max(columns - 1, 0)),
            rowFractions: Self.equalFractions(count: max(rows - 1, 0))
        )
    }

    init(columnFractions: [Float], rowFractions: [Float]) {
        self.columnFractions = columnFractions
        self.rowFractions = rowFractions
        if !columnFractions.isEmpty {
            self.columnFractions = Self.clampFractions(columnFractions, count: columnFractions.count)
        }
        if !rowFractions.isEmpty {
            self.rowFractions = Self.clampFractions(rowFractions, count: rowFractions.count)
        }
    }

    static func from(config: AppConfig?, grid: GridLayout) -> GridSplit {
        let expectedCols = max(grid.columns - 1, 0)
        let expectedRows = max(grid.rows - 1, 0)
        var split = equal(columns: grid.columns, rows: grid.rows)
        if let cols = config?.gridColumnSplits, cols.count == expectedCols {
            split.columnFractions = Self.clampFractions(cols, count: expectedCols)
        }
        if let rows = config?.gridRowSplits, rows.count == expectedRows {
            split.rowFractions = Self.clampFractions(rows, count: expectedRows)
        }
        return split
    }

    func resized(for grid: GridLayout) -> GridSplit {
        let expectedCols = max(grid.columns - 1, 0)
        let expectedRows = max(grid.rows - 1, 0)
        if columnFractions.count == expectedCols, rowFractions.count == expectedRows {
            return self
        }
        return Self.equal(columns: grid.columns, rows: grid.rows)
    }

    private static func equalFractions(count: Int) -> [Float] {
        guard count > 0 else { return [] }
        return (1 ... count).map { Float($0) / Float(count + 1) }
    }

    private static func clampFractions(_ values: [Float], count: Int) -> [Float] {
        guard count > 0 else { return [] }
        var result = equalFractions(count: count)
        for i in 0 ..< min(values.count, count) {
            let lo = i == 0 ? boundaryRange.lowerBound : max(result[i - 1] + 0.05, boundaryRange.lowerBound)
            let hi = i == count - 1 ? boundaryRange.upperBound : min(
                (i + 1 < values.count ? values[i + 1] : boundaryRange.upperBound) - 0.05,
                boundaryRange.upperBound
            )
            result[i] = min(max(values[i], lo), hi)
        }
        for i in 1 ..< count {
            result[i] = max(result[i], result[i - 1] + 0.05)
        }
        return result
    }
}

/// Grid geometry (AppKit top-left origin, y grows downward).
enum MultiviewSlotLayout {
    /// Maps a point in view bounds to slot 1…N, or nil when outside bounds.
    static func slotForPoint(
        _ point: CGPoint,
        columns: Int,
        rows: Int,
        split: GridSplit,
        in size: CGSize
    ) -> Int? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }

        let colBounds = columnBoundaries(columns: columns, split: split, width: size.width)
        let rowBounds = rowBoundaries(rows: rows, split: split, height: size.height)

        guard let col = indexInBoundaries(point.x, boundaries: colBounds),
              let row = indexInBoundaries(point.y, boundaries: rowBounds)
        else { return nil }

        let slot = row * columns + col + 1
        guard slot <= GridLayout(columns: columns, rows: rows).slotCount else { return nil }
        return slot
    }

    /// Pixel frame for `slot` (1-based) within `size`.
    static func cellFrame(
        slot: Int,
        columns: Int,
        rows: Int,
        split: GridSplit,
        in size: CGSize
    ) -> CGRect {
        guard slot >= 1, columns > 0, rows > 0 else { return .zero }
        let col = (slot - 1) % columns
        let row = (slot - 1) / columns
        guard row < rows else { return .zero }

        let colBounds = columnBoundaries(columns: columns, split: split, width: size.width)
        let rowBounds = rowBoundaries(rows: rows, split: split, height: size.height)

        let x = colBounds[col]
        let y = rowBounds[row]
        let w = colBounds[col + 1] - x
        let h = rowBounds[row + 1] - y
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// All cell frames for slots 1…slotCount.
    static func allCellFrames(
        columns: Int,
        rows: Int,
        split: GridSplit,
        in size: CGSize
    ) -> [CGRect] {
        let count = GridLayout(columns: columns, rows: rows).slotCount
        return (1 ... count).map { cellFrame(slot: $0, columns: columns, rows: rows, split: split, in: size) }
    }

    // MARK: - Backward-compatible 2×2 equal splits

    static func slotForPoint(_ point: CGPoint, in size: CGSize) -> Int? {
        slotForPoint(point, columns: 2, rows: 2, split: .equal(columns: 2, rows: 2), in: size)
    }

    static func quadrantFrame(slot: Int, in size: CGSize) -> CGRect {
        cellFrame(slot: slot, columns: 2, rows: 2, split: .equal(columns: 2, rows: 2), in: size)
    }

    // MARK: - NDC (Metal, y upward)

    struct NDCRegion {
        var minX: Float
        var maxX: Float
        var minY: Float
        var maxY: Float
    }

    /// NDC cell for grid position (col, row), 0-based.
    static func cellNDC(
        col: Int,
        row: Int,
        columns: Int,
        rows: Int,
        split: GridSplit
    ) -> NDCRegion {
        let colFracs = normalizedFractions(split.columnFractions, divisions: columns)
        let rowFracs = normalizedFractions(split.rowFractions, divisions: rows)

        let left = colFracs[col]
        let right = colFracs[col + 1]
        let topAppKit = rowFracs[row]
        let bottomAppKit = rowFracs[row + 1]

        // AppKit y-down → Metal NDC y-up
        return NDCRegion(
            minX: left * 2 - 1,
            maxX: right * 2 - 1,
            minY: 1 - bottomAppKit * 2,
            maxY: 1 - topAppKit * 2
        )
    }

    static func cellNDC(
        slot: Int,
        columns: Int,
        rows: Int,
        split: GridSplit
    ) -> NDCRegion {
        let col = (slot - 1) % columns
        let row = (slot - 1) / columns
        return cellNDC(col: col, row: row, columns: columns, rows: rows, split: split)
    }

    // MARK: - Private

    private static func columnBoundaries(columns: Int, split: GridSplit, width: CGFloat) -> [CGFloat] {
        boundaryPositions(divisions: columns, fractions: split.columnFractions, extent: width)
    }

    private static func rowBoundaries(rows: Int, split: GridSplit, height: CGFloat) -> [CGFloat] {
        boundaryPositions(divisions: rows, fractions: split.rowFractions, extent: height)
    }

    private static func boundaryPositions(divisions: Int, fractions: [Float], extent: CGFloat) -> [CGFloat] {
        let fracs = normalizedFractions(fractions, divisions: divisions)
        return fracs.map { CGFloat($0) * extent }
    }

    private static func normalizedFractions(_ fractions: [Float], divisions: Int) -> [Float] {
        guard divisions > 0 else { return [0, 1] }
        guard divisions > 1 else { return [0, 1] }
        var result = [Float](repeating: 0, count: divisions + 1)
        result[0] = 0
        result[divisions] = 1
        let expected = divisions - 1
        let source = fractions.count == expected ? fractions : GridSplit.equal(columns: divisions, rows: 1).columnFractions
        for i in 0 ..< expected {
            result[i + 1] = source[i]
        }
        return result
    }

    private static func indexInBoundaries(_ value: CGFloat, boundaries: [CGFloat]) -> Int? {
        guard boundaries.count >= 2 else { return nil }
        for i in 0 ..< boundaries.count - 1 {
            let lo = boundaries[i]
            let hi = boundaries[i + 1]
            let isLast = i == boundaries.count - 2
            if value >= lo && (value < hi || (isLast && value <= hi)) {
                return i
            }
        }
        return nil
    }
}
