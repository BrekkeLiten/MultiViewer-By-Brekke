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

    func reconcile(with renderer: MetalRenderer) {
        let snap = state.get()

        for slot in 1 ... 4 {
            let desired = snap.slots[slot]

            lock.lock()
            let current = assignments[slot]
            let existingProvider = providers[slot]
            lock.unlock()

            if current == desired {
                if let monitorable = existingProvider as? MonitorableProvider,
                   let last = monitorable.lastFrameAt,
                   Date().timeIntervalSince(last) > 2.0
                {
                    let now = Date()
                    lock.lock()
                    let lastRestart = lastRestartAt[slot]
                    lock.unlock()

                    if lastRestart == nil || now.timeIntervalSince(lastRestart!) > 2.0 {
                        restartProvider(slot: slot, desired: desired, renderer: renderer)
                    }
                }
                continue
            }

            restartProvider(slot: slot, desired: desired, renderer: renderer)
        }

        renderer.setLayoutMode(snap.layout == .oneUp ? .oneUp : .fourUp)
        renderer.setPrimarySlot(snap.primarySlot)
    }

    /// Push on-screen pixel targets so providers downscale before GPU upload.
    func updateDisplayUploadTargets(
        viewportWidth: Int,
        viewportHeight: Int,
        layout: AppState.LayoutMode,
        primarySlot: Int
    ) {
        let geometryLayout: DisplayUploadGeometry.Layout = layout == .oneUp
            ? .oneUp(primarySlot: primarySlot)
            : .fourUp

        lock.lock()
        let providerSnapshot = providers
        lock.unlock()

        for slot in 1 ... 4 {
            guard let provider = providerSnapshot[slot] as? DisplaySizedUploadProvider else { continue }

            let cell = DisplayUploadGeometry.cellPixelSize(
                slot: slot,
                layout: geometryLayout,
                viewportWidth: viewportWidth,
                viewportHeight: viewportHeight
            )

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
                // Geometry known but no frame yet — reserve cell fit size for first upload.
                let fit = DisplayUploadGeometry.aspectFitPixelSize(
                    cellWidth: cell.width,
                    cellHeight: cell.height,
                    contentWidthOverHeight: aspect
                )
                provider.setTargetUploadSize(width: fit.width, height: fit.height)
            }
        }
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

    private func restartProvider(slot: Int, desired: AppState.SourceRef?, renderer: MetalRenderer) {
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

        renderer.setProvider(forSlot: slot, provider: newProvider)
    }
}
