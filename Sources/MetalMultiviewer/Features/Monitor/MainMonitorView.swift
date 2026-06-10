import SwiftUI

struct MainMonitorView: View {
    @Bindable var model: MonitorAppModel
    @Environment(\.openWindow) private var openWindow

    private var windowRole: MonitorWindowRole {
        model.dualMonitorMode ? .multiview : .single
    }

    var body: some View {
        MonitorContentView(
            model: model,
            coordinator: model.metalCoordinator,
            windowRole: windowRole,
            showLayoutSwitcher: !model.dualMonitorMode,
            showPictureMonitoring: !model.dualMonitorMode
        )
        .background(WindowChromeConfigurator(
            title: model.dualMonitorMode ? "\(AppBranding.displayName) — Multiview" : AppBranding.displayName,
            minimumSize: NSSize(width: 480, height: 270),
            activateOnAppear: true
        ))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if !model.dualMonitorMode {
                    LayoutModeSwitcher(selection: layoutBinding)
                        .help("Layout: single full-frame or multiview grid")
                }

                Button("Inputs…") {
                    model.showSourcesEditor = true
                }
                .help("Configure NDI/SDI per slot")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if !model.dualMonitorMode {
                    pictureMonitoringToolbar
                }

                if model.dualMonitorMode {
                    Button("Program Monitor") {
                        openWindow(id: "program")
                    }
                    .help("Show or focus the program monitor window")
                }

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Preferences…")
                .simultaneousGesture(TapGesture().onEnded {
                    model.scrollPreferencesToPictureMonitoring = false
                })
            }
        }
        .toolbarBackground(MonitorDesign.canvasBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(isPresented: $model.showSourcesEditor) {
            SourcesEditorView(model: model)
        }
        .escapeReturnsToFourUp(model: model, windowRole: windowRole)
        .onReceive(NotificationCenter.default.publisher(for: .metalMultiviewerScopeMonitorChanged)) { notification in
            if let enabled = notification.userInfo?["enabled"] as? Bool {
                model.applyOneUpScopeMonitor(enabled)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .metalMultiviewerPictureMonitoringChanged)) { _ in
            model.applyPictureMonitoring(model.monitoringStore.get(), persist: false)
        }
    }

    @ViewBuilder
    private var pictureMonitoringToolbar: some View {
        Toggle(isOn: peakingBinding) {
            Label { Text("Focus Peaking") } icon: { FocusPeakingGlyph() }
        }
        .toggleStyle(.button)
        .help("Focus peaking — highlight sharp edges")

        Toggle(isOn: falseColorBinding) {
            Label { Text("False Color") } icon: { FalseColorGlyph() }
        }
        .toggleStyle(.button)
        .help("False color — luma heat map")

        Toggle(isOn: zebraBinding) {
            Label { Text("Zebra") } icon: { ZebraGlyph() }
        }
        .toggleStyle(.button)
        .help("Zebra — over-exposure stripes")
    }

    private var layoutBinding: Binding<AppState.LayoutMode> {
        Binding(get: { model.layout }, set: { model.setLayout($0) })
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

struct ProgramMonitorView: View {
    @Bindable var model: MonitorAppModel

    var body: some View {
        Group {
            if let coordinator = model.programCoordinator {
                MonitorContentView(
                    model: model,
                    coordinator: coordinator,
                    windowRole: .program,
                    showLayoutSwitcher: false,
                    showPictureMonitoring: true
                )
            } else {
                ContentUnavailableView(
                    "Program Monitor",
                    systemImage: "rectangle.inset.filled",
                    description: Text("Enable dual monitor mode in Preferences.")
                )
            }
        }
        .background(WindowChromeConfigurator(
            title: "\(AppBranding.displayName) — Program",
            minimumSize: NSSize(width: 480, height: 270),
            activateOnAppear: false
        ))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: peakingBinding) {
                    Label { Text("Focus Peaking") } icon: { FocusPeakingGlyph() }
                }
                .toggleStyle(.button)

                Toggle(isOn: falseColorBinding) {
                    Label { Text("False Color") } icon: { FalseColorGlyph() }
                }
                .toggleStyle(.button)

                Toggle(isOn: zebraBinding) {
                    Label { Text("Zebra") } icon: { ZebraGlyph() }
                }
                .toggleStyle(.button)
            }
        }
        .toolbarBackground(MonitorDesign.canvasBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear {
            if model.programCoordinator == nil {
                try? model.openProgramMonitor()
            }
        }
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
