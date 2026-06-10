import Foundation

final class AppState: @unchecked Sendable {
    enum LayoutMode: Int, Codable {
        case oneUp = 1
        case fourUp = 4
    }

    enum SourceRef: Equatable, Codable {
        case ndi(name: String)
        case sdi(index: Int)

        var persistenceString: String {
            switch self {
            case let .ndi(name): return "ndi:\(name)"
            case let .sdi(index): return "sdi:\(index)"
            }
        }
    }

    struct Snapshot: Equatable {
        var layout: LayoutMode
        var slots: [Int: SourceRef]
        var primarySlot: Int
        var gridLayout: GridLayout
        var gridSplit: GridSplit
        var dualMonitorMode: Bool
    }

    private let queue = DispatchQueue(label: "MetalMultiviewer.AppState")
    private var snapshot = Snapshot(
        layout: .fourUp,
        slots: [:],
        primarySlot: 1,
        gridLayout: .default2x2,
        gridSplit: .equal(columns: 2, rows: 2),
        dualMonitorMode: false
    )

    func get() -> Snapshot {
        queue.sync { snapshot }
    }

    func setLayout(_ mode: LayoutMode) {
        queue.sync { snapshot.layout = mode }
    }

    func setGridLayout(_ grid: GridLayout) {
        queue.sync {
            snapshot.gridLayout = grid
            snapshot.gridSplit = snapshot.gridSplit.resized(for: grid)
        }
    }

    func setGridSplit(_ split: GridSplit) {
        queue.sync { snapshot.gridSplit = split }
    }

    func setDualMonitorMode(_ enabled: Bool) {
        queue.sync { snapshot.dualMonitorMode = enabled }
    }

    /// Slot shown fullscreen in **1-up** (`1 ... maxSlots`); clamps if out of range.
    func setPrimarySlot(_ slot: Int) {
        let clamped = min(max(slot, 1), MultiviewLimits.maxSlots)
        queue.sync { snapshot.primarySlot = clamped }
    }

    func setSource(slot: Int, source: SourceRef?) throws {
        guard (1 ... MultiviewLimits.maxSlots).contains(slot) else {
            throw AppStateError.invalidSlot
        }
        queue.sync {
            if let source {
                snapshot.slots[slot] = source
            } else {
                snapshot.slots.removeValue(forKey: slot)
            }
        }
    }
}

enum AppStateError: Error {
    case invalidSlot
    case invalidGrid
}
