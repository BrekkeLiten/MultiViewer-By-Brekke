import Foundation
import Metal

final class SourceManager: @unchecked Sendable {
    private let device: MTLDevice
    private let state: AppState
    private let playback: MonitorPlayback
    private let onFrameUpdated: @Sendable () -> Void

    private let lock = NSLock()
    private var providers: [Int: FrameProvider] = [:]
    private var assignments: [Int: AppState.SourceRef] = [:]
    private var lastRestartAt: [Int: Date] = [:]
    /// Doubling restart delay per slot for persistently dead feeds (reset when frames flow again).
    private var restartBackoff: [Int: TimeInterval] = [:]
    private static let maxRestartBackoff: TimeInterval = 30

    init(
        device: MTLDevice,
        state: AppState,
        playback: MonitorPlayback,
        onFrameUpdated: @escaping @Sendable () -> Void
    ) {
        self.device = device
        self.state = state
        self.playback = playback
        self.onFrameUpdated = onFrameUpdated
    }

    func reconcile(with renderers: [MetalRenderer]) {
        let snap = state.get()

        for slot in 1 ... MultiviewLimits.maxSlots {
            let desired = snap.slots[slot]

            lock.lock()
            let current = assignments[slot]
            let existingProvider = providers[slot]
            lock.unlock()

            if current == desired {
                guard let monitorable = existingProvider as? MonitorableProvider,
                      let last = monitorable.lastFrameAt
                else { continue }

                let now = Date()
                if now.timeIntervalSince(last) <= FeedSignalPolicy.staleInterval {
                    lock.lock()
                    restartBackoff[slot] = nil
                    lock.unlock()
                    continue
                }

                lock.lock()
                let lastRestart = lastRestartAt[slot]
                let backoff = restartBackoff[slot] ?? FeedSignalPolicy.staleInterval
                lock.unlock()

                if lastRestart == nil || now.timeIntervalSince(lastRestart!) > backoff {
                    lock.lock()
                    restartBackoff[slot] = min(backoff * 2, Self.maxRestartBackoff)
                    lock.unlock()
                    restartProvider(slot: slot, desired: desired, renderers: renderers)
                }
                continue
            }

            lock.lock()
            restartBackoff[slot] = nil
            lock.unlock()
            restartProvider(slot: slot, desired: desired, renderers: renderers)
        }

        for renderer in renderers {
            renderer.setLayoutMode(snap.layout == .oneUp ? .oneUp : .fourUp)
            renderer.setPrimarySlot(snap.primarySlot)
            renderer.setGridLayout(snap.gridLayout)
            renderer.setGridSplit(snap.gridSplit)
        }
    }

    /// Push on-screen pixel targets so providers downscale before GPU upload.
    func updateDisplayUploadTargets(
        viewportWidth: Int,
        viewportHeight: Int,
        layout: AppState.LayoutMode,
        primarySlot: Int,
        oneUpScopeMonitor: Bool,
        scopeMonitorSplit: ScopeMonitorSplit = .defaults,
        gridLayout: GridLayout,
        gridSplit: GridSplit,
        dualMonitorMode: Bool,
        programViewportWidth: Int? = nil,
        programViewportHeight: Int? = nil,
        programOneUpScopeMonitor: Bool = false
    ) {
        let geometryLayout: DisplayUploadGeometry.Layout = switch layout {
        case .oneUp where oneUpScopeMonitor:
            .oneUpScopeMonitor(primarySlot: primarySlot, split: scopeMonitorSplit)
        case .oneUp:
            .oneUp(primarySlot: primarySlot)
        case .fourUp:
            .grid(columns: gridLayout.columns, rows: gridLayout.rows, split: gridSplit)
        }

        lock.lock()
        let providerSnapshot = providers
        lock.unlock()

        for slot in 1 ... MultiviewLimits.maxSlots {
            guard let provider = providerSnapshot[slot] as? DisplaySizedUploadProvider else { continue }

            var cell = DisplayUploadGeometry.cellPixelSize(
                slot: slot,
                layout: geometryLayout,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight
            )

            if dualMonitorMode, let pw = programViewportWidth, let ph = programViewportHeight, slot == primarySlot {
                let programCell = DisplayUploadGeometry.cellPixelSize(
                    slot: slot,
                    layout: programOneUpScopeMonitor
                        ? .oneUpScopeMonitor(primarySlot: primarySlot, split: scopeMonitorSplit)
                        : .oneUp(primarySlot: primarySlot),
                    viewportWidth: pw,
                    viewportHeight: ph
                )
                cell = (
                    max(cell.width, programCell.width),
                    max(cell.height, programCell.height)
                )
            }

            let aspect: Float? = {
                if let reporter = providerSnapshot[slot] as? VideoBroadcastAspectReporting {
                    let r = reporter.broadcastAspectRatio
                    if r > 0.001 { return r }
                }
                if let dims = providerSnapshot[slot] as? VideoFeedDimensionReporting {
                    let w = dims.feedPixelWidth
                    let h = dims.feedPixelHeight
                    if w > 0, h > 0 { return Float(w) / Float(h) }
                }
                return nil
            }()

            let sourceW = (providerSnapshot[slot] as? VideoFeedDimensionReporting)?.receivedPixelWidth ?? 0
            let sourceH = (providerSnapshot[slot] as? VideoFeedDimensionReporting)?.receivedPixelHeight ?? 0

            let target = DisplayUploadGeometry.uploadPixelSize(
                sourceWidth: sourceW,
                sourceHeight: sourceH,
                cellWidth: cell.width,
                cellHeight: cell.height,
                contentWidthOverHeight: aspect
            )

            if target.width > 0, target.height > 0 {
                provider.setTargetUploadSize(width: target.width, height: target.height)
            } else if cell.width == 0 || cell.height == 0 {
                provider.setTargetUploadSize(width: 0, height: 0)
            } else if sourceW == 0 || sourceH == 0 {
                let fit = DisplayUploadGeometry.aspectFitPixelSize(
                    cellWidth: cell.width,
                    cellHeight: cell.height,
                    contentWidthOverHeight: aspect
                )
                provider.setTargetUploadSize(width: fit.width, height: fit.height)
            }
        }
    }

    func feedSignalStatusBySlot(snapshot: AppState.Snapshot) -> [Int: FeedSignalStatus] {
        lock.lock()
        let providerSnapshot = providers
        let restartSnapshot = lastRestartAt
        lock.unlock()

        var out: [Int: FeedSignalStatus] = [:]
        for slot in 1 ... MultiviewLimits.maxSlots {
            let assignment = snapshot.slots[slot]
            let provider = providerSnapshot[slot]
            let monitorable = provider as? MonitorableProvider
            out[slot] = FeedSignalPolicy.status(
                assignment: assignment,
                hasProvider: assignment != nil && provider != nil,
                lastFrameAt: monitorable?.lastFrameAt,
                lastRestartAt: restartSnapshot[slot],
                hasDisplayableTexture: Self.hasDisplayableTexture(provider: provider)
            )
        }
        return out
    }

    private static func hasDisplayableTexture(provider: FrameProvider?) -> Bool {
        guard let tex = provider?.copyLatestTexture() else { return false }
        return tex.width > 2 && tex.height > 2
    }

    func feedDimensionsBySlot() -> [Int: (width: Int, height: Int)] {
        lock.lock()
        defer { lock.unlock() }
        var out: [Int: (width: Int, height: Int)] = [:]
        for (slot, provider) in providers {
            guard let reporting = provider as? VideoFeedDimensionReporting else { continue }
            out[slot] = (reporting.feedPixelWidth, reporting.feedPixelHeight)
        }
        return out
    }

    private func provider(slot: Int) -> FrameProvider? {
        lock.lock()
        defer { lock.unlock() }
        return providers[slot]
    }

    private func restartProvider(slot: Int, desired: AppState.SourceRef?, renderers: [MetalRenderer]) {
        if let old = provider(slot: slot) as? NDIReceiver { old.stop() }
        if let old = provider(slot: slot) as? DeckLinkCapture { old.stop() }

        let newProvider: FrameProvider?
        if let desired {
            switch desired {
            case let .ndi(name):
                let r = NDIReceiver(device: device, streamName: name, playback: playback)
                r.onFrameUpdated = onFrameUpdated
                r.start()
                newProvider = r
            case let .sdi(index):
                let c = DeckLinkCapture(device: device, inputIndex: index, playback: playback)
                c.onFrameUpdated = onFrameUpdated
                c.start()
                newProvider = c
            }
        } else {
            newProvider = nil
        }

        lock.lock()
        assignments[slot] = desired
        providers[slot] = newProvider
        lastRestartAt[slot] = Date()
        lock.unlock()

        for renderer in renderers {
            renderer.setProvider(forSlot: slot, provider: newProvider)
        }
    }
}
