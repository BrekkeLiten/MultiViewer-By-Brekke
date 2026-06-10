import AppKit
import Foundation
import Observation

@Observable @MainActor
final class MonitorAppModel {
    let appState: AppState
    let settingsStore: SettingsStore
    let monitoringStore: PictureMonitoringStore
    let controlServerManager: ControlServerManager
    let metalCoordinator: MetalRenderCoordinator
    private(set) var programCoordinator: MetalRenderCoordinator?

    var layout: AppState.LayoutMode
    var primarySlot: Int
    var gridLayout: GridLayout
    var gridSplit: GridSplit
    var dualMonitorMode: Bool
    var oneUpScopeMonitorEnabled: Bool
    var scopeMonitorSplit: ScopeMonitorSplit
    var pictureMonitoring: PictureMonitoringSettings
    var showSourcesEditor = false
    var scrollPreferencesToPictureMonitoring = false
    var programMonitorOpen = false

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
        let grid = ConfigLoader.effectiveGridLayout(config: cfg)

        self.settingsStore = store
        self.workingConfig = cfg
        self.appState = state
        self.monitoringStore = monitoring
        self.controlServerManager = ControlServerManager(state: state)
        self.activePlayback = MonitorPlayback.from(config: cfg)
        self.layout = ConfigLoader.defaultLayout(config: cfg)
        self.primarySlot = cfg.primarySlot.flatMap { (1 ... MultiviewLimits.maxSlots).contains($0) ? $0 : nil } ?? 1
        self.gridLayout = grid
        self.gridSplit = ConfigLoader.effectiveGridSplit(config: cfg, grid: grid)
        self.dualMonitorMode = ConfigLoader.effectiveDualMonitorMode(config: cfg)
        self.oneUpScopeMonitorEnabled = ConfigLoader.effectiveOneUpScopeMonitor(config: cfg)
        self.scopeMonitorSplit = ConfigLoader.effectiveScopeMonitorSplit(config: cfg)
        self.pictureMonitoring = monitoring.get()
        self.metalCoordinator = MetalRenderCoordinator(windowRole: .single)

        appState.setLayout(layout)
        appState.setPrimarySlot(primarySlot)
        appState.setGridLayout(gridLayout)
        appState.setGridSplit(gridSplit)
        appState.setDualMonitorMode(dualMonitorMode)
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
            metalCoordinator.renderer?.setWindowRole(dualMonitorMode ? .multiview : .single)
            if dualMonitorMode {
                try openProgramMonitor()
            }
            metalCoordinator.syncRendererLayout(from: appState.get())
            pushUploadTargets()
            refreshOverlayData()
            metalCoordinator.startReconcileTimer(model: self)
        } catch {
            presentFatalRendererError(error)
        }
    }

    func openProgramMonitor() throws {
        guard programCoordinator == nil else { return }
        guard let sourceManager = metalCoordinator.sourceManager else {
            throw MetalRenderCoordinatorError.deviceUnavailable
        }
        let coordinator = MetalRenderCoordinator(windowRole: .program)
        try coordinator.start(
            appState: appState,
            playback: activePlayback,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit,
            pictureMonitoring: pictureMonitoring,
            sharedSourceManager: sourceManager,
            reconcilePeer: metalCoordinator,
            onRefresh: { [weak self] in
                Task { @MainActor in
                    self?.refreshOverlayData()
                }
            }
        )
        programCoordinator = coordinator
        programMonitorOpen = true
        coordinator.syncRendererLayout(from: appState.get())
        coordinator.requestDisplay()
    }

    func closeProgramMonitor() {
        programCoordinator = nil
        programMonitorOpen = false
    }

    func setDualMonitorMode(_ enabled: Bool) throws {
        dualMonitorMode = enabled
        appState.setDualMonitorMode(enabled)
        metalCoordinator.renderer?.setWindowRole(enabled ? .multiview : .single)
        if enabled {
            try openProgramMonitor()
        } else {
            closeProgramMonitor()
            metalCoordinator.renderer?.setWindowRole(.single)
        }
        persistDualMonitorMode(enabled)
        pushUploadTargets()
        metalCoordinator.requestDisplay()
        programCoordinator?.requestDisplay()
    }

    func refreshOverlayData() {
        let snap = appState.get()
        if layout != snap.layout { layout = snap.layout }
        if primarySlot != snap.primarySlot { primarySlot = snap.primarySlot }
        if gridLayout != snap.gridLayout { gridLayout = snap.gridLayout }
        if gridSplit != snap.gridSplit { gridSplit = snap.gridSplit }
        if dualMonitorMode != snap.dualMonitorMode { dualMonitorMode = snap.dualMonitorMode }
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
        guard !dualMonitorMode else { return }
        appState.setLayout(mode)
        layout = mode
        metalCoordinator.syncRendererLayout(from: appState.get())
        pushUploadTargets()
        refreshOverlayData()
        persistAppStateToDisk()
        metalCoordinator.requestDisplay()
    }

    func setGridLayout(_ grid: GridLayout) {
        gridLayout = grid
        gridSplit = gridSplit.resized(for: grid)
        appState.setGridLayout(grid)
        appState.setGridSplit(gridSplit)
        if !dualMonitorMode {
            appState.setLayout(.fourUp)
            layout = .fourUp
        }
        metalCoordinator.syncRendererLayout(from: appState.get())
        pushUploadTargets()
        refreshOverlayData()
        persistGridSettings()
        metalCoordinator.requestDisplay()
    }

    func applyGridSplit(_ split: GridSplit, persist: Bool) {
        gridSplit = split
        appState.setGridSplit(split)
        metalCoordinator.syncRendererLayout(from: appState.get())
        pushUploadTargets()
        refreshOverlayData()
        metalCoordinator.requestDisplay()
        if persist {
            persistGridSplit(split)
        }
    }

    func switchToOneUp(primarySlot slot: Int) {
        appState.setPrimarySlot(slot)
        primarySlot = slot
        if dualMonitorMode {
            programCoordinator?.syncRendererLayout(from: appState.get())
            programCoordinator?.requestDisplay()
            persistAppStateToDisk()
            refreshOverlayData()
            return
        }
        appState.setLayout(.oneUp)
        layout = .oneUp
        metalCoordinator.syncRendererLayout(from: appState.get())
        pushUploadTargets()
        refreshOverlayData()
        persistAppStateToDisk()
        metalCoordinator.requestDisplay()
    }

    func applyScopeMonitorSplit(_ split: ScopeMonitorSplit, persist: Bool) {
        scopeMonitorSplit = split
        metalCoordinator.setScopeMonitorSplit(split)
        programCoordinator?.setScopeMonitorSplit(split)
        pushUploadTargets()
        refreshOverlayData()
        metalCoordinator.requestDisplay()
        programCoordinator?.requestDisplay()
        if persist {
            persistScopeMonitorSplit(split)
        }
    }

    func applyOneUpScopeMonitor(_ enabled: Bool) {
        oneUpScopeMonitorEnabled = enabled
        metalCoordinator.setOneUpScopeMonitorEnabled(enabled)
        programCoordinator?.setOneUpScopeMonitorEnabled(enabled)
        pushUploadTargets()
        refreshOverlayData()
        metalCoordinator.requestDisplay()
        programCoordinator?.requestDisplay()
    }

    func applyPictureMonitoring(_ settings: PictureMonitoringSettings, persist: Bool) {
        pictureMonitoring = settings.clamped()
        monitoringStore.set(pictureMonitoring, notify: false)
        metalCoordinator.setPictureMonitoring(pictureMonitoring)
        programCoordinator?.setPictureMonitoring(pictureMonitoring)
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
        gridLayout = snap.gridLayout
        gridSplit = snap.gridSplit
        dualMonitorMode = snap.dualMonitorMode
        refreshOverlayData()
        metalCoordinator.syncRendererLayout(from: snap)
        programCoordinator?.syncRendererLayout(from: snap)
        pushUploadTargets()
        metalCoordinator.requestDisplay()
        programCoordinator?.requestDisplay()
    }

    private func pushUploadTargets() {
        metalCoordinator.pushDisplayUploadTargets(
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitorEnabled,
            scopeMonitorSplit: scopeMonitorSplit,
            gridLayout: gridLayout,
            gridSplit: gridSplit,
            dualMonitorMode: dualMonitorMode,
            programCoordinator: programCoordinator
        )
    }

    func persistAppStateToDisk() {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            let snap = appState.get()
            cfg.layout = snap.layout.rawValue
            cfg.primarySlot = snap.primarySlot
            cfg.gridColumns = snap.gridLayout.columns
            cfg.gridRows = snap.gridLayout.rows
            cfg.gridColumnSplits = snap.gridSplit.columnFractions.isEmpty ? nil : snap.gridSplit.columnFractions
            cfg.gridRowSplits = snap.gridSplit.rowFractions.isEmpty ? nil : snap.gridSplit.rowFractions
            cfg.dualMonitorMode = snap.dualMonitorMode
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

    func persistGridSettings() {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            cfg.gridColumns = gridLayout.columns
            cfg.gridRows = gridLayout.rows
            cfg.gridColumnSplits = gridSplit.columnFractions.isEmpty ? nil : gridSplit.columnFractions
            cfg.gridRowSplits = gridSplit.rowFractions.isEmpty ? nil : gridSplit.rowFractions
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {}
    }

    func persistGridSplit(_ split: GridSplit) {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            cfg.gridColumnSplits = split.columnFractions.isEmpty ? nil : split.columnFractions
            cfg.gridRowSplits = split.rowFractions.isEmpty ? nil : split.rowFractions
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {}
    }

    func persistDualMonitorMode(_ enabled: Bool) {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            cfg.dualMonitorMode = enabled
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {}
    }

    func persistScopeMonitorSplit(_ split: ScopeMonitorSplit) {
        do {
            var cfg = (try? settingsStore.load()) ?? .empty
            cfg.scopeColumnSplit = split.columnFraction
            cfg.scopeRowSplit = split.rowFraction
            workingConfig = cfg
            try settingsStore.save(cfg)
        } catch {}
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
        } catch {}
    }

    func reloadWorkingConfig() {
        workingConfig = (try? settingsStore.load()) ?? .empty
        gridLayout = ConfigLoader.effectiveGridLayout(config: workingConfig)
        gridSplit = ConfigLoader.effectiveGridSplit(config: workingConfig, grid: gridLayout)
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
