import AppKit
import Metal
import MetalKit

/// Owns one Metal viewport; optionally shares a `SourceManager` across windows.
@MainActor
final class MetalRenderCoordinator {
    let mtkView: MTKView
    let windowRole: MonitorWindowRole
    private(set) var renderer: MetalRenderer?
    private(set) var sourceManager: SourceManager?
    private var ownsSourceManager = false
    private var appState: AppState?
    private var reconcileTimer: Timer?
    private var onRefresh: (() -> Void)?
    private weak var reconcilePeer: MetalRenderCoordinator?

    init(windowRole: MonitorWindowRole = .single) {
        self.windowRole = windowRole
        let view = MTKView(frame: .zero)
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = true
        view.isPaused = true
        mtkView = view
    }

    func start(
        appState: AppState,
        playback: MonitorPlayback,
        oneUpScopeMonitor: Bool,
        scopeMonitorSplit: ScopeMonitorSplit,
        pictureMonitoring: PictureMonitoringSettings,
        sharedSourceManager: SourceManager? = nil,
        reconcilePeer: MetalRenderCoordinator? = nil,
        onRefresh: @escaping () -> Void
    ) throws {
        self.onRefresh = onRefresh
        self.appState = appState
        self.reconcilePeer = reconcilePeer

        guard let device = mtkView.device else {
            throw MetalRenderCoordinatorError.deviceUnavailable
        }

        let renderer = try MetalRenderer(device: device, drawablePixelFormat: mtkView.colorPixelFormat)
        renderer.setWindowRole(windowRole)
        renderer.setOneUpScopeMonitorEnabled(oneUpScopeMonitor)
        renderer.setScopeMonitorSplit(scopeMonitorSplit)
        renderer.setPictureMonitoring(pictureMonitoring)
        self.renderer = renderer
        mtkView.delegate = renderer

        if let sharedSourceManager {
            sourceManager = sharedSourceManager
            ownsSourceManager = false
        } else {
            let mtkViewRef = mtkView
            let onFrameUpdated: @Sendable () -> Void = {
                Task { @MainActor in
                    mtkViewRef.setNeedsDisplay(mtkViewRef.bounds)
                }
            }
            sourceManager = SourceManager(
                device: device,
                state: appState,
                playback: playback,
                onFrameUpdated: onFrameUpdated
            )
            ownsSourceManager = true
        }

    }

    func attachSharedSourceManager(_ manager: SourceManager, appState: AppState, onRefresh: @escaping () -> Void) {
        sourceManager = manager
        ownsSourceManager = false
        self.appState = appState
        self.onRefresh = onRefresh
    }

    func runReconcileTick(
        layout: AppState.LayoutMode,
        primarySlot: Int,
        oneUpScopeMonitor: Bool,
        scopeMonitorSplit: ScopeMonitorSplit,
        gridLayout: GridLayout,
        gridSplit: GridSplit,
        dualMonitorMode: Bool,
        programCoordinator: MetalRenderCoordinator?
    ) {
        guard let sourceManager, let appState else { return }
        var renderers: [MetalRenderer] = []
        if let r = renderer { renderers.append(r) }
        if dualMonitorMode, let peer = programCoordinator?.renderer { renderers.append(peer) }
        sourceManager.reconcile(with: renderers)

        let snap = appState.get()
        let multiviewViewport = effectiveDrawablePixelSize()
        let programViewport = programCoordinator?.effectiveDrawablePixelSize()

        let effectiveLayout = dualMonitorMode ? AppState.LayoutMode.fourUp : layout
        sourceManager.updateDisplayUploadTargets(
            viewportWidth: multiviewViewport.width,
            viewportHeight: multiviewViewport.height,
            layout: effectiveLayout,
            primarySlot: snap.primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitor && windowRole != .multiview,
            scopeMonitorSplit: scopeMonitorSplit,
            gridLayout: gridLayout,
            gridSplit: gridSplit,
            dualMonitorMode: dualMonitorMode,
            programViewportWidth: programViewport?.width,
            programViewportHeight: programViewport?.height,
            programOneUpScopeMonitor: oneUpScopeMonitor
        )
        onRefresh?()
    }

    isolated deinit {
        reconcileTimer?.invalidate()
    }

    private var oneUpScopeMonitorEnabled = false
    private var scopeMonitorSplit = ScopeMonitorSplit.defaults

    func setOneUpScopeMonitorEnabled(_ enabled: Bool) {
        oneUpScopeMonitorEnabled = enabled
        renderer?.setOneUpScopeMonitorEnabled(enabled)
        requestDisplay()
    }

    func setScopeMonitorSplit(_ split: ScopeMonitorSplit) {
        scopeMonitorSplit = split
        renderer?.setScopeMonitorSplit(split)
        requestDisplay()
    }

    func setPictureMonitoring(_ settings: PictureMonitoringSettings) {
        renderer?.setPictureMonitoring(settings)
        requestDisplay()
    }

    func syncRendererLayout(from snap: AppState.Snapshot) {
        renderer?.setLayoutMode(snap.layout == .oneUp ? .oneUp : .fourUp)
        renderer?.setPrimarySlot(snap.primarySlot)
        renderer?.setGridLayout(snap.gridLayout)
        renderer?.setGridSplit(snap.gridSplit)
    }

    func pushDisplayUploadTargets(
        layout: AppState.LayoutMode,
        primarySlot: Int,
        oneUpScopeMonitor: Bool,
        scopeMonitorSplit: ScopeMonitorSplit,
        gridLayout: GridLayout,
        gridSplit: GridSplit,
        dualMonitorMode: Bool,
        programCoordinator: MetalRenderCoordinator?
    ) {
        oneUpScopeMonitorEnabled = oneUpScopeMonitor
        self.scopeMonitorSplit = scopeMonitorSplit
        guard let sourceManager else { return }
        let viewport = effectiveDrawablePixelSize()
        let programViewport = programCoordinator?.effectiveDrawablePixelSize()
        let effectiveLayout = dualMonitorMode ? AppState.LayoutMode.fourUp : layout
        sourceManager.updateDisplayUploadTargets(
            viewportWidth: viewport.width,
            viewportHeight: viewport.height,
            layout: effectiveLayout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitor && windowRole != .multiview,
            scopeMonitorSplit: scopeMonitorSplit,
            gridLayout: gridLayout,
            gridSplit: gridSplit,
            dualMonitorMode: dualMonitorMode,
            programViewportWidth: programViewport?.width,
            programViewportHeight: programViewport?.height,
            programOneUpScopeMonitor: oneUpScopeMonitor
        )
    }

    func noteViewportSizeChanged() {
        onRefresh?()
        requestDisplay()
    }

    func effectiveDrawablePixelSize() -> (width: Int, height: Int) {
        let scale = mtkView.window?.backingScaleFactor ?? 1
        let dw = mtkView.drawableSize.width
        let dh = mtkView.drawableSize.height
        if dw > 0.5, dh > 0.5 {
            return (max(Int(dw), 1), max(Int(dh), 1))
        }
        return (
            max(Int(mtkView.bounds.width * scale), 1),
            max(Int(mtkView.bounds.height * scale), 1)
        )
    }

    func requestDisplay() {
        mtkView.setNeedsDisplay(mtkView.bounds)
    }

    func feedDimensionsBySlot() -> [Int: (width: Int, height: Int)] {
        sourceManager?.feedDimensionsBySlot() ?? [:]
    }

    func feedSignalStatusBySlot(snapshot: AppState.Snapshot) -> [Int: FeedSignalStatus] {
        sourceManager?.feedSignalStatusBySlot(snapshot: snapshot) ?? [:]
    }

    func startReconcileTimer(
        model: MonitorAppModel
    ) {
        reconcileTimer?.invalidate()
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self, weak model] _ in
            Task { @MainActor [weak self, weak model] in
                guard let self, let model else { return }
                self.runReconcileTick(
                    layout: model.layout,
                    primarySlot: model.primarySlot,
                    oneUpScopeMonitor: model.oneUpScopeMonitorEnabled,
                    scopeMonitorSplit: model.scopeMonitorSplit,
                    gridLayout: model.gridLayout,
                    gridSplit: model.gridSplit,
                    dualMonitorMode: model.dualMonitorMode,
                    programCoordinator: model.programCoordinator
                )
                model.programCoordinator?.requestDisplay()
                self.requestDisplay()
            }
        }
    }
}

enum MetalRenderCoordinatorError: Error {
    case deviceUnavailable
}
