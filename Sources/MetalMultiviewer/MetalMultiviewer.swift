import AppKit

@MainActor @main
final class MetalMultiviewerApp: NSObject, NSApplicationDelegate {
    private let appState = AppState()
    private lazy var settingsStore = SettingsStore(url: ConfigLoader.persistedConfigURL())
    private lazy var controlServerManager = ControlServerManager(state: appState)

    private var window: NSWindow?
    private var prefsWindow: NSWindow?

    private let viewMenuIdentifier = NSUserInterfaceItemIdentifier("metalMV.viewMenu")

    private var rootViewController: MainViewController?
    private var activePlayback = MonitorPlayback.from(config: .empty)

    static func main() {
        let app = NSApplication.shared
        let delegate = MetalMultiviewerApp()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppBranding.installApplicationIcon()

        let cfg = (try? settingsStore.load()) ?? .empty

        appState.setLayout(ConfigLoader.defaultLayout(config: cfg))
        if let p = cfg.primarySlot, (1 ... 4).contains(p) {
            appState.setPrimarySlot(p)
        }

        if let slots = cfg.slots {
            for (slotKey, value) in slots {
                guard let slot = Int(slotKey) else { continue }
                if let src = try? ControlServer.parseSourceRef(value) {
                    try? appState.setSource(slot: slot, source: src)
                }
            }
        }

        installMainMenu()

        controlServerManager.apply(
            enabled: ConfigLoader.effectiveControlEnabled(config: cfg),
            port: ConfigLoader.effectivePort(config: cfg),
            bindAddress: ConfigLoader.persistedControlBindAddress(config: cfg)
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteAppStateChange(_:)),
            name: .metalMultiviewerAppStateChanged,
            object: nil
        )

        let playback = MonitorPlayback.from(config: cfg)
        activePlayback = playback
        let mainVC = MainViewController(state: appState, playback: playback)
        mainVC.coordinationHost = self
        rootViewController = mainVC

        let mainWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        mainWindow.title = AppBranding.displayName
        mainWindow.minSize = NSSize(width: 480, height: 270)
        mainWindow.contentViewController = mainVC
        mainWindow.setContentSize(NSSize(width: 1280, height: 720))
        mainWindow.center()
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()

        self.window = mainWindow

        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func handleRemoteAppStateChange(_ notification: Notification) {
        persistAppStateToDisk()
        rootViewController?.syncTitleBarLayout(with: appState.get().layout)
    }

    /// Persists current layout + quad sources to the same JSON as Preferences / launch.
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
            try settingsStore.save(cfg)
        } catch {
            // Best-effort persistence; avoid crashing the UI shell.
        }
    }

    func presentSourcesSheet(presentedBy host: MainViewController) {
        let snap = appState.get()
        let editor = SourcesEditorViewController(appState: appState, snapshot: snap) { [weak self, weak host] in
            self?.persistAppStateToDisk()
            guard let self, let host else { return }
            host.syncTitleBarLayout(with: self.appState.get().layout)
        }
        host.presentAsSheet(editor)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appName = AppBranding.displayName
        let appMenuItem = NSMenuItem(title: appName, action: nil, keyEquivalent: "")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        appMenu.addItem(hideItem)

        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)

        appMenuItem.submenu = appMenu

        let viewRoot = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        mainMenu.addItem(viewRoot)

        let viewMenu = NSMenu(title: "View")
        viewMenu.identifier = viewMenuIdentifier
        viewMenu.delegate = self

        let oneUp = NSMenuItem(
            title: "1-Up Layout",
            action: #selector(setLayoutFromViewMenu(_:)),
            keyEquivalent: "1"
        )
        oneUp.target = self
        oneUp.tag = LayoutMenuTag.oneUp.rawValue
        viewMenu.addItem(oneUp)

        let fourUp = NSMenuItem(
            title: "4-Up Layout",
            action: #selector(setLayoutFromViewMenu(_:)),
            keyEquivalent: "4"
        )
        fourUp.target = self
        fourUp.tag = LayoutMenuTag.fourUp.rawValue
        viewMenu.addItem(fourUp)

        viewMenu.addItem(NSMenuItem.separator())

        let sources = NSMenuItem(
            title: "Configure Inputs…",
            action: #selector(showConfigureInputs(_:)),
            keyEquivalent: "i"
        )
        sources.target = self
        sources.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(sources)

        viewRoot.submenu = viewMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    private enum LayoutMenuTag: Int {
        case oneUp = 1
        case fourUp = 4
    }

    @objc private func setLayoutFromViewMenu(_ sender: NSMenuItem) {
        let mode: AppState.LayoutMode
        switch sender.tag {
        case LayoutMenuTag.oneUp.rawValue: mode = .oneUp
        case LayoutMenuTag.fourUp.rawValue: mode = .fourUp
        default: return
        }
        appState.setLayout(mode)
        rootViewController?.syncTitleBarLayout(with: mode)
        persistAppStateToDisk()
    }

    @objc private func showConfigureInputs(_ sender: Any?) {
        guard let host = rootViewController else { return }
        presentSourcesSheet(presentedBy: host)
    }

    @objc private func showPreferences(_ sender: Any?) {
        if prefsWindow == nil {
            let initial = (try? settingsStore.load()) ?? .empty
            let vc = PreferencesViewController(
                settingsStore: settingsStore,
                controlManager: controlServerManager,
                config: initial,
                appliedNdiHighBandwidth: activePlayback.ndiBandwidth >= 100,
                appliedPreviewMaxFPS: activePlayback.previewMaxFPS
            )

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 500, height: 330)),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Preferences"
            w.center()
            w.contentViewController = vc
            let prefsSize = NSSize(width: 500, height: 330)
            w.setContentSize(prefsSize)
            w.contentMinSize = prefsSize
            w.contentMaxSize = prefsSize
            w.isReleasedWhenClosed = false
            prefsWindow = w
        }

        guard let prefsWindow else { return }
        (prefsWindow.contentViewController as? PreferencesViewController)?.reloadFromDisk()
        prefsWindow.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
    }
}

extension MetalMultiviewerApp: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu.identifier == viewMenuIdentifier else { return }
        let current = appState.get().layout.rawValue
        for item in menu.items {
            guard item.tag == LayoutMenuTag.oneUp.rawValue || item.tag == LayoutMenuTag.fourUp.rawValue else {
                continue
            }
            item.state = item.tag == current ? .on : .off
        }
    }
}
