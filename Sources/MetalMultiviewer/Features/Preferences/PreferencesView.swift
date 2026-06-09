import AppKit
import SwiftUI

struct PreferencesView: View {
    @Bindable var model: MonitorAppModel

    @State private var working = AppConfig.empty
    @State private var bindAddressChoices: [ControlBindOption] = []
    @State private var controlStatusMessage = ""
    @State private var controlStatusColor: Color = .secondary
    @State private var portText = "8080"
    @State private var fpsText = "30"
    @State private var controlURL = ""
    @State private var statusObserver: NSObjectProtocol?

    private let pictureMonitoringSectionID = "pictureMonitoring"

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section("Control") {
                    Toggle("Enable control server", isOn: controlEnabledBinding)

                    LabeledContent("Listen on") {
                        Picker("Listen on", selection: bindAddressBinding) {
                            ForEach(Array(bindAddressChoices.enumerated()), id: \.offset) { idx, option in
                                Text(option.label).tag(idx)
                            }
                        }
                        .labelsHidden()
                    }

                    LabeledContent("Port") {
                        TextField("", text: $portText)
                            .frame(width: 72)
                            .onSubmit { persistPortAndApply() }
                    }

                    LabeledContent("URL") {
                        HStack {
                            Text(controlURL)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(controlURL, forType: .string)
                            }
                        }
                    }

                    if !controlStatusMessage.isEmpty {
                        Text(controlStatusMessage)
                            .font(.caption)
                            .foregroundStyle(controlStatusColor)
                    }
                }

                Section {
                    LabeledContent("Max FPS") {
                        TextField("", text: $fpsText)
                            .frame(width: 72)
                            .onSubmit { persistVideoSettings() }
                    }

                    LabeledContent("NDI Resolution") {
                        Picker("", selection: ndiBandwidthBinding) {
                            Text("High").tag(true)
                            Text("Low").tag(false)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }

                    Toggle("Scope monitor in 1-up", isOn: scopeMonitorBinding)
                        .help("In 1-up layout, show picture and vectorscope on top, RGB waveform and RGB parade below.")

                    if needsRestart {
                        Text("NDI bandwidth or Max FPS changes require a restart.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Spacer()
                            Button("Restart to Apply") {
                                restartApp()
                            }
                            .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Video")
                }

                Section("Picture monitoring") {
                    LabeledContent("Peaking") {
                        Picker("Peaking", selection: peakingColorBinding) {
                            ForEach(FocusPeakingColor.allCases, id: \.self) { color in
                                Text(color.displayName).tag(color)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    LabeledContent("Sensitivity") {
                        HStack {
                            Slider(
                                value: peakingSensitivityBinding,
                                in: Double(PictureMonitoringSettings.sensitivityRange.lowerBound) ... Double(PictureMonitoringSettings.sensitivityRange.upperBound)
                            )
                            Text(String(format: "%.2f", working.focusPeakingSensitivity ?? PictureMonitoringSettings.defaults.focusPeakingSensitivity))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                        }
                    }

                    LabeledContent("Zebra at") {
                        Picker("Zebra at", selection: zebraLevelBinding) {
                            ForEach(PictureMonitoringSettings.zebraLevelPresets, id: \.self) { preset in
                                Text("\(Int((preset * 100).rounded()))%").tag(preset)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }
                }
                .id(pictureMonitoringSectionID)

                Section {
                    Text(NdiAttribution.preferencesFooterPlainText())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .frame(minWidth: 480, minHeight: 420)
            .background(WindowChromeConfigurator(title: AppBranding.settingsWindowTitle))
            .onAppear {
                reloadFromDisk()
                installStatusObserver()
                if model.scrollPreferencesToPictureMonitoring {
                    proxy.scrollTo(pictureMonitoringSectionID, anchor: .top)
                    model.scrollPreferencesToPictureMonitoring = false
                }
            }
            .onChange(of: model.scrollPreferencesToPictureMonitoring) { _, scroll in
                if scroll {
                    proxy.scrollTo(pictureMonitoringSectionID, anchor: .top)
                    model.scrollPreferencesToPictureMonitoring = false
                }
            }
            .onDisappear {
                if let statusObserver {
                    NotificationCenter.default.removeObserver(statusObserver)
                }
            }
        }
    }

    private var needsRestart: Bool {
        let uiHigh = working.ndiFullQuality != false
        let ndiChanged = uiHigh != (model.activePlayback.ndiBandwidth >= 100)
        let fpsChanged = uiPreviewMaxFPS().map { Int($0.rounded()) != Int(model.activePlayback.previewMaxFPS.rounded()) } ?? false
        return ndiChanged || fpsChanged
    }

    private var controlEnabledBinding: Binding<Bool> {
        Binding(
            get: { ConfigLoader.effectiveControlEnabled(config: working) },
            set: { enabled in
                working.controlEnabled = enabled
                if enabled {
                    persistAndApplyControl()
                } else {
                    persistDisableControl()
                }
            }
        )
    }

    private var bindAddressBinding: Binding<Int> {
        Binding(
            get: {
                let saved = ConfigLoader.persistedControlBindAddress(config: working)
                return bindAddressChoices.firstIndex(where: { $0.address == saved }) ?? 0
            },
            set: { idx in
                guard idx >= 0, idx < bindAddressChoices.count else { return }
                working.controlBindAddress = bindAddressChoices[idx].address
                updateControlURLPreview()
                persistAndApplyControl()
            }
        )
    }

    private var ndiBandwidthBinding: Binding<Bool> {
        Binding(
            get: { working.ndiFullQuality != false },
            set: { high in
                working.ndiFullQuality = high
                persistVideoSettings()
            }
        )
    }

    private var scopeMonitorBinding: Binding<Bool> {
        Binding(
            get: { ConfigLoader.effectiveOneUpScopeMonitor(config: working) },
            set: { enabled in
                working.oneUpScopeMonitor = enabled
                saveWorkingConfig()
                model.applyOneUpScopeMonitor(enabled)
                NotificationCenter.default.post(
                    name: .metalMultiviewerScopeMonitorChanged,
                    object: nil,
                    userInfo: ["enabled": enabled]
                )
            }
        )
    }

    private var peakingColorBinding: Binding<FocusPeakingColor> {
        Binding(
            get: { ConfigLoader.effectivePictureMonitoring(config: working).focusPeakingColor },
            set: { color in
                working.focusPeakingColor = color.rawValue
                persistPictureMonitoringPrefs()
            }
        )
    }

    private var peakingSensitivityBinding: Binding<Double> {
        Binding(
            get: { Double(ConfigLoader.effectivePictureMonitoring(config: working).focusPeakingSensitivity) },
            set: { value in
                working.focusPeakingSensitivity = Float(value)
                persistPictureMonitoringPrefs()
            }
        )
    }

    private var zebraLevelBinding: Binding<Float> {
        Binding(
            get: { ConfigLoader.effectivePictureMonitoring(config: working).zebraLevel },
            set: { level in
                working.zebraLevel = level
                persistPictureMonitoringPrefs()
            }
        )
    }

    private func reloadFromDisk() {
        model.reloadWorkingConfig()
        working = model.workingConfig
        portText = "\(Int(ConfigLoader.persistedPreferredPort(config: working)))"
        let fps = working.previewMaxFPS ?? 30
        fpsText = "\(Int(fps.rounded()))"
        reloadBindPopUp()
        updateControlURLPreview()
        syncFromManager()
    }

    private func reloadBindPopUp() {
        bindAddressChoices = bindOptionsIncludingSaved()
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
        let saved = ConfigLoader.persistedControlBindAddress(config: working)
        return saved
    }

    private func updateControlURLPreview() {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        let port = Int(trimmed).flatMap { (1 ... 65535).contains($0) ? $0 : nil }
            ?? Int(ConfigLoader.persistedPreferredPort(config: working))
        controlURL = NetworkInterfaceDiscovery.controlURL(
            bindAddress: selectedBindAddress(),
            port: port
        )
    }

    private func persistPortAndApply() {
        updateControlURLPreview()
        persistAndApplyControl()
    }

    private func persistAndApplyControl() {
        guard syncPortIntoWorking() else {
            setStatus("Port must be 1–65535.", color: .orange)
            reloadFromDisk()
            return
        }
        working.controlBindAddress = selectedBindAddress()
        saveWorkingConfig()
        syncControlServerFromWorking()
        syncFromManager()
    }

    private func persistDisableControl() {
        saveWorkingConfig()
        syncControlServerFromWorking()
        syncFromManager()
    }

    private func persistVideoSettings() {
        guard syncVideoFieldsIntoWorking() else {
            setStatus("Max FPS must be 5–120.", color: .orange)
            reloadFromDisk()
            return
        }
        saveWorkingConfig()
    }

    private func persistPictureMonitoringPrefs() {
        saveWorkingConfig()
        let monitoring = ConfigLoader.effectivePictureMonitoring(config: working)
        model.applyPictureMonitoring(monitoring, persist: true)
        NotificationCenter.default.post(name: .metalMultiviewerPictureMonitoringChanged, object: nil)
    }

    private func saveWorkingConfig() {
        do {
            try model.settingsStore.save(working)
            model.reloadWorkingConfig()
            working = model.workingConfig
        } catch {
            setStatus("Could not save settings: \(error)", color: .red)
        }
    }

    private func syncPortIntoWorking() -> Bool {
        let trimmed = portText.trimmingCharacters(in: .whitespaces)
        guard let p = Int(trimmed), (1 ... 65535).contains(p) else { return false }
        working.port = p
        return true
    }

    private func syncVideoFieldsIntoWorking() -> Bool {
        let trimmed = fpsText.trimmingCharacters(in: .whitespaces)
        guard let fps = Double(trimmed), fps >= 5, fps <= 120 else { return false }
        working.previewMaxFPS = fps
        working.ndiFullQuality = working.ndiFullQuality != false
        return true
    }

    private func uiPreviewMaxFPS() -> Double? {
        let trimmed = fpsText.trimmingCharacters(in: .whitespaces)
        guard let fps = Double(trimmed), fps >= 5, fps <= 120 else { return nil }
        return fps
    }

    private func syncControlServerFromWorking() {
        let enabled = ConfigLoader.effectiveControlEnabled(config: working)
        let port = ConfigLoader.persistedPreferredPort(config: working)
        let bindAddress = ConfigLoader.persistedControlBindAddress(config: working)
        model.controlServerManager.apply(enabled: enabled, port: port, bindAddress: bindAddress, monitoringStore: model.monitoringStore)
    }

    private func syncFromManager() {
        switch model.controlServerManager.status {
        case .stopped:
            updateControlURLPreview()
            if let w = model.controlServerManager.lastWarning, !w.isEmpty {
                setStatus(w)
            } else if !ConfigLoader.effectiveControlEnabled(config: working) {
                setStatus("Control server disabled.")
            } else {
                setStatus("")
            }
        case let .running(url, _, _):
            controlURL = url
            if let w = model.controlServerManager.lastWarning, !w.isEmpty {
                setStatus(w, color: .orange)
            } else {
                setStatus("")
            }
        case let .failed(msg):
            updateControlURLPreview()
            setStatus(msg, color: .red)
        }
    }

    private func setStatus(_ message: String, color: Color = .secondary) {
        controlStatusMessage = message
        controlStatusColor = color
    }

    private func installStatusObserver() {
        statusObserver = NotificationCenter.default.addObserver(
            forName: ControlServerManager.statusDidChangeNotification,
            object: model.controlServerManager,
            queue: .main
        ) { _ in
            Task { @MainActor in
                syncFromManager()
            }
        }
    }

    private func restartApp() {
        guard syncVideoFieldsIntoWorking() else {
            setStatus("Max FPS must be 5–120.", color: .orange)
            reloadFromDisk()
            return
        }
        saveWorkingConfig()
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
}
