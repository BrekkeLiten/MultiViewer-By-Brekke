import SwiftUI

struct FourUpInteractionOverlay: View {
    let model: MonitorAppModel
    let size: CGSize

    @State private var hoveredSlot: Int?

    var body: some View {
        if model.layout == .fourUp {
            ZStack(alignment: .topLeading) {
                if let hoveredSlot {
                    let frame = MultiviewSlotLayout.quadrantFrame(slot: hoveredSlot, in: size)
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
                        guard let slot = MultiviewSlotLayout.slotForPoint(location, in: size) else { return }
                        model.switchToOneUp(primarySlot: slot)
                    }
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredSlot = MultiviewSlotLayout.slotForPoint(location, in: size)
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
            .accessibilityHint("Click a quadrant to switch to 1-up view")
        } else {
            Color.clear
                .onAppear { hoveredSlot = nil }
        }
    }
}
