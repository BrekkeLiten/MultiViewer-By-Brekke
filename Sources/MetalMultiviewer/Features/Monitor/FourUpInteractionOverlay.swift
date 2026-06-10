import SwiftUI

struct FourUpInteractionOverlay: View {
    let model: MonitorAppModel
    let size: CGSize
    let windowRole: MonitorWindowRole

    @State private var hoveredSlot: Int?

    private var showsGridInteraction: Bool {
        switch windowRole {
        case .multiview: return true
        case .program: return false
        case .single: return model.layout == .fourUp
        }
    }

    var body: some View {
        if showsGridInteraction {
            ZStack(alignment: .topLeading) {
                if let hoveredSlot {
                    let frame = MultiviewSlotLayout.cellFrame(
                        slot: hoveredSlot,
                        columns: model.gridLayout.columns,
                        rows: model.gridLayout.rows,
                        split: model.gridSplit,
                        in: size
                    )
                    Rectangle()
                        .fill(MonitorDesign.hoverTint)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                }

                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: size.width, height: size.height)
                    .onTapGesture(coordinateSpace: .local) { location in
                        guard !GridDividerOverlay.isNearDivider(
                            location,
                            split: model.gridSplit,
                            in: size
                        ) else { return }
                        guard let slot = MultiviewSlotLayout.slotForPoint(
                            location,
                            columns: model.gridLayout.columns,
                            rows: model.gridLayout.rows,
                            split: model.gridSplit,
                            in: size
                        ) else { return }
                        model.switchToOneUp(primarySlot: slot)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if GridDividerOverlay.isNearDivider(
                                location,
                                split: model.gridSplit,
                                in: size
                            ) {
                                hoveredSlot = nil
                            } else {
                                hoveredSlot = MultiviewSlotLayout.slotForPoint(
                                    location,
                                    columns: model.gridLayout.columns,
                                    rows: model.gridLayout.rows,
                                    split: model.gridSplit,
                                    in: size
                                )
                            }
                        case .ended:
                            hoveredSlot = nil
                        }
                    }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onChange(of: model.layout) { _, _ in
                hoveredSlot = nil
            }
            .accessibilityLabel("Multiview grid")
            .accessibilityHint(model.dualMonitorMode
                ? "Click a cell to show it on the program monitor"
                : "Click a cell to switch to 1-up view")
        } else {
            Color.clear
                .onAppear { hoveredSlot = nil }
        }
    }
}
