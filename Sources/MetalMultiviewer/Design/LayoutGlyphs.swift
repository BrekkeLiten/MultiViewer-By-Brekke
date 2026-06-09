import SwiftUI

/// Multiview layout toolbar glyphs (single full-frame vs 2×2 quad).
enum LayoutGlyphs {
    static let width: CGFloat = 28
    static let height: CGFloat = 16
    static let aspectHeightOverWidth: CGFloat = 9.0 / 16.0
    static let stroke: Color = .white
    static let strokeDimmed: Color = Color(white: 0.55)
    static let lineWidth: CGFloat = 1.15
    static let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
}

struct OneUpLayoutGlyph: View {
    var color: Color = LayoutGlyphs.stroke

    var body: some View {
        Canvas { context, size in
            let frame = LayoutFrame.rect16x9(in: size, padding: 1)
            context.stroke(
                Path(roundedRect: frame, cornerRadius: 1.5),
                with: .color(color),
                style: LayoutGlyphs.strokeStyle
            )
        }
        .frame(width: LayoutGlyphs.width, height: LayoutGlyphs.height)
        .accessibilityHidden(true)
    }
}

struct FourUpLayoutGlyph: View {
    var color: Color = LayoutGlyphs.stroke

    var body: some View {
        Canvas { context, size in
            let outer = LayoutFrame.rect16x9(in: size, padding: 1)
            let inset: CGFloat = 1.6
            let gutter: CGFloat = 1.5
            let grid = outer.insetBy(dx: inset, dy: inset)
            let cellW = (grid.width - gutter) / 2
            let cellH = (grid.height - gutter) / 2

            context.stroke(
                Path(roundedRect: outer, cornerRadius: 1.5),
                with: .color(color),
                style: LayoutGlyphs.strokeStyle
            )

            for row in 0 ..< 2 {
                for col in 0 ..< 2 {
                    let cell = CGRect(
                        x: grid.minX + CGFloat(col) * (cellW + gutter),
                        y: grid.minY + CGFloat(row) * (cellH + gutter),
                        width: cellW,
                        height: cellH
                    )
                    context.stroke(
                        Path(roundedRect: cell, cornerRadius: 0.5),
                        with: .color(color),
                        style: LayoutGlyphs.strokeStyle
                    )
                }
            }
        }
        .frame(width: LayoutGlyphs.width, height: LayoutGlyphs.height)
        .accessibilityHidden(true)
    }
}

/// Segmented-style 1-up / 4-up switcher (macOS `Picker` does not render custom Canvas labels).
struct LayoutModeSwitcher: View {
    @Binding var selection: AppState.LayoutMode

    private let segmentWidth: CGFloat = 40
    private let controlHeight: CGFloat = 26

    var body: some View {
        HStack(spacing: 0) {
            segment(.oneUp) {
                OneUpLayoutGlyph(color: glyphColor(for: .oneUp))
            }
            segment(.fourUp) {
                FourUpLayoutGlyph(color: glyphColor(for: .fourUp))
            }
        }
        .padding(3)
        .background(Capsule(style: .continuous).fill(Color(white: 0.20)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout")
    }

    private func segment<Icon: View>(_ mode: AppState.LayoutMode, @ViewBuilder icon: () -> Icon) -> some View {
        let isSelected = selection == mode
        return Button {
            selection = mode
        } label: {
            icon()
                .frame(width: segmentWidth, height: controlHeight - 6)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Color(white: 0.44))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .oneUp ? "1-up" : "4-up")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func glyphColor(for mode: AppState.LayoutMode) -> Color {
        selection == mode ? LayoutGlyphs.stroke : LayoutGlyphs.strokeDimmed
    }
}

private enum LayoutFrame {
    static func rect16x9(in size: CGSize, padding: CGFloat) -> CGRect {
        let maxW = size.width - padding * 2
        let maxH = size.height - padding * 2
        var width = maxW
        var height = width * LayoutGlyphs.aspectHeightOverWidth
        if height > maxH {
            height = maxH
            width = height / LayoutGlyphs.aspectHeightOverWidth
        }
        return CGRect(
            x: (size.width - width) * 0.5,
            y: (size.height - height) * 0.5,
            width: width,
            height: height
        )
    }
}
