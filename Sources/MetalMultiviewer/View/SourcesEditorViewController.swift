import AppKit

/// Configure slots: combo lists populated from NDI Finder + SDI presets; always editable for custom refs.
@MainActor
final class SourcesEditorViewController: NSViewController {
    /// Sentinel for an empty assignment (shown to the user; stored as absent slot).
    static let noneChoice = SourceDisplayLabels.noneChoice
    private static let noneDisplayLabel = SourceDisplayLabels.noneDisplayLabel

    private let appState: AppState
    private let onCommitted: () -> Void

    private var slotCombos: [NSComboBox] = []
    /// Last successful NDI scan (`ndi:…` persistence strings).
    private var discoveredNDI: [String] = []
    /// Maps combo row label → persistence ref (`ndi:…`, `sdi:N`, or none sentinel).
    private var refByDisplayLabel: [String: String] = [:]

    private let titleField = NSTextField(labelWithString: "Configure Inputs")
    private let subtitleField = NSTextField(labelWithString: "Assign a live source to each multiview slot.")
    private let scanSummaryField = NSTextField(labelWithString: "Scanning…")
    private let scanDetailField = NSTextField(wrappingLabelWithString: "")
    private var refreshFeedsButton: NSButton?
    private var slotsSectionTopToDetail: NSLayoutConstraint?
    private var slotsSectionTopToSummary: NSLayoutConstraint?

    init(appState: AppState, snapshot: AppState.Snapshot, onCommitted: @escaping () -> Void) {
        self.appState = appState
        self.onCommitted = onCommitted
        super.init(nibName: nil, bundle: nil)

        preferredContentSize = NSSize(width: 560, height: 360)

        for slot in 1 ... 4 {
            let box = NSComboBox()
            box.isEditable = true
            box.completes = true
            box.hasVerticalScroller = true
            box.numberOfVisibleItems = 12
            box.placeholderString = "Choose or type ndi:… / sdi:N"
            if let src = snapshot.slots[slot] {
                box.stringValue = SourceDisplayLabels.displayLabel(for: src.persistenceString)
            } else {
                box.stringValue = Self.noneDisplayLabel
            }
            slotCombos.append(box)
        }
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func loadView() {
        self.view = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        view.wantsLayer = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleField.font = .boldSystemFont(ofSize: 15)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        subtitleField.font = .systemFont(ofSize: 12)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.translatesAutoresizingMaskIntoConstraints = false

        let discoverySectionLabel = sectionHeader("Available inputs")
        let slotsSectionLabel = sectionHeader("Multiview slots")

        scanSummaryField.font = .systemFont(ofSize: 12, weight: .medium)
        scanSummaryField.textColor = .labelColor
        scanSummaryField.translatesAutoresizingMaskIntoConstraints = false
        scanSummaryField.lineBreakMode = .byTruncatingTail

        scanDetailField.font = .systemFont(ofSize: 11)
        scanDetailField.textColor = .tertiaryLabelColor
        scanDetailField.translatesAutoresizingMaskIntoConstraints = false
        scanDetailField.maximumNumberOfLines = 2

        let refreshBtn = NSButton(title: "Scan", target: self, action: #selector(refreshFeeds(_:)))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.translatesAutoresizingMaskIntoConstraints = false
        refreshBtn.toolTip = "Scan the network for NDI senders (SDI devices are listed automatically)"
        refreshFeedsButton = refreshBtn

        let okBtn = NSButton(title: "OK", target: self, action: #selector(ok(_:)))
        okBtn.translatesAutoresizingMaskIntoConstraints = false
        okBtn.keyEquivalent = "\r"
        okBtn.bezelStyle = .rounded

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.bezelStyle = .rounded

        view.addSubview(titleField)
        view.addSubview(subtitleField)
        view.addSubview(discoverySectionLabel)
        view.addSubview(scanSummaryField)
        view.addSubview(scanDetailField)
        view.addSubview(refreshBtn)
        view.addSubview(slotsSectionLabel)
        view.addSubview(okBtn)
        view.addSubview(cancelBtn)

        let margin: CGFloat = 20
        let sectionGap: CGFloat = 14
        let rowGap: CGFloat = 10

        var constraints: [NSLayoutConstraint] = [
            titleField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin),
            titleField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
            titleField.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 4),

            discoverySectionLabel.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            discoverySectionLabel.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            discoverySectionLabel.topAnchor.constraint(equalTo: subtitleField.bottomAnchor, constant: sectionGap),

            scanSummaryField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            scanSummaryField.topAnchor.constraint(equalTo: discoverySectionLabel.bottomAnchor, constant: 8),
            scanSummaryField.trailingAnchor.constraint(lessThanOrEqualTo: refreshBtn.leadingAnchor, constant: -12),

            refreshBtn.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            refreshBtn.centerYAnchor.constraint(equalTo: scanSummaryField.centerYAnchor),
            refreshBtn.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),

            scanDetailField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            scanDetailField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            scanDetailField.topAnchor.constraint(equalTo: scanSummaryField.bottomAnchor, constant: 4),

            slotsSectionLabel.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            slotsSectionLabel.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
        ]

        slotsSectionTopToDetail = slotsSectionLabel.topAnchor.constraint(
            equalTo: scanDetailField.bottomAnchor,
            constant: sectionGap
        )
        slotsSectionTopToSummary = slotsSectionLabel.topAnchor.constraint(
            equalTo: scanSummaryField.bottomAnchor,
            constant: sectionGap
        )
        slotsSectionTopToSummary?.isActive = true

        var anchor = slotsSectionLabel.bottomAnchor
        for (idx, combo) in slotCombos.enumerated() {
            let row = slotRow(slot: idx + 1, combo: combo)
            view.addSubview(row)
            constraints.append(contentsOf: [
                row.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
                row.topAnchor.constraint(equalTo: anchor, constant: rowGap),
            ])
            anchor = row.bottomAnchor
        }

        constraints.append(contentsOf: [
            okBtn.topAnchor.constraint(equalTo: anchor, constant: 20),
            okBtn.bottomAnchor.constraint(equalTo: cancelBtn.bottomAnchor),
            okBtn.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -10),
            cancelBtn.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            cancelBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin),
        ])

        NSLayoutConstraint.activate(constraints)

        refillAllCombos(usingNDIScan: discoveredNDI, statusHint: nil)
        Task { await self.runInitialNDIScan() }
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let lbl = NSTextField(labelWithString: text)
        lbl.font = .systemFont(ofSize: 11, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }

    private func slotRow(slot: Int, combo: NSComboBox) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSTextField(labelWithString: "\(slot)")
        badge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.alignment = .center
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let badgePlate = NSView()
        badgePlate.wantsLayer = true
        badgePlate.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        badgePlate.layer?.cornerRadius = 6
        badgePlate.translatesAutoresizingMaskIntoConstraints = false
        badgePlate.addSubview(badge)

        combo.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(badgePlate)
        row.addSubview(combo)

        NSLayoutConstraint.activate([
            badgePlate.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            badgePlate.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            badgePlate.widthAnchor.constraint(equalToConstant: 28),
            badgePlate.heightAnchor.constraint(equalToConstant: 28),

            badge.centerXAnchor.constraint(equalTo: badgePlate.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: badgePlate.centerYAnchor),

            combo.leadingAnchor.constraint(equalTo: badgePlate.trailingAnchor, constant: 10),
            combo.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            combo.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            combo.heightAnchor.constraint(equalToConstant: 24),

            row.heightAnchor.constraint(equalToConstant: 32),
        ])

        return row
    }

    // MARK: - Display labels

    private func persistenceRef(forComboValue raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == Self.noneDisplayLabel || trimmed == Self.noneChoice {
            return Self.noneChoice
        }
        if let mapped = refByDisplayLabel[trimmed] {
            return mapped
        }
        if trimmed.lowercased().hasPrefix("ndi:") || trimmed.lowercased().hasPrefix("sdi:") {
            return trimmed
        }
        return trimmed
    }

    private func displayLabelForStoredRef(_ ref: String) -> String {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == Self.noneChoice { return Self.noneDisplayLabel }
        return SourceDisplayLabels.displayLabel(for: normalized)
    }

    // MARK: - Combo population

    private func refillAllCombos(usingNDIScan ndi: [String], statusHint: ScanPresentation?) {
        discoveredNDI = ndi.sorted()
        let baseItems = choiceList(ndiLines: discoveredNDI)
        refByDisplayLabel = Dictionary(uniqueKeysWithValues: baseItems.map { ($0.label, $0.ref) })
        for box in slotCombos {
            let preservedRef = persistenceRef(forComboValue: box.stringValue)
            repopulateCombo(box, preservingRef: preservedRef, baseItems: baseItems)
        }
        if let statusHint {
            applyScanPresentation(statusHint)
        }
    }

    private struct ScanPresentation {
        var summary: String
        var detail: String?
    }

    private func applyScanPresentation(_ p: ScanPresentation) {
        scanSummaryField.stringValue = p.summary
        scanDetailField.stringValue = p.detail ?? ""
        let showDetail = !(p.detail?.isEmpty ?? true)
        scanDetailField.isHidden = !showDetail
        slotsSectionTopToDetail?.isActive = showDetail
        slotsSectionTopToSummary?.isActive = !showDetail
        preferredContentSize = NSSize(width: 560, height: showDetail ? 400 : 360)
    }

    private func makeScanPresentation(ndiLines: [String], technicalStatus: String) -> ScanPresentation {
        let ndiCount = ndiLines.count
        let deckCount = VideoInputDiscovery.deckLinkDeviceCount()

        var summaryParts: [String] = []
        if ndiCount > 0 {
            summaryParts.append("\(ndiCount) NDI source\(ndiCount == 1 ? "" : "s")")
        } else {
            summaryParts.append("No NDI sources found")
        }
        if deckCount > 0 {
            summaryParts.append("\(deckCount) SDI device\(deckCount == 1 ? "" : "s")")
        } else {
            summaryParts.append("No SDI devices")
        }

        let detail: String? = technicalStatus.contains("Bonjour")
            || technicalStatus.contains("libndi")
            || technicalStatus.contains("not found")
            ? technicalStatus
            : nil

        return ScanPresentation(summary: summaryParts.joined(separator: " · "), detail: detail)
    }

    private func repopulateCombo(_ box: NSComboBox, preservingRef selectionRef: String, baseItems: [ChoiceItem]) {
        var labels = baseItems.map(\.label)

        let pickRef = selectionRef == Self.noneChoice ? Self.noneChoice : selectionRef
        let pickLabel = displayLabelForStoredRef(pickRef)
        if pickRef != Self.noneChoice, refByDisplayLabel[pickLabel] == nil {
            labels.insert(pickLabel, at: min(1, labels.count))
            refByDisplayLabel[pickLabel] = pickRef
        }

        box.removeAllItems()
        box.addItems(withObjectValues: labels)
        if labels.contains(pickLabel) {
            box.stringValue = pickLabel
        } else {
            box.stringValue = Self.noneDisplayLabel
        }
    }

    private struct ChoiceItem {
        var label: String
        var ref: String
    }

    private func choiceList(ndiLines: [String]) -> [ChoiceItem] {
        var items: [ChoiceItem] = [ChoiceItem(label: Self.noneDisplayLabel, ref: Self.noneChoice)]

        let ndiSorted = ndiLines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var usedLabels = Set<String>([Self.noneDisplayLabel])
        for ndi in ndiSorted {
            var label = SourceDisplayLabels.displayLabel(for: ndi)
            if usedLabels.contains(label) {
                label = ndi
            }
            usedLabels.insert(label)
            items.append(ChoiceItem(label: label, ref: ndi))
        }

        for sdi in VideoInputDiscovery.deckLinkBackedSDIRefs() {
            let label = SourceDisplayLabels.displayLabel(for: sdi)
            items.append(ChoiceItem(label: label, ref: sdi))
        }

        return items
    }

    // MARK: - Scanning

    private func runInitialNDIScan() async {
        applyScanPresentation(ScanPresentation(summary: "Scanning network…", detail: nil))
        refreshFeedsButton?.isEnabled = false
        let outcome = await VideoInputDiscovery.discoverNDISources(scanSeconds: 2.8)
        let deck = VideoInputDiscovery.deckLinkStatusLine(maxNames: 6)
        let mergedTechnical = outcome.statusLine + "\n\n" + deck
        let presentation = makeScanPresentation(ndiLines: outcome.lines, technicalStatus: outcome.statusLine)
        refillAllCombos(usingNDIScan: outcome.lines, statusHint: presentation)
        scanDetailField.toolTip = mergedTechnical
        refreshFeedsButton?.isEnabled = true
    }

    @objc private func refreshFeeds(_ sender: Any?) {
        Task { await self.runInitialNDIScan() }
    }

    @objc private func ok(_ sender: Any?) {
        for (idx, box) in slotCombos.enumerated() {
            let slot = idx + 1
            let ref = persistenceRef(forComboValue: box.stringValue)
            do {
                if ref == Self.noneChoice {
                    try appState.setSource(slot: slot, source: nil)
                } else {
                    let parsed = try ControlServer.parseSourceRef(ref)
                    try appState.setSource(slot: slot, source: parsed)
                }
            } catch {
                presentValidationAlert(forSlot: slot, error: error)
                return
            }
        }
        onCommitted()
        dismiss(nil)
    }

    @objc private func cancel(_ sender: Any?) {
        dismiss(nil)
    }

    private func presentValidationAlert(forSlot slot: Int, error: Error) {
        let alert = NSAlert()
        alert.messageText = "Invalid source for slot \(slot)"
        alert.informativeText = "Use None, pick from the list, or type a full reference such as ndi:Host (Name) or sdi:0.\n\n\(error)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        guard let win = presentingViewController?.view.window ?? view.window else {
            alert.runModal()
            return
        }
        alert.beginSheetModal(for: win) { _ in }
    }
}
