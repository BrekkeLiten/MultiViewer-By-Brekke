import AppKit
import MetalKit
import Metal

/// Overlay that forwards hits only to badge subviews; gaps pass through to `mtkView` below.
private final class PassThroughOverlayView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let sv = superview else { return nil }
        let inSelf = convert(point, from: sv)
        guard bounds.contains(inSelf), !isHidden, alphaValue > 0.001 else { return nil }
        for child in subviews.reversed() {
            if let hit = child.hitTest(inSelf) { return hit }
        }
        return nil
    }
}

@MainActor
final class MainViewController: NSViewController {
    private let mtkView = MTKView(frame: .zero)
    private var renderer: MetalRenderer?
    private let appState: AppState
    private var sourceManager: SourceManager?

    /// Non-interactive layer above `mtkView` for per-slot resolution badges.
    private let feedBadgeOverlay = PassThroughOverlayView(frame: .zero)
    private var feedBadgeLabels: [NSTextField] = []
    /// Limits slot-1 badge width to the left half in 4-up; relaxed in 1-up.
    private var badgeSlot1FourUpTrailing: NSLayoutConstraint?

    /// Main app coordinator (menu bar persistence + presenting source sheet).
    weak var coordinationHost: MetalMultiviewerApp?

    private var titleBarChromeInstalled = false
    private weak var layoutSegment: NSSegmentedControl?
    private let playback: MonitorPlayback

    init(state: AppState, playback: MonitorPlayback) {
        self.appState = state
        self.playback = playback
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720))
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        mtkView.translatesAutoresizingMaskIntoConstraints = false
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 120
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        view.addSubview(mtkView)
        NSLayoutConstraint.activate([
            mtkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mtkView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        mtkView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor).isActive = true

        feedBadgeOverlay.translatesAutoresizingMaskIntoConstraints = false
        feedBadgeOverlay.wantsLayer = true
        feedBadgeOverlay.layer?.backgroundColor = NSColor.clear.cgColor

        view.addSubview(feedBadgeOverlay)

        NSLayoutConstraint.activate([
            feedBadgeOverlay.leadingAnchor.constraint(equalTo: mtkView.leadingAnchor),
            feedBadgeOverlay.trailingAnchor.constraint(equalTo: mtkView.trailingAnchor),
            feedBadgeOverlay.topAnchor.constraint(equalTo: mtkView.topAnchor),
            feedBadgeOverlay.bottomAnchor.constraint(equalTo: mtkView.bottomAnchor),
        ])

        setupFeedBadgeLabels()

        guard let device = mtkView.device else {
            assertionFailure("Metal device unavailable")
            return
        }

        do {
            let renderer = try MetalRenderer(device: device, drawablePixelFormat: mtkView.colorPixelFormat)
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
            Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                sourceManager.reconcile(with: rendererRef)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let snap = appStateRef.get()
                    sourceManager.updateDisplayUploadTargets(
                        viewportWidth: Int(self.mtkView.drawableSize.width),
                        viewportHeight: Int(self.mtkView.drawableSize.height),
                        layout: snap.layout,
                        primarySlot: snap.primarySlot
                    )
                    self.updateFeedResolutionBadges(sourceManager: sourceManager)
                }
            }
            configureFeedBadgeLayoutMode(appState.get().layout)
            updateFeedResolutionBadges(sourceManager: sourceManager)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to start renderer"
            alert.informativeText = "\(error)"
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        installTitleBarChromeIfNeeded()
        pushDisplayUploadTargets()
    }

    private func pushDisplayUploadTargets() {
        guard let sourceManager else { return }
        let snap = appState.get()
        sourceManager.updateDisplayUploadTargets(
            viewportWidth: Int(mtkView.drawableSize.width),
            viewportHeight: Int(mtkView.drawableSize.height),
            layout: snap.layout,
            primarySlot: snap.primarySlot
        )
    }

    func syncTitleBarLayout(with layout: AppState.LayoutMode) {
        guard let seg = layoutSegment else { return }
        seg.selectedSegment = layout == .oneUp ? 0 : 1
        configureFeedBadgeLayoutMode(layout)
    }

    /// Host may call before `layoutSegment` exists; latest layout is applied once installed.
    private func installTitleBarChromeIfNeeded() {
        guard !titleBarChromeInstalled, let window = view.window else { return }
        titleBarChromeInstalled = true

        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .bottom

        let bar = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 38))
        bar.translatesAutoresizingMaskIntoConstraints = true
        bar.autoresizingMask = [.width, .maxYMargin]

        let seg = NSSegmentedControl(labels: ["1-up", "4-up"], trackingMode: .selectOne, target: self, action: #selector(layoutSegmentChanged(_:)))
        seg.segmentStyle = .texturedRounded
        seg.identifier = NSUserInterfaceItemIdentifier("layoutSegment")
        seg.translatesAutoresizingMaskIntoConstraints = false
        syncSegment(seg, layout: appState.get().layout)
        layoutSegment = seg

        let inputs = NSButton(title: "Inputs…", target: self, action: #selector(openInputsSheet(_:)))
        inputs.toolTip = "Configure NDI/SDI per slot"
        inputs.bezelStyle = .texturedRounded
        inputs.controlSize = .small
        inputs.translatesAutoresizingMaskIntoConstraints = false

        bar.addSubview(seg)
        bar.addSubview(inputs)

        accessory.view = bar
        accessory.view.autoresizesSubviews = true

        NSLayoutConstraint.activate([
            seg.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            seg.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            inputs.leadingAnchor.constraint(equalTo: seg.trailingAnchor, constant: 10),
            inputs.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            bar.heightAnchor.constraint(equalToConstant: 38),
        ])

        window.addTitlebarAccessoryViewController(accessory)
    }

    @objc private func layoutSegmentChanged(_ sender: NSSegmentedControl) {
        let mode: AppState.LayoutMode = sender.selectedSegment == 0 ? .oneUp : .fourUp
        appState.setLayout(mode)
        configureFeedBadgeLayoutMode(mode)
        pushDisplayUploadTargets()
        if let sm = sourceManager {
            updateFeedResolutionBadges(sourceManager: sm)
        }
        coordinationHost?.persistAppStateToDisk()
        mtkView.setNeedsDisplay(mtkView.bounds)
    }

    @objc private func openInputsSheet(_ sender: Any?) {
        coordinationHost?.presentSourcesSheet(presentedBy: self)
    }

    private func syncSegment(_ seg: NSSegmentedControl, layout: AppState.LayoutMode) {
        seg.selectedSegment = layout == .oneUp ? 0 : 1
    }

    private func setupFeedBadgeLabels() {
        for slot in 1 ... 4 {
            let fld = NSTextField(labelWithString: "")
            fld.translatesAutoresizingMaskIntoConstraints = false
            fld.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            fld.textColor = .white
            fld.alignment = .left
            fld.lineBreakMode = .byTruncatingTail
            fld.cell?.lineBreakMode = .byTruncatingTail
            fld.maximumNumberOfLines = 1
            fld.drawsBackground = true
            fld.backgroundColor = NSColor.black.withAlphaComponent(0.55)
            fld.isBordered = false
            fld.isEditable = false
            fld.isSelectable = false
            fld.toolTip = "Incoming resolution for slot \(slot)"
            feedBadgeOverlay.addSubview(fld)
            feedBadgeLabels.append(fld)
        }

        let o = feedBadgeOverlay
        let badges = feedBadgeLabels
        guard badges.count == 4 else { return }

        let badgeSlot1FourUpTrailingConstraint = badges[0].trailingAnchor.constraint(lessThanOrEqualTo: o.centerXAnchor, constant: -8)
        badgeSlot1FourUpTrailing = badgeSlot1FourUpTrailingConstraint

        NSLayoutConstraint.activate([
            badges[0].leadingAnchor.constraint(equalTo: o.leadingAnchor, constant: 10),
            badges[0].topAnchor.constraint(equalTo: o.topAnchor, constant: 10),
            badgeSlot1FourUpTrailingConstraint,

            badges[1].leadingAnchor.constraint(equalTo: o.centerXAnchor, constant: 10),
            badges[1].topAnchor.constraint(equalTo: o.topAnchor, constant: 10),
            badges[1].trailingAnchor.constraint(lessThanOrEqualTo: o.trailingAnchor, constant: -8),

            badges[2].leadingAnchor.constraint(equalTo: o.leadingAnchor, constant: 10),
            badges[2].topAnchor.constraint(equalTo: o.centerYAnchor, constant: 10),
            badges[2].trailingAnchor.constraint(lessThanOrEqualTo: o.centerXAnchor, constant: -8),

            badges[3].leadingAnchor.constraint(equalTo: o.centerXAnchor, constant: 10),
            badges[3].topAnchor.constraint(equalTo: o.centerYAnchor, constant: 10),
            badges[3].trailingAnchor.constraint(lessThanOrEqualTo: o.trailingAnchor, constant: -8),
        ])
    }

    private func configureFeedBadgeLayoutMode(_ layout: AppState.LayoutMode) {
        guard feedBadgeLabels.count == 4 else { return }

        switch layout {
        case .oneUp:
            badgeSlot1FourUpTrailing?.isActive = false
            feedBadgeLabels[0].isHidden = false
            feedBadgeLabels[1].isHidden = true
            feedBadgeLabels[2].isHidden = true
            feedBadgeLabels[3].isHidden = true
        case .fourUp:
            badgeSlot1FourUpTrailing?.isActive = true
            feedBadgeLabels[0].isHidden = false
            feedBadgeLabels[1].isHidden = false
            feedBadgeLabels[2].isHidden = false
            feedBadgeLabels[3].isHidden = false
        }
    }

    private func feedBadgeString(slot: Int, snap: AppState.Snapshot, dims: [Int: (width: Int, height: Int)]) -> String {
        let src = snap.slots[slot]
        let kindLabel: String = switch src {
        case nil:
            ""
        case .ndi:
            "NDI "
        case .sdi:
            "SDI "
        }
        guard src != nil else { return "" }
        let w = dims[slot]?.width ?? 0
        let h = dims[slot]?.height ?? 0
        if w > 0, h > 0 {
            return "\(kindLabel)\(w)×\(h)"
        }
        return "\(kindLabel)—"
    }

    private func updateFeedResolutionBadges(sourceManager: SourceManager) {
        guard feedBadgeLabels.count == 4 else { return }
        let snap = appState.get()
        let dims = sourceManager.feedDimensionsBySlot()

        if snap.layout == .oneUp {
            feedBadgeLabels[0].toolTip = "Incoming resolution for slot \(snap.primarySlot) (1-up)"
            feedBadgeLabels[0].stringValue = feedBadgeString(slot: snap.primarySlot, snap: snap, dims: dims)
            return
        }

        for idx in 0 ..< 4 {
            let slot = idx + 1
            feedBadgeLabels[idx].stringValue = feedBadgeString(slot: slot, snap: snap, dims: dims)
        }
    }
}
