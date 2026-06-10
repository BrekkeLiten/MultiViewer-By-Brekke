import SwiftUI

struct MainMonitorView: View {
    @Bindable var model: MonitorAppModel

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                MetalCanvasView(coordinator: model.metalCoordinator)
                    .frame(width: size.width, height: size.height)

                SignalStateOverlay(model: model, size: size)
                FeedBadgeOverlay(model: model, size: size)

                if model.oneUpScopeMonitorEnabled && model.layout == .oneUp {
                    ScopeChromeOverlay(split: model.scopeMonitorSplit, size: size)
                    ScopeDividerRepresentable(
                        split: model.scopeMonitorSplit,
                        isVisible: true
                    ) { split, persist in
                        model.applyScopeMonitorSplit(split, persist: persist)
                    }
                    .frame(width: size.width, height: size.height)
                }

                FourUpInteractionOverlay(model: model, size: size)
            }
            .frame(width: size.width, height: size.height)
        }
        .background(MonitorDesign.canvasBackground)
        .preferredColorScheme(.dark)
        .background(WindowChromeConfigurator(
            title: AppBranding.displayName,
            minimumSize: NSSize(width: 480, height: 270),
            activateOnAppear: true
        ))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                LayoutModeSwitcher(selection: layoutBinding)
                    .help("Layout: single full-frame or 2×2 multiview")

                Button("Inputs…") {
                    model.showSourcesEditor = true
                }
                .help("Configure NDI/SDI per slot")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: peakingBinding) {
                    Label {
                        Text("Focus Peaking")
                    } icon: {
                        FocusPeakingGlyph()
                    }
                }
                .toggleStyle(.button)
                .help("Focus peaking — highlight sharp edges")

                Toggle(isOn: falseColorBinding) {
                    Label {
                        Text("False Color")
                    } icon: {
                        FalseColorGlyph()
                    }
                }
                .toggleStyle(.button)
                .help("False color — luma heat map")

                Toggle(isOn: zebraBinding) {
                    Label {
                        Text("Zebra")
                    } icon: {
                        ZebraGlyph()
                    }
                }
                .toggleStyle(.button)
                .help("Zebra — over-exposure stripes")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Picture monitoring settings…")
                .simultaneousGesture(TapGesture().onEnded {
                    model.scrollPreferencesToPictureMonitoring = true
                })
            }
        }
        .toolbarBackground(MonitorDesign.canvasBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(isPresented: $model.showSourcesEditor) {
            SourcesEditorView(model: model)
        }
        .escapeReturnsToFourUp(model: model)
        .onReceive(NotificationCenter.default.publisher(for: .metalMultiviewerScopeMonitorChanged)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                model.applyOneUpScopeMonitor(enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .metalMultiviewerPictureMonitoringChanged)) { _ in
            // The store is the live source of truth (HTTP control mutates it directly);
            // reloading from disk here would revert remote toggles to stale persisted values.
            model.applyPictureMonitoring(model.monitoringStore.get(), persist: false)
        }
    }

    private var layoutBinding: Binding<AppState.LayoutMode> {
        Binding(
            get: { model.layout },
            set: { model.setLayout($0) }
        )
    }

    private var peakingBinding: Binding<Bool> {
        Binding(
            get: { model.pictureMonitoring.focusPeakingEnabled },
            set: { enabled in
                var next = model.pictureMonitoring
                next.focusPeakingEnabled = enabled
                model.applyPictureMonitoring(next, persist: true)
            }
        )
    }

    private var falseColorBinding: Binding<Bool> {
        Binding(
            get: { model.pictureMonitoring.falseColorEnabled },
            set: { enabled in
                var next = model.pictureMonitoring
                next.falseColorEnabled = enabled
                model.applyPictureMonitoring(next, persist: true)
            }
        )
    }

    private var zebraBinding: Binding<Bool> {
        Binding(
            get: { model.pictureMonitoring.zebraEnabled },
            set: { enabled in
                var next = model.pictureMonitoring
                next.zebraEnabled = enabled
                model.applyPictureMonitoring(next, persist: true)
            }
        )
    }
}
