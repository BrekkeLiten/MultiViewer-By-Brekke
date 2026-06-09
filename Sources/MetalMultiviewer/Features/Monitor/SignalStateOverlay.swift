import SwiftUI

struct SignalStateOverlay: View {
    let model: MonitorAppModel
    let size: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if model.layout == .fourUp {
                ForEach(1 ... 4, id: \.self) { slot in
                    panel(for: slot, frame: MultiviewSlotLayout.quadrantFrame(slot: slot, in: size))
                }
            } else {
                let frame = pictureFrame
                panel(for: model.primarySlot, frame: frame)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
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
