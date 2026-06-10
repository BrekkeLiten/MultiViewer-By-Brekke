import SwiftUI

struct SignalStateOverlay: View {
    let model: MonitorAppModel
    let size: CGSize
    let windowRole: MonitorWindowRole

    var body: some View {
        ZStack(alignment: .topLeading) {
            if effectiveShowsGrid {
                ForEach(1 ... model.gridLayout.slotCount, id: \.self) { slot in
                    let frame = MultiviewSlotLayout.cellFrame(
                        slot: slot,
                        columns: model.gridLayout.columns,
                        rows: model.gridLayout.rows,
                        split: model.gridSplit,
                        in: size
                    )
                    panel(for: slot, frame: frame)
                }
            } else {
                panel(for: model.primarySlot, frame: pictureFrame)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private var effectiveShowsGrid: Bool {
        switch windowRole {
        case .multiview: return true
        case .program: return false
        case .single: return model.layout == .fourUp
        }
    }

    private var pictureFrame: CGRect {
        if model.oneUpScopeMonitorEnabled {
            return ScopeMonitorPanelFrames.from(split: model.scopeMonitorSplit, size: size).picture
        }
        return CGRect(origin: .zero, size: size)
    }

    @ViewBuilder
    private func panel(for slot: Int, frame: CGRect) -> some View {
        let status = model.signalStatus[slot] ?? .noSource
        if status != .live {
            ZStack {
                Color.black
                statusContent(for: status)
            }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(slot: slot, status: status))
        }
    }

    @ViewBuilder
    private func statusContent(for status: FeedSignalStatus) -> some View {
        switch status {
        case .live:
            EmptyView()
        case .noSource:
            VStack(spacing: 6) {
                Image(systemName: "rectangle.slash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MonitorDesign.statusNoSource)
                Text("NO SOURCE")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MonitorDesign.statusNoSource)
            }
        case .noSignal:
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(MonitorDesign.statusNoSignal)
                Text("NO SIGNAL")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MonitorDesign.statusNoSignal)
            }
        }
    }

    private func accessibilityText(slot: Int, status: FeedSignalStatus) -> String {
        switch status {
        case .live: "Slot \(slot) live"
        case .noSource: "Slot \(slot), no source assigned"
        case .noSignal: "Slot \(slot), no signal"
        }
    }
}
