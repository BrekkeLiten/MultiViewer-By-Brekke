import AppKit
import Foundation
import Observation

@Observable @MainActor
final class MonitorAppModel {
    let appState: AppState
    let settingsStore: SettingsStore
    let monitoringStore: PictureMonitoringStore
    let controlServerManager: ControlServerManager
    let metalCoordinator = MetalRenderCoordinator()

    var layout: AppState.LayoutMode
    var primarySlot: Int
    var oneUpScopeMonitorEnabled: Bool
    var scopeMonitorSplit: ScopeMonitorSplit
    var pictureMonitoring: PictureMonitoringSettings
    var showSourcesEditor = false
    var scrollPreferencesToPictureMonitoring = false

    var feedDimensions: [Int: (width: Int, height: Int)] = [:]
    var signalStatus: [Int: FeedSignalStatus] = [:]

    private(set) var activePlayback: MonitorPlayback
    private(set) var workingConfig: AppConfig
    private var remoteStateObserver: NSObjectProtocol?

    init() {
        let store = SettingsStore(url: ConfigLoader.persistedConfigURL())
        let cfg = (try? store.load()) ?? .empty
        let state = AppState()
        let monitoring = PictureMonitoringStore(
            settings: ConfigLoader.effectivePictureMonitoring(config: cfg)
        )

        self.settingsStore = store
        self.workingConfig = cfg
        self.appState = state
        self.monitoringStore = monitoring
        self.controlServerManager = ControlServerManager(state: state)
        self.activePlayback = MonitorPlayback.from(config: cfg)
        self.layout = ConfigLoader.defaultLayout(config: cfg)
        self.primarySlot = cfg.primarySlot.flatMap { (1 ... 4).contains($0) ? $0 : nil } ?? 1
        self.oneUpScopeMonitorEnabled = ConfigLoader.effectiveOneUpScopeMonitor(config: cfg)
        self.scopeMonitorSplit = ConfigLoader.effectiveScopeMonitorSplit(config: cfg)
        self.pictureMonitoring = monitoring.get()

        appState.setLayout(layout)
        appState.setPrimarySlot(primarySlot)
        loadSlotsFromConfig(cfg, into: state)
    }

    isolated deinit {
        if let remoteStateObserver {
            NotificationCenter.default.removeObserver(remoteStateObserver)
        }
    }

    func finishLaunchSetup() {
        monitoringStore.set(pictureMonitoring, notify: false)
        controlServerManager.apply(
            enabled: ConfigLoader.effectiveControlEnabled(config: workingConfig),
            port: ConfigLoader.effectivePort(config: workingConfig),
            bindAddress: ConfigLoader.persistedControlBindAddress(config: workingConfig),
            monitoringStore: monitoringStore
        )

        remoteStateObserver = NotificationCenter.default.addObserver(
            forName: .metalMultiviewerAppStateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromAppState()
                self?.persistAppStateToDisk()
            }
        }

        do {
            try metalCoordinator.start(
                appState: appState,
                playback: activePlayback,
                oneUpScopeMonitor: oneUpScopeMonitorEnabled,
                scopeMonitorSplit: scopeMonitorSplit,
                pictureMonitoring: pictureMonitoring,
                onRefresh: { [weak self] in
                    Task { @MainActor in
                        self?.refreshOverlayData()
                    }
                }
            )
            metalCoordinator.syncRendererLayout(from: appState.get())
            metalCoordinator.pushDisplayUploadTargets(
                layout: layout,
                primarySlot: primarySlot,
                oneUpScopeMonitor: oneUpScopeMonitorEnabled,
                scopeMonitorSplit: scopeMonitorSplit
            )
            refreshOverlayData()
        } catch {
            presentFatalRendererError(error)
        }
    }

    func refreshOverlayData() {
        // Runs at 20 Hz from the reconcile timer — only write @Observable
        // properties when values actually changed to avoid SwiftUI churn.
        let snap = appState.get()
        if layout != snap.layout { layout = snap.layout }
        if primarySlot != snap.primarySlot { primarySlot = snap.primarySlot }
        let dims = metalCoordinator.feedDimensionsBySlot()
        if !Self.dimensionsEqual(feedDimensions, dims) { feedDimensions = dims }
        let status = metalCoordinator.feedSignalStatusBySlot(snapshot: snap)
        if signalStatus != status { signalStatus = status }
    }

    private static func dimensionsEqual(
        _ a: [Int: (width: Int, height: Int)],
        _ b: [Int: (width: Int, height: Int)]
    ) -> Bool {
        guard a.count == b.count else { return false }
        for (slot, dims) in a {
            guard let other = b[slot], other == dims else { return false }
        }
        return true
    }

    func setLayout(_ mode: AppState.LayoutMode) {
        appState.setLayout(mode)
        layout = mode
        metalCoordinator.syncRendererLayout(from: appState.get())
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit
        )
        refreshOverlayData()
        persistAppStateToDisk()
        metalCoordinator.requestDisplay()
    }

    func switchToOneUp(primarySlot slot: Int) {
        appState.setPrimarySlot(slot)
        appState.setLayout(.oneUp)
        primarySlot = slot
        layout = .oneUp
        metalCoordinator.syncRendererLayout(from: appState.get())
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit
        )
        refreshOverlayData()
        persistAppStateToDisk()
        metalCoordinator.requestDisplay()
    }

    func applyScopeMonitorSplit(_ split: ScopeMonitorSplit, persist: Bool) {
        scopeMonitorSplit = split
        metalCoordinator.setScopeMonitorSplit(split)
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit
        )
        refreshOverlayData()
        metalCoordinator.requestDisplay()
        if persist {
            persistScopeMonitorSplit(split)
        }
    }

    func applyOneUpScopeMonitor(_ enabled: Bool) {
        oneUpScopeMonitorEnabled = enabled
        metalCoordinator.setOneUpScopeMonitorEnabled(enabled)
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit
        )
        refreshOverlayData()
        metalCoordinator.requestDisplay()
    }

    func applyPictureMonitoring(_ settings: PictureMonitoringSettings, persist: Bool) {
        pictureMonitoring = settings.clamped()
        monitoringStore.set(pictureMonitoring, notify: false)
        metalCoordinator.setPictureMonitoring(pictureMonitoring)
        if persist {
            persistPictureMonitoring(pictureMonitoring)
        }
    }

    func toggleFocusPeaking() {
        var next = pictureMonitoring
        next.focusPeakingEnabled.toggle()
        applyPictureMonitoring(next, persist: true)
    }

    func toggleFalseColor() {
        var next = pictureMonitoring
        next.falseColorEnabled.toggle()
        applyPictureMonitoring(next, persist: true)
    }

    func toggleZebra() {
        var next = pictureMonitoring
        next.zebraEnabled.toggle()
        applyPictureMonitoring(next, persist: true)
    }

    func syncFromAppState() {
        let snap = appState.get()
        layout = snap.layout
        primarySlot = snap.primarySlot
        refreshOverlayData()
        metalCoordinator.syncRendererLayout(from: snap)
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit
        )
        metalCoordinator.requestDisplay()
    }

    func persistAppStateToDisk() {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            let snap = appState.get()
            cfg.layout = snap.layout.rawValue
            cfg.primarySlot = snap.primarySlot
            var slots: [String: String] = [:]
            for (k, ref) in snap.slots.sorted(by: { $0.key < $1.key }) {
                slots["\(k)"] = ref.persistenceString
            }
            cfg.slots = slots.isEmpty ? nil : slots
            cfg.scopeColumnSplit = scopeMonitorSplit.columnFraction
            cfg.scopeRowSplit = scopeMonitorSplit.rowFraction
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {
            // Best-effort persistence.
        }
    }

    func persistScopeMonitorSplit(_ split: ScopeMonitorSplit) {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            cfg.scopeColumnSplit = split.columnFraction
            cfg.scopeRowSplit = split.rowFraction
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {
            // Best-effort persistence.
        }
    }

    func persistPictureMonitoring(_ settings: PictureMonitoringSettings) {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            let clamped = settings.clamped()
            cfg.focusPeakingEnabled = clamped.focusPeakingEnabled
            cfg.falseColorEnabled = clamped.falseColorEnabled
            cfg.zebraEnabled = clamped.zebraEnabled
            cfg.focusPeakingColor = clamped.focusPeakingColor.rawValue
            cfg.focusPeakingSensitivity = clamped.focusPeakingSensitivity
            cfg.zebraLevel = clamped.zebraLevel
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {
            // Best-effort persistence.
        }
    }

    func reloadWorkingConfig() {
        workingConfig = (try? settingsStore.load()) ?? .empty
    }

    func commitSourcesEditor() {
        persistAppStateToDisk()
        syncFromAppState()
    }

    private func loadSlotsFromConfig(_ cfg: AppConfig, into state: AppState) {
        guard let slots = cfg.slots else { return }
        for (slotKey, value) in slots {
            guard let slot = Int(slotKey) else { continue }
            if let src = try? ControlServer.parseSourceRef(value) {
                try? state.setSource(slot: slot, source: src)
            }
        }
    }

    private func presentFatalRendererError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Failed to start renderer"
        alert.informativeText = "\(error)"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
