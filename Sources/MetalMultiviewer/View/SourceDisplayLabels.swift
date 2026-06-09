import Foundation

/// Human-readable labels for source picker rows (maps back to `ndi:…` / `sdi:N` persistence strings).
enum SourceDisplayLabels {
    static let noneChoice = "(None)"
    static let noneDisplayLabel = "None"

    static func displayLabel(for ref: String) -> String {
        let t = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == noneChoice { return noneDisplayLabel }
        if t.lowercased().hasPrefix("ndi:") {
            return ndiDisplayLabel(body: String(t.dropFirst(4)))
        }
        if t.lowercased().hasPrefix("sdi:") {
            return "SDI \(String(t.dropFirst(4)))"
        }
        return t
    }

    /// NDI names are usually `HOST (Stream)` — show both so identical stream names on different machines stay distinct.
    static func ndiDisplayLabel(body: String) -> String {
        let parsed = parseNDIName(body)
        let host = shortenNDIHost(parsed.host)
        if let stream = parsed.stream, !stream.isEmpty {
            return "\(host) · \(stream)"
        }
        return host
    }

    private struct ParsedNDIName {
        var host: String
        var stream: String?
    }

    private static func parseNDIName(_ raw: String) -> ParsedNDIName {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let open = trimmed.firstIndex(of: "("),
              let close = trimmed.lastIndex(of: ")"),
              open < close
        else {
            return ParsedNDIName(host: trimmed, stream: nil)
        }

        let host = trimmed[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        let stream = trimmed[trimmed.index(after: open) ..< close]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedNDIName(
            host: String(host),
            stream: stream.isEmpty ? nil : String(stream)
        )
    }

    /// Compact label for multiview HUD badges (source name + optional resolution).
    static func multiviewBadgeText(
        slot: Int,
        sourcePersistenceString: String?,
        pixelWidth: Int,
        pixelHeight: Int
    ) -> String {
        guard let raw = sourcePersistenceString?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              raw != noneChoice
        else {
            return "Slot \(slot)"
        }
        let name = displayLabel(for: raw)
        if pixelWidth > 0, pixelHeight > 0 {
            return "\(name) · \(pixelWidth)×\(pixelHeight)"
        }
        return name
    }

    private static func shortenNDIHost(_ host: String) -> String {
        var h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.uppercased().hasSuffix(".LOCAL") {
            h = String(h.dropLast(".LOCAL".count))
        }
        return h.isEmpty ? host : h
    }
}
