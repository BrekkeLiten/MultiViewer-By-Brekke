import Foundation
import Swifter

extension Notification.Name {
    /// Posted on main when HTTP control server mutates `AppState` (layout, primary slot, sources).
    static let metalMultiviewerAppStateChanged = Notification.Name("MetalMultiviewerAppStateChanged")
}

final class ControlServer {
    private let server = HttpServer()
    private let state: AppState
    private(set) var boundPort: in_port_t?
    private(set) var boundBindAddress: String?

    init(state: AppState) {
        self.state = state
    }

    func start(port: in_port_t, bindAddress: String) throws {
        server.GET["/state"] = { [weak self] _ in
            guard let self else {
                return .internalServerError
            }
            let snap = state.get()
            let body: [String: Any] = [
                "layout": snap.layout.rawValue,
                "primarySlot": snap.primarySlot,
            ]
            return .ok(.json(body))
        }

        server.POST["/layout/1"] = { [weak self] _ in
            self?.state.setLayout(.oneUp)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true]))
        }

        server.POST["/layout/4"] = { [weak self] _ in
            self?.state.setLayout(.fourUp)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true]))
        }

        /// Which input (1…4) is shown fullscreen in **1-up** mode.
        server.POST["/layout/primary/:slot"] = { [weak self] request in
            guard let self else { return .internalServerError }
            guard
                let slotStr = request.params[":slot"],
                let slot = Int(slotStr),
                (1 ... 4).contains(slot)
            else {
                return .badRequest(.json(["ok": false, "error": "invalid_slot"]))
            }
            state.setPrimarySlot(slot)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true, "primarySlot": slot]))
        }

        server.POST["/source/:slot/:name"] = { [weak self] request in
            guard let self else { return .internalServerError }

            guard
                let slotStr = request.params[":slot"],
                let slot = Int(slotStr)
            else {
                return .badRequest(.json(["ok": false, "error": "invalid_slot"]))
            }

            guard let rawName = request.params[":name"] else {
                return .badRequest(.json(["ok": false, "error": "missing_name"]))
            }

            let decodedName = rawName.removingPercentEncoding ?? rawName

            do {
                let src = try Self.parseSourceRef(decodedName)
                try state.setSource(slot: slot, source: src)
                Self.notifyAppStateChanged()
                return .ok(.json(["ok": true]))
            } catch {
                return .badRequest(.json(["ok": false, "error": "invalid_source"]))
            }
        }

        server.listenAddressIPv4 = bindAddress
        try server.start(port, forceIPv4: true)
        boundPort = port
        boundBindAddress = bindAddress
    }

    func stop() {
        server.stop()
        boundPort = nil
        boundBindAddress = nil
    }

    static func parseSourceRef(_ value: String) throws -> AppState.SourceRef {
        if value.hasPrefix("ndi:") {
            let name = String(value.dropFirst(4))
            guard !name.isEmpty else { throw ParseError.invalid }
            return .ndi(name: name)
        }
        if value.hasPrefix("sdi:") {
            let idxStr = String(value.dropFirst(4))
            guard let idx = Int(idxStr) else { throw ParseError.invalid }
            return .sdi(index: idx)
        }
        throw ParseError.invalid
    }

    enum ParseError: Error {
        case invalid
    }

    private static func notifyAppStateChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .metalMultiviewerAppStateChanged, object: nil)
        }
    }
}

