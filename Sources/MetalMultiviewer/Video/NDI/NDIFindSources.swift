import Foundation

/// Uses NDI runtime **Find** API so lists match what `NDIlib_recv_create_v3` expects.
/// Plain Bonjour `_ndi._tcp` service instance names are *not* guaranteed to equal `NDIlib_source_t.p_ndi_name`.
enum NDIFindSources {
    private struct NDIlib_source_pod {
        var p_ndi_name: UnsafePointer<CChar>?
        var p_ip_address: UnsafePointer<CChar>?
    }

    private struct NDIlib_find_create_pod {
        var show_local_sources: CBool = true
        var p_groups: UnsafePointer<CChar>? = nil
        var p_extra_ips: UnsafePointer<CChar>? = nil
    }

    enum SnapshotResult: Sendable {
        case ndiRuntimeMissing(Error)
        case findAPISymbolsMissing
        case found([String])
    }

    /// Blocking call — invoke from a background task / thread.
    static func snapshot(waitForSourcesMs: UInt32) -> SnapshotResult {
        let api: NDILibraryLoader.API
        do {
            api = try NDILibraryLoader.sharedAPI()
        } catch {
            return .ndiRuntimeMissing(error)
        }

        guard
            let findCreate = api.findCreateV2,
            let findDestroy = api.findDestroy,
            let findWait = api.findWaitForSources,
            let findGet = api.findGetCurrentSources
        else {
            return .findAPISymbolsMissing
        }

        var create = NDIlib_find_create_pod()
        let finder: UnsafeMutableRawPointer? = withUnsafeMutablePointer(to: &create) { ptr in
            findCreate(UnsafeRawPointer(ptr))
        }
        guard let finder else { return .found([]) }
        defer { findDestroy(finder) }

        _ = findWait(finder, waitForSourcesMs)

        var count: UInt32 = 0
        guard let rawBase = findGet(finder, &count), count > 0 else {
            return .found([])
        }

        let stride = MemoryLayout<NDIlib_source_pod>.stride
        var seen = Set<String>()
        var lines: [String] = []

        for i in 0 ..< Int(count) {
            let elt = rawBase.load(fromByteOffset: i * stride, as: NDIlib_source_pod.self)
            let nameStr = elt.p_ndi_name.map { String(cString: $0) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
            let ipStr = elt.p_ip_address.map { String(cString: $0) }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""

            let entry: String?
            if !nameStr.isEmpty {
                entry = "ndi:\(nameStr)"
            } else if !ipStr.isEmpty {
                entry = "ndi:\(ipStr)"
            } else {
                entry = nil
            }

            if let entry, seen.insert(entry).inserted {
                lines.append(entry)
            }
        }

        lines.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return .found(lines)
    }
}
