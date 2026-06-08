import DeckLinkBridge
import Foundation
import Network

/// Best-effort discovery for the Configure Inputs sheet.
/// - **NDI**: Prefer NDI SDK **Finder** (`NDIlib_find_*`) names — these match `recv_create`. Bonjour is only fallback.
/// - **SDI**: Blackmagic DeckLink cards enumerated via Desktop Video; falls back to `sdi:N` presets when none.
enum VideoInputDiscovery {
    struct NDIScanOutcome: Sendable {
        var lines: [String]
        var statusLine: String
    }

    static func sdiPresetEntries(maxIndex: Int = 16) -> [String] {
        (0 ..< maxIndex).map { "sdi:\($0)" }
    }

    /// Indexed `sdi:N` refs; when Desktop Video exposes hardware, prefers `0..<deviceCount`, else presets up to `maxIndex`.
    static func deckLinkBackedSDIRefs(preferredPresetCount: Int = 16) -> [String] {
        let n = Int(max(0, mvDeckLinkEnumerateDevices()))
        if n > 0 {
            return (0 ..< n).map { "sdi:\($0)" }
        }
        return (0 ..< preferredPresetCount).map { "sdi:\($0)" }
    }

    /// Compact status for the Inputs sheet footer (paired with DeckLinkBackedSDI refs).
    static func deckLinkDeviceCount() -> Int {
        Int(max(0, mvDeckLinkEnumerateDevices()))
    }

    /// Compact status for the Inputs sheet footer (paired with DeckLinkBackedSDI refs).
    static func deckLinkStatusLine(maxNames: Int = 6) -> String {
        let n = Int(mvDeckLinkEnumerateDevices())
        if n <= 0 {
            return "DeckLink Desktop Video: no capture devices enumerated (hardware + driver installed?). Showing empty `sdi:` presets."
        }
        var parts: [String] = []
        for i in 0 ..< min(n, Int(maxNames)) {
            guard let utf8 = mvDeckLinkCopyDeviceDisplayName(Int32(i)) else { continue }
            defer { mvDeckLinkFreeString(utf8) }
            let dn = String(cString: utf8)
            parts.append("sdi:\(i) → \(dn)")
        }
        let extra = n > parts.count ? " … + \(n - parts.count) more" : ""
        return "DeckLink Desktop Video: \(n) input device(s).\n" + parts.joined(separator: "\n") + extra
    }

    /// Prefer NDI Find (exact `recv_create` names); falls back to Bonjour when Finder is unavailable or returns nothing.
    static func discoverNDISources(scanSeconds: TimeInterval = 2.5) async -> NDIScanOutcome {
        let waitMs = UInt32(min(max(scanSeconds * 1000, 350), 12_000))
        let snap = await Task.detached {
            NDIFindSources.snapshot(waitForSourcesMs: waitMs)
        }.value

        switch snap {
        case let .found(names):
            if !names.isEmpty {
                return NDIScanOutcome(
                    lines: names,
                    statusLine: "NDI Finder (SDK): \(names.count) source(s). These strings match `NDIlib_recv_create_v3`."
                )
            }
            let b = await discoverBonjourNDISources(scanSeconds: scanSeconds)
            if b.isEmpty {
                return NDIScanOutcome(
                    lines: [],
                    statusLine: "NDI Finder: no sources. Bonjour `_ndi._tcp`: none. Start a sender on the LAN or check Local Network permission."
                )
            }
            return NDIScanOutcome(
                lines: b,
                statusLine: "NDI Finder saw 0 sources; listing Bonjour `_ndi._tcp` names (often NOT the same as NDI source names). Prefer typing the name from NDI Studio Monitor."
            )
        case .findAPISymbolsMissing:
            let b = await discoverBonjourNDISources(scanSeconds: scanSeconds)
            return NDIScanOutcome(
                lines: b,
                statusLine: b.isEmpty
                    ? "This `libndi` build has no Find API symbols; Bonjour scan empty. Install the current NDI Runtime from ndi.video."
                    : "NDI Find API missing from this dylib; Bonjour list is best-effort only."
            )
        case .ndiRuntimeMissing:
            let b = await discoverBonjourNDISources(scanSeconds: scanSeconds)
            return NDIScanOutcome(
                lines: b,
                statusLine: "NDI library (libndi.3.dylib) not found. Install NDI Runtime for macOS from https://ndi.video/download/ and restart, or set environment variable NDI_RUNTIME_DIR_V3 to the folder containing libndi.3.dylib. Until then Bonjour may list names but video will not decode."
            )
        }
    }

    /// mDNS `_ndi._tcp` **instance** titles — not guaranteed equal to finder `p_ndi_name`.
    static func discoverBonjourNDISources(scanSeconds: TimeInterval = 2.5) async -> [String] {
        await withCheckedContinuation { continuation in
            let gate = ResumeGate(continuation)

            final class NameBag: @unchecked Sendable {
                let lock = NSLock()
                var names = Set<String>()
                func add(raw: String) {
                    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    let ndi = t.lowercased().hasPrefix("ndi:") ? t : "ndi:\(t)"
                    lock.lock()
                    names.insert(ndi)
                    lock.unlock()
                }

                func sortedUnique() -> [String] {
                    lock.lock()
                    defer { lock.unlock() }
                    return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                }
            }

            let bag = NameBag()
            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            let browsers: [NWBrowser] = [
                NWBrowser(for: NWBrowser.Descriptor.bonjour(type: "_ndi._tcp", domain: nil), using: parameters),
                NWBrowser(for: NWBrowser.Descriptor.bonjour(type: "_ndi._tcp", domain: "local."), using: parameters),
            ]

            for browser in browsers {
                browser.browseResultsChangedHandler = { _, changes in
                    for change in changes {
                        guard case let .added(result) = change else { continue }
                        guard case let .service(name, _, _, _) = result.endpoint else { continue }
                        bag.add(raw: String(name))
                    }
                }
                browser.start(queue: .global(qos: .userInitiated))
            }

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + scanSeconds) {
                for b in browsers {
                    b.cancel()
                }
                gate.resumeOnce(bag.sortedUnique())
            }
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private let cont: CheckedContinuation<[String], Never>

    init(_ cont: CheckedContinuation<[String], Never>) {
        self.cont = cont
    }

    func resumeOnce(_ v: [String]) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        cont.resume(returning: v)
    }
}
