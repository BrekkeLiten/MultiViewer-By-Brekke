import SwiftUI

/// Picture-monitoring toolbar glyphs (SmallHD / on-camera monitor convention).
enum PictureMonitoringGlyphs {
    static let width: CGFloat = 22
    static let height: CGFloat = 18
}

// MARK: - Focus peaking — subject silhouette with dashed edge highlight

struct FocusPeakingGlyph: View {
    var body: some View {
        Canvas { context, size in
            let silhouette = Self.silhouettePath(in: size)
            context.fill(silhouette, with: .color(Color(white: 0.42)))

            context.stroke(
                silhouette,
                with: .color(.white.opacity(0.95)),
                style: StrokeStyle(lineWidth: 1.1, lineJoin: .round, dash: [1.6, 1.1])
            )

            // Soft outer peaking ring (reference aura)
            let aura = silhouette.strokedPath(StrokeStyle(lineWidth: 2.4, lineJoin: .round))
            context.stroke(
                aura,
                with: .color(.white.opacity(0.28)),
                style: StrokeStyle(lineWidth: 2.4, lineJoin: .round, dash: [2.0, 1.6])
            )
        }
        .frame(width: PictureMonitoringGlyphs.width, height: PictureMonitoringGlyphs.height)
        .accessibilityHidden(true)
    }

    private static func silhouettePath(in size: CGSize) -> Path {
        var path = Path()
        let cx = size.width * 0.5
        path.addEllipse(in: CGRect(x: cx - 3.1, y: 1.6, width: 6.2, height: 6.2))
        path.addEllipse(in: CGRect(x: cx - 6.0, y: 6.8, width: 12.0, height: 7.2))
        return path
    }
}

// MARK: - False colour — horizontal exposure ladder (no frame border)

struct FalseColorGlyph: View {
    private static let bands: [Color] = [
        Color(red: 0.86, green: 0.56, blue: 0.56), // over / warm
        Color(red: 0.78, green: 0.84, blue: 0.48),
        Color(red: 0.46, green: 0.78, blue: 0.56),
        Color(red: 0.56, green: 0.74, blue: 0.90),
        Color(red: 0.64, green: 0.56, blue: 0.80), // shadow / cool
    ]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.bands.enumerated()), id: \.offset) { _, color in
                color
            }
        }
        .frame(width: 14, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .frame(width: PictureMonitoringGlyphs.width, height: PictureMonitoringGlyphs.height)
        .accessibilityHidden(true)
    }
}

// MARK: - Zebra — alternating diagonal stripes filling the square

struct ZebraGlyph: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 4, y: 2, width: 14, height: 14)
            let clip = Path(roundedRect: rect, cornerRadius: 2)

            context.clip(to: clip)
            context.fill(Path(rect), with: .color(Color(white: 0.34)))

            let stripeWidth: CGFloat = 2.6
            var x = rect.minX - rect.height
            var index = 0
            while x < rect.maxX + rect.height {
                var stripe = Path()
                stripe.move(to: CGPoint(x: x, y: rect.maxY))
                stripe.addLine(to: CGPoint(x: x + stripeWidth, y: rect.maxY))
                stripe.addLine(to: CGPoint(x: x + stripeWidth + rect.height, y: rect.minY))
                stripe.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                stripe.closeSubpath()

                if index.isMultiple(of: 2) {
                    context.fill(stripe, with: .color(Color(white: 0.68)))
                }
                x += stripeWidth
                index += 1
            }
        }
        .frame(width: PictureMonitoringGlyphs.width, height: PictureMonitoringGlyphs.height)
        .accessibilityHidden(true)
    }
}
