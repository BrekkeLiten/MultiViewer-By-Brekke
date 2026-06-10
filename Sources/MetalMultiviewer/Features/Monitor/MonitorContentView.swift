import SwiftUI

/// Shared Metal canvas + overlays for main and program windows.
struct MonitorContentView: View {
    @Bindable var model: MonitorAppModel
    let coordinator: MetalRenderCoordinator
    let windowRole: MonitorWindowRole
    var showLayoutSwitcher: Bool = true
    var showPictureMonitoring: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                MetalCanvasView(coordinator: coordinator)
                    .frame(width: size.width, height: size.height)

                SignalStateOverlay(model: model, size: size, windowRole: windowRole)
                FeedBadgeOverlay(model: model, size: size, windowRole: windowRole)

                if showsScopeChrome {
                    ScopeChromeOverlay(split: model.scopeMonitorSplit, size: size)
                    ScopeDividerRepresentable(
                        split: model.scopeMonitorSplit,
                        isVisible: true
                    ) { split, persist in
                        model.applyScopeMonitorSplit(split, persist: persist)
                    }
                    .frame(width: size.width, height: size.height)
                }

                FourUpInteractionOverlay(model: model, size: size, windowRole: windowRole)

                // Above cell click/hover layer so divider drags receive mouse events first.
                if showsGridDividers {
                    GridDividerRepresentable(
                        gridLayout: model.gridLayout,
                        split: model.gridSplit,
                        isVisible: true
                    ) { split, persist in
                        model.applyGridSplit(split, persist: persist)
                    }
                    .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .background(MonitorDesign.canvasBackground)
        .preferredColorScheme(.dark)
    }

    private var showsScopeChrome: Bool {
        guard model.oneUpScopeMonitorEnabled else { return false }
        switch windowRole {
        case .program: return true
        case .single: return model.layout == .oneUp
        case .multiview: return false
        }
    }

    private var showsGridDividers: Bool {
        switch windowRole {
        case .multiview: return true
        case .single: return model.layout == .fourUp
        case .program: return false
        }
    }
}
