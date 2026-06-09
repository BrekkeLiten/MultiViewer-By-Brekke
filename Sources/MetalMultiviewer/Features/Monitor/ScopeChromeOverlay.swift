import SwiftUI

struct ScopeChromeOverlay: View {
    let split: ScopeMonitorSplit
    let size: CGSize

    private struct PanelInfo: Identifiable {
        var id: String { title }
        var title: String
        var frame: CGRect
        var showScale: Bool
    }

    var body: some View {
        let frames = ScopeMonitorPanelFrames.from(split: split, size: size)
        let panels: [PanelInfo] = [
            PanelInfo(title: "Preview", frame: frames.picture, showScale: false),
            PanelInfo(title: "Vectorscope", frame: frames.vectorscope, showScale: false),
            PanelInfo(title: "RGB Waveform", frame: frames.rgbWaveform, showScale: true),
            PanelInfo(title: "RGB Parade", frame: frames.rgbParade, showScale: true),
        ]

        ZStack(alignment: .topLeading) {
            ForEach(panels) { panel in
                panelHeader(panel.title, in: panel.frame)
                if panel.showScale {
                    intensityScale(in: panel.frame)
                }
            }
            vectorscopeTargets(in: frames.vectorscope)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    private func panelHeader(_ title: String, in frame: CGRect) -> some View {
        Text(title)
            .font(.system(size: 11))
            .foregroundStyle(MonitorDesign.scopeCaption)
            .position(
                x: frame.minX + MonitorDesign.panelHeaderInset + 40,
                y: frame.minY + 12
            )
    }

    private func intensityScale(in panelFrame: CGRect) -> some View {
        let scaleFrame = CGRect(
            x: panelFrame.minX,
            y: panelFrame.minY + 28,
            width: panelFrame.width,
            height: max(panelFrame.height - 32, 4)
        )
        let gutterWidth = CGFloat(ScopeIntensityScale.labelColumnWidthPx)

        return ZStack(alignment: .topLeading) {
            ForEach(ScopeIntensityScale.ireTickValues, id: \.self) { ire in
                let fromTop = CGFloat(ScopeIntensityScale.displayFractionFromTop(ire: ire))
                let lineY = scaleFrame.minY + fromTop * scaleFrame.height
                Text("\(ire)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MonitorDesign.scopeScaleNumeral)
                    .position(
                        x: scaleFrame.minX + gutterWidth - 6,
                        y: lineY + CGFloat(ScopeIntensityScale.labelBelowLinePx) + 6
                    )
            }
            Text("IRE")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(MonitorDesign.scopeScaleNumeral)
                .position(
                    x: scaleFrame.minX + 12,
                    y: scaleFrame.maxY - 10
                )
        }
    }

    private func vectorscopeTargets(in panelFrame: CGRect) -> some View {
        let containerBounds = CGRect(origin: .zero, size: size)
        let circle = VectorscopeOverlayLayout.circleRect(in: containerBounds, split: split)
        let letters = ScopeMonitorLayout.ResolveStyle.vectorscopeTargetLetters
        let angles = ScopeColorMath.vectorscopeTargetAngles

        return ForEach(Array(letters.enumerated()), id: \.offset) { idx, letter in
            if idx < angles.count {
                let center = VectorscopeOverlayLayout.targetLabelCenter(in: circle, angle: angles[idx])
                Text(letter)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(MonitorDesign.scopeTargetLetter)
                    .position(x: center.x, y: center.y)
            }
        }
    }
}
