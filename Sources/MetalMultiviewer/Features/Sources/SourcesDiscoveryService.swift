import Foundation

struct SourceChoice: Identifiable, Equatable {
    var id: String { ref }
    var label: String
    var ref: String
}

struct ScanPresentation: Equatable {
    var summary: String
    var detail: String?
}

@MainActor
enum SourcesDiscoveryService {
    static let noneChoice = SourceDisplayLabels.noneChoice
    static let noneDisplayLabel = SourceDisplayLabels.noneDisplayLabel

    static func choiceList(ndiLines: [String]) -> [SourceChoice] {
        var items: [SourceChoice] = [SourceChoice(label: noneDisplayLabel, ref: noneChoice)]

        let ndiSorted = ndiLines.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var usedLabels = Set<String>([noneDisplayLabel])
        for ndi in ndiSorted {
            var label = SourceDisplayLabels.displayLabel(for: ndi)
            if usedLabels.contains(label) {
                label = ndi
            }
            usedLabels.insert(label)
            items.append(SourceChoice(label: label, ref: ndi))
        }

        for sdi in VideoInputDiscovery.deckLinkBackedSDIRefs() {
            let label = SourceDisplayLabels.displayLabel(for: sdi)
            items.append(SourceChoice(label: label, ref: sdi))
        }

        return items
    }

    static func makeScanPresentation(ndiLines: [String], technicalStatus: String) -> ScanPresentation {
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

        return ScanPresentation(
            summary: summaryParts.joined(separator: " · "),
            detail: professionalScanDetail(ndiCount: ndiCount, technicalStatus: technicalStatus)
        )
    }

    /// User-facing scan footnote; technical `statusLine` stays in the tooltip only.
    static func professionalScanDetail(ndiCount: Int, technicalStatus: String) -> String? {
        if ndiCount > 0 { return nil }

        let lower = technicalStatus.lowercased()
        if lower.contains("libndi") && (lower.contains("not found") || lower.contains("missing")) {
            return "NDI runtime not installed. Install from ndi.video and restart the app."
        }
        if lower.contains("find api") {
            return "NDI discovery is limited. Install the latest NDI runtime from ndi.video."
        }
        if lower.contains("bonjour") && lower.contains("prefer typing") {
            return "Network names shown. Confirm the exact source name in NDI Studio Monitor."
        }
        if lower.contains("no sources") || (lower.contains("bonjour") && lower.contains("none")) {
            return "No NDI senders detected. Start a source on your network and allow Local Network access for this app."
        }
        if lower.contains("bonjour") {
            return "Sources discovered on the network. Rescan if a sender was just started."
        }
        return nil
    }

    static func discoverSources() async -> (ndiLines: [String], presentation: ScanPresentation, toolTip: String) {
        let outcome = await VideoInputDiscovery.discoverNDISources(scanSeconds: 2.8)
        let deck = VideoInputDiscovery.deckLinkStatusLine(maxNames: 6)
        let mergedTechnical = outcome.statusLine + "\n\n" + deck
        let presentation = makeScanPresentation(ndiLines: outcome.lines, technicalStatus: outcome.statusLine)
        return (outcome.lines, presentation, mergedTechnical)
    }

    static func displayLabel(for ref: String) -> String {
        let normalized = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty || normalized == noneChoice { return noneDisplayLabel }
        return SourceDisplayLabels.displayLabel(for: normalized)
    }

    static func isPersistenceRef(_ ref: String) -> Bool {
        if ref == noneChoice { return true }
        let lower = ref.lowercased()
        return lower.hasPrefix("ndi:") || lower.hasPrefix("sdi:")
    }

    static func resolvedPersistenceRef(
        displayValue: String,
        slot: Int,
        slotPersistenceRef: [Int: String],
        refByDisplayLabel: [String: String]
    ) -> String {
        let trimmed = displayValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == noneDisplayLabel || trimmed == noneChoice {
            return noneChoice
        }
        if let mapped = refByDisplayLabel[trimmed] {
            return mapped
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("ndi:") || lower.hasPrefix("sdi:") {
            return trimmed
        }
        if let saved = slotPersistenceRef[slot], saved != noneChoice {
            let savedLabel = displayLabel(for: saved)
            if savedLabel == trimmed {
                return saved
            }
        }
        return trimmed
    }
}
