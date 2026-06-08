import AppKit

/// Stream Deck / scripting control endpoint: enable, port, URL, persisted beside layout/slots in `config.json`.
@MainActor
final class PreferencesViewController: NSViewController {
    private enum Layout {
        static let margin: CGFloat = 20
        static let labelWidth: CGFloat = 88
        static let labelFieldGap: CGFloat = 10
        static let rowSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 22
        static var fieldLeading: CGFloat { margin + labelWidth + labelFieldGap }
    }

    private let settingsStore: SettingsStore
    private let controlManager: ControlServerManager
    /// NDI bandwidth mode currently running (High = program stream).
    private let appliedNdiHighBandwidth: Bool
    /// Preview FPS cap currently running.
    private let appliedPreviewMaxFPS: Double

    private var working: AppConfig
    private nonisolated(unsafe) var observer: NSObjectProtocol?
    private var bindAddressChoices: [ControlBindOption] = []

    private let enableCheckbox = NSButton(checkboxWithTitle: "Enable control server", target: nil, action: nil)
    private let bindPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let portField = NSTextField(string: "8080")
    private let urlField = NSTextField(string: "")
    private let statusField = NSTextField(wrappingLabelWithString: "")
    private let copyButton = NSButton(title: "Copy URL", target: nil, action: nil)
    private let fpsField = NSTextField(string: "30")
    private let ndiBandwidthSegment = NSSegmentedControl(
        labels: ["High", "Low"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let restartButton = NSButton(title: "Restart to Apply", target: nil, action: nil)

    init(
        settingsStore: SettingsStore,
        controlManager: ControlServerManager,
        config: AppConfig,
        appliedNdiHighBandwidth: Bool,
        appliedPreviewMaxFPS: Double
    ) {
        self.settingsStore = settingsStore
        self.controlManager = controlManager
        self.appliedNdiHighBandwidth = appliedNdiHighBandwidth
        self.appliedPreviewMaxFPS = appliedPreviewMaxFPS
        self.working = config
        super.init(nibName: nil, bundle: nil)

        enableCheckbox.target = self
        enableCheckbox.action = #selector(enableDidChange(_:))
        bindPopUp.target = self
        bindPopUp.action = #selector(bindAddressDidChange(_:))
        copyButton.target = self
        copyButton.action = #selector(copyURL(_:))
        ndiBandwidthSegment.target = self
        ndiBandwidthSegment.action = #selector(ndiBandwidthDidChange(_:))
        restartButton.target = self
        restartButton.action = #selector(restartApp(_:))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override func loadView() {
        preferredContentSize = NSSize(width: 500, height: 330)
        let container = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        self.view = container
        layoutUI(in: container)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        urlField.isEditable = false
        urlField.isSelectable = true
        urlField.isBezeled = false
        urlField.isBordered = false
        urlField.drawsBackground = false
        urlField.backgroundColor = .clear
        urlField.focusRingType = .none
        urlField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        urlField.textColor = .labelColor

        statusField.maximumNumberOfLines = 4
        statusField.font = .systemFont(ofSize: 11)
        statusField.textColor = .secondaryLabelColor

        portField.alignment = .right
        fpsField.alignment = .right

        copyButton.bezelStyle = .rounded
        styleRestartButton()
        restartButton.isHidden = true

        observer = NotificationCenter.default.addObserver(
            forName: ControlServerManager.statusDidChangeNotification,
            object: controlManager,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncFromManager()
            }
        }

        reloadFromWorking()
        syncFromManager()
    }

    func reloadFromDisk() {
        if let cfg = try? settingsStore.load() {
            working = cfg
        }
        reloadFromWorking()
        syncFromManager()
    }

    private func layoutUI(in container: NSView) {
        let controlHeader = sectionHeader("Control")
        let videoHeader = sectionHeader("Video")
        let separator = NSBox()
        separator.boxType = .separator

        let bindLabel = formLabel("Listen on:")
        let portLabel = formLabel("Port:")
        let urlLabel = formLabel("URL:")
        let fpsLabel = formLabel("Max FPS:")
        let ndiLabel = formLabel("NDI:")

        for view in [
            controlHeader, enableCheckbox, bindLabel, bindPopUp, portLabel, portField,
            urlLabel, urlField, copyButton, statusField, separator,
            videoHeader, fpsLabel, fpsField, ndiLabel, ndiBandwidthSegment, restartButton,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
        }

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
            container.heightAnchor.constraint(equalToConstant: preferredContentSize.height),

            controlHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            controlHeader.topAnchor.constraint(equalTo: container.topAnchor, constant: Layout.margin),

            enableCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            enableCheckbox.topAnchor.constraint(equalTo: controlHeader.bottomAnchor, constant: Layout.rowSpacing),

            bindLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            bindLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            bindLabel.firstBaselineAnchor.constraint(equalTo: bindPopUp.firstBaselineAnchor),
            bindPopUp.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            bindPopUp.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            bindPopUp.topAnchor.constraint(equalTo: enableCheckbox.bottomAnchor, constant: Layout.rowSpacing),

            portLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            portLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            portLabel.firstBaselineAnchor.constraint(equalTo: portField.firstBaselineAnchor),
            portField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            portField.widthAnchor.constraint(equalToConstant: 72),
            portField.topAnchor.constraint(equalTo: bindPopUp.bottomAnchor, constant: Layout.rowSpacing),

            urlLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            urlLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            urlLabel.firstBaselineAnchor.constraint(equalTo: urlField.firstBaselineAnchor),
            urlField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            urlField.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -10),
            urlField.topAnchor.constraint(equalTo: portField.bottomAnchor, constant: Layout.rowSpacing),

            copyButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            copyButton.centerYAnchor.constraint(equalTo: urlField.centerYAnchor),

            statusField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            statusField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            statusField.topAnchor.constraint(equalTo: urlField.bottomAnchor, constant: 10),

            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            separator.topAnchor.constraint(equalTo: statusField.bottomAnchor, constant: Layout.sectionSpacing),

            videoHeader.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            videoHeader.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: Layout.sectionSpacing),

            fpsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            fpsLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            fpsLabel.firstBaselineAnchor.constraint(equalTo: fpsField.firstBaselineAnchor),
            fpsField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            fpsField.widthAnchor.constraint(equalToConstant: 72),
            fpsField.topAnchor.constraint(equalTo: videoHeader.bottomAnchor, constant: Layout.rowSpacing),

            ndiLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.margin),
            ndiLabel.widthAnchor.constraint(equalToConstant: Layout.labelWidth),
            ndiLabel.firstBaselineAnchor.constraint(equalTo: ndiBandwidthSegment.firstBaselineAnchor),
            ndiBandwidthSegment.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Layout.fieldLeading),
            ndiBandwidthSegment.widthAnchor.constraint(equalToConstant: 120),
            ndiBandwidthSegment.topAnchor.constraint(equalTo: fpsField.bottomAnchor, constant: Layout.rowSpacing),

            restartButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Layout.margin),
            restartButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Layout.margin),
        ])
    }

    private func sectionHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize(for: .regular))
        return label
    }

    private func formLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        return label
    }

    private func styleRestartButton() {
        restartButton.bezelStyle = .rounded
        let title = "Restart to Apply"
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.systemRed,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
        ]
        restartButton.attributedTitle = NSAttributedString(string: title, attributes: attributes)
        restartButton.attributedAlternateTitle = NSAttributedString(string: title, attributes: attributes)
    }

    private func reloadFromWorking() {
        enableCheckbox.state = ConfigLoader.effectiveControlEnabled(config: working) ? .on : .off
        let p = ConfigLoader.persistedPreferredPort(config: working)
        portField.stringValue = "\(Int(p))"
        portField.delegate = self

        reloadBindPopUp()

        let fps = working.previewMaxFPS ?? 30
        fpsField.stringValue = "\(Int(fps.rounded()))"
        fpsField.delegate = self
        ndiBandwidthSegment.selectedSegment = (working.ndiFullQuality != false) ? 0 : 1

        updateControlURLPreview()
        updateRestartVisibility()
    }

    private func reloadBindPopUp() {
        bindAddressChoices = bindOptionsIncludingSaved()
        bindPopUp.removeAllItems()
        for (idx, option) in bindAddressChoices.enumerated() {
            bindPopUp.addItem(withTitle: option.label)
            bindPopUp.item(at: idx)?.tag = idx
        }

        let saved = ConfigLoader.persistedControlBindAddress(config: working)
        if let idx = bindAddressChoices.firstIndex(where: { $0.address == saved }) {
            bindPopUp.selectItem(at: idx)
        } else if !bindAddressChoices.isEmpty {
            bindPopUp.selectItem(at: 0)
        }
    }

    private func bindOptionsIncludingSaved() -> [ControlBindOption] {
        var options = NetworkInterfaceDiscovery.bindOptions()
        let saved = ConfigLoader.persistedControlBindAddress(config: working)
        if !options.contains(where: { $0.address == saved }) {
            options.append(ControlBindOption(address: saved, label: saved))
        }
        return options
    }

    private func selectedBindAddress() -> String {
        let idx = bindPopUp.indexOfSelectedItem
        guard idx >= 0, idx < bindAddressChoices.count else {
            return NetworkInterfaceDiscovery.localhostAddress
        }
        return bindAddressChoices[idx].address
    }

    private func updateControlURLPreview() {
        let trimmed = portField.stringValue.trimmingCharacters(in: .whitespaces)
        let port = Int(trimmed).flatMap { (1 ... 65535).contains($0) ? $0 : nil }
            ?? Int(ConfigLoader.persistedPreferredPort(config: working))
        urlField.stringValue = NetworkInterfaceDiscovery.controlURL(
            bindAddress: selectedBindAddress(),
            port: port
        )
    }

    private func setStatus(_ message: String, color: NSColor = .secondaryLabelColor) {
        statusField.stringValue = message
        statusField.textColor = color
    }

    @objc private func enableDidChange(_ sender: NSButton) {
        if sender.state == .on {
            working.controlEnabled = true
            persistAndApply()
        } else {
            working.controlEnabled = false
            persistDisableOnly()
        }
    }

    @objc private func bindAddressDidChange(_ sender: NSPopUpButton) {
        working.controlBindAddress = selectedBindAddress()
        updateControlURLPreview()
        persistAndApply()
    }

    @objc private func ndiBandwidthDidChange(_ sender: NSSegmentedControl) {
        working.ndiFullQuality = sender.selectedSegment == 0
        persistVideoSettings()
        updateRestartVisibility()
    }

    private func updateRestartVisibility() {
        let uiHigh = ndiBandwidthSegment.selectedSegment == 0
        let ndiChanged = uiHigh != appliedNdiHighBandwidth
        let fpsChanged = uiPreviewMaxFPS().map { Int($0.rounded()) != Int(appliedPreviewMaxFPS.rounded()) } ?? false
        restartButton.isHidden = !(ndiChanged || fpsChanged)
    }

    private func uiPreviewMaxFPS() -> Double? {
        let trimmed = fpsField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let fps = Double(trimmed), fps >= 5, fps <= 120 else { return nil }
        return fps
    }

    @objc private func restartApp(_ sender: Any?) {
        guard syncVideoFieldsIntoWorking() else {
            setStatus("Max FPS must be 5–120.", color: .systemOrange)
            reloadFromWorking()
            return
        }
        do {
            try settingsStore.save(working)
        } catch {
            setStatus("Could not save settings: \(error)", color: .systemRed)
            return
        }

        relaunchApplication()
        NSApp.terminate(nil)
    }

    private func relaunchApplication() {
        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = ["-n", bundleURL.path]
            try? task.run()
            return
        }

        let args = ProcessInfo.processInfo.arguments
        guard let executable = args.first else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        if args.count > 1 {
            task.arguments = Array(args.dropFirst())
        }
        try? task.run()
    }

    private func persistDisableOnly() {
        do {
            try settingsStore.save(working)
        } catch {
            setStatus("Could not save settings: \(error)", color: .systemRed)
            syncFromManager()
            return
        }
        syncControlServerFromWorking()
        syncFromManager()
    }

    @objc private func copyURL(_ sender: Any?) {
        let s = urlField.stringValue
        guard !s.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    private func persistAndApply() {
        guard syncPortIntoWorking() else {
            setStatus("Port must be 1–65535.", color: .systemOrange)
            reloadFromWorking()
            syncFromManager()
            return
        }

        working.controlBindAddress = selectedBindAddress()

        do {
            try settingsStore.save(working)
        } catch {
            setStatus("Could not save settings: \(error)", color: .systemRed)
            return
        }

        syncControlServerFromWorking()
        syncFromManager()
    }

    private func persistPortAndApplyOnEndEditing() {
        updateControlURLPreview()
        persistAndApply()
    }

    private func persistVideoSettings() {
        guard syncVideoFieldsIntoWorking() else {
            setStatus("Max FPS must be 5–120.", color: .systemOrange)
            reloadFromWorking()
            return
        }
        do {
            try settingsStore.save(working)
        } catch {
            setStatus("Could not save settings: \(error)", color: .systemRed)
        }
        updateRestartVisibility()
    }

    private func syncPortIntoWorking() -> Bool {
        let trimmed = portField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let p = Int(trimmed), (1 ... 65535).contains(p) else { return false }
        working.port = p
        return true
    }

    private func syncVideoFieldsIntoWorking() -> Bool {
        let trimmed = fpsField.stringValue.trimmingCharacters(in: .whitespaces)
        guard let fps = Double(trimmed), fps >= 5, fps <= 120 else { return false }
        working.previewMaxFPS = fps
        working.ndiFullQuality = ndiBandwidthSegment.selectedSegment == 0
        return true
    }

    private func syncControlServerFromWorking() {
        let enabled = ConfigLoader.effectiveControlEnabled(config: working)
        let port = ConfigLoader.persistedPreferredPort(config: working)
        let bindAddress = ConfigLoader.persistedControlBindAddress(config: working)
        controlManager.apply(enabled: enabled, port: port, bindAddress: bindAddress)
    }

    private func syncFromManager() {
        switch controlManager.status {
        case .stopped:
            updateControlURLPreview()
            if let w = controlManager.lastWarning, !w.isEmpty {
                setStatus(w)
            } else if !ConfigLoader.effectiveControlEnabled(config: working) {
                setStatus("Control server disabled.")
            } else {
                setStatus("")
            }
        case let .running(url, _, _):
            urlField.stringValue = url
            if let w = controlManager.lastWarning, !w.isEmpty {
                setStatus(w, color: .systemOrange)
            } else {
                setStatus("")
            }
        case let .failed(msg):
            updateControlURLPreview()
            setStatus(msg, color: .systemRed)
        }
    }
}

extension PreferencesViewController: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        if (obj.object as? NSTextField) === portField {
            persistPortAndApplyOnEndEditing()
            return
        }
        if (obj.object as? NSTextField) === fpsField {
            persistVideoSettings()
        }
    }
}
