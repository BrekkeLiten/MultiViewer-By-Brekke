import AppKit
import Metal
import MetalKit

/// Owns the Metal render loop and source manager; no AppKit UI chrome.
@MainActor
final class MetalRenderCoordinator {
    let mtkView: MTKView
    private(set) var renderer: MetalRenderer?
    private(set) var sourceManager: SourceManager?
    private var reconcileTimer: Timer?
    private var onRefresh: (() -> Void)?

    init() {
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
        onRefresh: @escaping () -> Void
    ) throws {
        self.onRefresh = onRefresh

        guard let device = mtkView.device else {
            throw MetalRenderCoordinatorError.deviceUnavailable
        }

        let renderer = try MetalRenderer(device: device, drawablePixelFormat: mtkView.colorPixelFormat)
        renderer.setOneUpScopeMonitorEnabled(oneUpScopeMonitor)
        renderer.setScopeMonitorSplit(scopeMonitorSplit)
        renderer.setPictureMonitoring(pictureMonitoring)
        self.renderer = renderer
        mtkView.delegate = renderer

        let mtkViewRef = mtkView
        let onFrameUpdated: @Sendable () -> Void = {
            Task { @MainActor in
                mtkViewRef.setNeedsDisplay(mtkViewRef.bounds)
            }
        }

        let sourceManager = SourceManager(
            device: device,
            state: appState,
            playback: playback,
            onFrameUpdated: onFrameUpdated
        )
        self.sourceManager = sourceManager

        let rendererRef = renderer
        let appStateRef = appState
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            sourceManager.reconcile(with: rendererRef)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = appStateRef.get()
                let viewport = self.effectiveDrawablePixelSize()
                sourceManager.updateDisplayUploadTargets(
                    viewportWidth: viewport.width,
                    viewportHeight: viewport.height,
                    layout: snap.layout,
                    primarySlot: snap.primarySlot,
                    oneUpScopeMonitor: self.oneUpScopeMonitorEnabled,
                    scopeMonitorSplit: self.scopeMonitorSplit
                )
                self.onRefresh?()
            }
        }
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
    }

    func pushDisplayUploadTargets(
        layout: AppState.LayoutMode,
        primarySlot: Int,
        oneUpScopeMonitor: Bool,
        scopeMonitorSplit: ScopeMonitorSplit
    ) {
        oneUpScopeMonitorEnabled = oneUpScopeMonitor
        self.scopeMonitorSplit = scopeMonitorSplit
        guard let sourceManager else { return }
        let viewport = effectiveDrawablePixelSize()
        sourceManager.updateDisplayUploadTargets(
            viewportWidth: viewport.width,
            viewportHeight: viewport.height,
            layout: layout,
            primarySlot: primarySlot,
            oneUpScopeMonitor: oneUpScopeMonitor,
            scopeMonitorSplit: scopeMonitorSplit
        )
    }

    func noteViewportSizeChanged() {
        onRefresh?()
        requestDisplay()
    }

    private func effectiveDrawablePixelSize() -> (width: Int, height: Int) {
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
}

enum MetalRenderCoordinatorError: Error {
    case deviceUnavailable
}
