import Foundation

/// Parses NDI XML metadata for program video dimensions (`<video_format xres="…" yres="…"/>`).
enum NDIMetadataFormatParser {
    static func videoDimensions(from xml: String) -> (width: Int, height: Int)? {
        let trimmed = xml.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let pair = parseAttributes(in: trimmed, widthKey: "xres", heightKey: "yres") {
            return pair
        }
        if let pair = parseAttributes(in: trimmed, widthKey: "width", heightKey: "height") {
            return pair
        }
        return nil
    }

    private static func parseAttributes(
        in xml: String,
        widthKey: String,
        heightKey: String
    ) -> (width: Int, height: Int)? {
        guard
            let w = firstIntAttribute(named: widthKey, in: xml),
            let h = firstIntAttribute(named: heightKey, in: xml),
            w > 0, h > 0
        else {
            return nil
        }
        return (w, h)
    }

    private static func firstIntAttribute(named name: String, in xml: String) -> Int? {
        let lower = xml.lowercased()
        let token = "\(name.lowercased())=\""
        guard let tokenRange = lower.range(of: token) else { return nil }
        let valueStart = xml.index(xml.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: tokenRange.upperBound))
        guard valueStart < xml.endIndex else { return nil }
        let after = xml[valueStart...]
        guard let end = after.firstIndex(of: "\"") else { return nil }
        return Int(after[..<end])
    }
}
