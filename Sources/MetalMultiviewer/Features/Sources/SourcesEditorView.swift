import SwiftUI

struct SourcesEditorView: View {
    @Bindable var model: MonitorAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var slotSelections: [Int: String] = [:]
    @State private var slotPersistenceRef: [Int: String] = [:]
    @State private var discoveredNDI: [String] = []
    @State private var choices: [SourceChoice] = []
    @State private var refByDisplayLabel: [String: String] = [:]
    @State private var scanSummary = "Scanning network…"
    @State private var scanDetail: String?
    @State private var scanToolTip = ""
    @State private var isScanning = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Available inputs") {
                    HStack {
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(scanSummary)
                                .font(.body)
                            if let scanDetail, !scanDetail.isEmpty {
                                Text(scanDetail)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .help(scanToolTip)
                            }
                        }
                        Spacer()
                        Button("Scan") {
                            Task { await runScan() }
                        }
                        .disabled(isScanning)
                    }
                }

                Section("Multiview slots") {
                    ForEach(1 ... 4, id: \.self) { slot in
                        LabeledContent("Slot \(slot)") {
                            Picker("Slot \(slot)", selection: slotBinding(slot)) {
                                ForEach(choices) { choice in
                                    Text(choice.label).tag(choice.label)
                                }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("OK") { commit() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(MonitorDesign.formMargin)
        }
        .frame(width: 520, height: scanDetail == nil ? 380 : 420)
        .onAppear {
            loadInitialSelections()
            populateChoicesImmediately()
            Task { await runScan() }
        }
    }

    private func slotBinding(_ slot: Int) -> Binding<String> {
        Binding(
            get: { slotSelections[slot] ?? SourcesDiscoveryService.noneDisplayLabel },
            set: { slotSelections[slot] = $0 }
        )
    }

    private func populateChoicesImmediately() {
        discoveredNDI = []
        refillChoices()
    }

    private func loadInitialSelections() {
        let snap = model.appState.get()
        for slot in 1 ... 4 {
            if let src = snap.slots[slot] {
                let label = SourcesDiscoveryService.displayLabel(for: src.persistenceString)
                slotSelections[slot] = label
                slotPersistenceRef[slot] = src.persistenceString
            } else {
                slotSelections[slot] = SourcesDiscoveryService.noneDisplayLabel
                slotPersistenceRef[slot] = SourcesDiscoveryService.noneChoice
            }
        }
    }

    private func runScan() async {
        isScanning = true
        scanSummary = "Scanning network…"
        scanDetail = nil
        let result = await SourcesDiscoveryService.discoverSources()
        discoveredNDI = result.ndiLines.sorted()
        scanSummary = result.presentation.summary
        scanDetail = result.presentation.detail
        scanToolTip = result.toolTip
        refillChoices()
        isScanning = false
    }

    private func refillChoices() {
        choices = SourcesDiscoveryService.choiceList(ndiLines: discoveredNDI)
        refByDisplayLabel = Dictionary(uniqueKeysWithValues: choices.map { ($0.label, $0.ref) })

        for slot in 1 ... 4 {
            let display = slotSelections[slot] ?? SourcesDiscoveryService.noneDisplayLabel
            let ref = SourcesDiscoveryService.resolvedPersistenceRef(
                displayValue: display,
                slot: slot,
                slotPersistenceRef: slotPersistenceRef,
                refByDisplayLabel: refByDisplayLabel
            )
            let pickLabel = SourcesDiscoveryService.displayLabel(for: ref)
            if choices.contains(where: { $0.label == pickLabel }) {
                slotSelections[slot] = pickLabel
            } else if ref != SourcesDiscoveryService.noneChoice,
                      SourcesDiscoveryService.isPersistenceRef(ref),
                      !choices.contains(where: { $0.ref == ref })
            {
                let extra = SourceChoice(label: pickLabel, ref: ref)
                choices.insert(extra, at: min(1, choices.count))
                refByDisplayLabel[pickLabel] = ref
                slotSelections[slot] = pickLabel
            } else if slotSelections[slot] == nil {
                slotSelections[slot] = SourcesDiscoveryService.noneDisplayLabel
            }
        }
    }

    private func commit() {
        for slot in 1 ... 4 {
            let display = slotSelections[slot] ?? SourcesDiscoveryService.noneDisplayLabel
            let ref = SourcesDiscoveryService.resolvedPersistenceRef(
                displayValue: display,
                slot: slot,
                slotPersistenceRef: slotPersistenceRef,
                refByDisplayLabel: refByDisplayLabel
            )
            do {
                if ref == SourcesDiscoveryService.noneChoice {
                    try model.appState.setSource(slot: slot, source: nil)
                    slotPersistenceRef[slot] = SourcesDiscoveryService.noneChoice
                } else {
                    let parsed = try ControlServer.parseSourceRef(ref)
                    try model.appState.setSource(slot: slot, source: parsed)
                    slotPersistenceRef[slot] = ref
                }
            } catch {
                presentValidationAlert(slot: slot, error: error)
                return
            }
        }
        model.commitSourcesEditor()
        dismiss()
    }

    private func presentValidationAlert(slot: Int, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Invalid source for slot \(slot)"
        alert.informativeText = "Use None, pick from the list, or type a full reference such as ndi:Host (Name) or sdi:0.\n\n\(error)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
