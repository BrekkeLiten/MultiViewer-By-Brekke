import AppKit

enum NdiAttribution {
    static let trademarkNotice = "NDI® is a registered trademark of Vizrt NDI AB."
    static let websiteURL = URL(string: "https://ndi.video/")!

    static func openWebsite() {
        NSWorkspace.shared.open(websiteURL)
    }

    static func acknowledgmentsMessage() -> String {
        """
        MultiViewer by Brekke includes the NDI® runtime under the NDI SDK license agreement.

        \(trademarkNotice)

        Learn more about NDI and download tools at ndi.video.
        """
    }

    static func preferencesFooterPlainText() -> String {
        "Uses NDI®. Learn more at ndi.video — \(trademarkNotice)"
    }

    /// Preferences footer: plain label plus link button styling via attributed string.
    static func preferencesFooterAttributedString() -> NSAttributedString {
        let prefix = "Uses NDI®. "
        let linkTitle = "Learn more at ndi.video"
        let full = prefix + linkTitle
        let result = NSMutableAttributedString(string: full)
        let range = (full as NSString).range(of: linkTitle)
        result.addAttributes([
            .link: websiteURL,
            .foregroundColor: NSColor.linkColor,
        ], range: range)
        result.addAttribute(.font, value: NSFont.systemFont(ofSize: 11), range: NSRange(location: 0, length: full.count))
        return result
    }
}
