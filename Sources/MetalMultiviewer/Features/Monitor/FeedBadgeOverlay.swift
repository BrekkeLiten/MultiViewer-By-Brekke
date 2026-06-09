import SwiftUI

struct FeedBadgeOverlay: View {
    let model: MonitorAppModel
    let size: CGSize

    var body: some View {
        let snap = model.appState.get()
        let showScope = model.oneUpScopeMonitorEnabled && model.layout == .oneUp

        ZStack(alignment: .topLeading) {
            if model.layout == .oneUp {
                let slot = snap.primarySlot
                badge(for: slot, snap: snap, origin: previewBadgeOrigin(showScope: showScope), maxWidth: previewBadgeMaxWidth(showScope: showScope))
            } else {
                ForEach(1 ... 4, id: \.self) { slot in
                    let frame = MultiviewSlotLayout.quadrantFrame(slot: slot, in: size)
                    badge(for: slot, snap: snap, origin: CGPoint(x: frame.minX + 10, y: frame.minY + 10), maxWidth: badgeMaxWidth(for: slot, frame: frame))
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func previewBadgeOrigin(showScope: Bool) -> CGPoint {
        if showScope {
            let frames = ScopeMonitorPanelFrames.from(split: model.scopeMonitorSplit, size: size)
            return CGPoint(x: frames.picture.minX + 8, y: frames.picture.minY + 26)
        }
        return CGPoint(x: 10, y: 10)
    }

    private func previewBadgeMaxWidth(showScope: Bool) -> CGFloat {
        if showScope {
            return 280
        }
        return min(size.width - 20, 400)
    }

    private func badgeMaxWidth(for slot: Int, frame: CGRect) -> CGFloat {
        switch slot {
        case 1, 3:
            return max(size.width * 0.5 - 18, 60)
        default:
            return max(frame.width - 20, 60)
        }
    }

    @ViewBuilder
    private func badge(for slot: Int, snap: AppState.Snapshot, origin: CGPoint, maxWidth: CGFloat) -> some View {
        let dims = model.feedDimensions
        let text = SourceDisplayLabels.multiviewBadgeText(
            slot: slot,
            sourcePersistenceString: snap.slots[slot]?.persistenceString,
            pixelWidth: dims[slot]?.width ?? 0,
            pixelHeight: dims[slot]?.height ?? 0
        )
        let hasSource = snap.slots[slot] != nil

        Text(text)
            .font(.system(size: MonitorDesign.badgeFontSize, weight: .semibold, design: .monospaced))
            .foregroundStyle(hasSource ? Color.white : Color.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MonitorDesign.badgeBackground, in: RoundedRectangle(cornerRadius: MonitorDesign.badgeCornerRadius, style: .continuous))
            .frame(maxWidth: maxWidth, alignment: .leading)
            .fixedSize(horizontal: true, vertical: true)
            .offset(x: origin.x, y: origin.y)
            .accessibilityLabel("Slot \(slot): \(text)")
    }
}
