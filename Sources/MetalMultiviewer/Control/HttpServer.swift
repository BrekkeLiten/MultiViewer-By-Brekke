import Foundation
import Swifter

extension Notification.Name {
    /// Posted on main when HTTP control server mutates `AppState` (layout, primary slot, sources).
    static let metalMultiviewerAppStateChanged = Notification.Name("MetalMultiviewerAppStateChanged")
}

final class ControlServer {
    private let server = HttpServer()
    private let state: AppState
    private let monitoringStore: PictureMonitoringStore?
    private(set) var boundPort: in_port_t?
    private(set) var boundBindAddress: String?

    init(state: AppState, monitoringStore: PictureMonitoringStore? = nil) {
        self.state = state
        self.monitoringStore = monitoringStore
    }

    func start(port: in_port_t, bindAddress: String) throws {
        server.GET["/state"] = { [weak self] _ in
            guard let self else {
                return .internalServerError
            }
            let snap = state.get()
            var body: [String: Any] = [
                "layout": snap.layout.rawValue,
                "primarySlot": snap.primarySlot,
                "gridColumns": snap.gridLayout.columns,
                "gridRows": snap.gridLayout.rows,
                "dualMonitorMode": snap.dualMonitorMode,
            ]
            if let store = monitoringStore {
                let m = store.get()
                body["monitoring"] = [
                    "focusPeaking": m.focusPeakingEnabled,
                    "falseColor": m.falseColorEnabled,
                    "zebra": m.zebraEnabled,
                    "zebraLevel": m.zebraLevel,
                ]
            }
            return .ok(.json(body))
        }

        server.POST["/layout/1"] = { [weak self] _ in
            self?.state.setLayout(.oneUp)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true]))
        }

        server.POST["/layout/4"] = { [weak self] _ in
            self?.state.setLayout(.fourUp)
            self?.state.setGridLayout(.default2x2)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true]))
        }

        server.POST["/layout/grid/:cols/:rows"] = { [weak self] request in
            guard let self else { return .internalServerError }
            guard
                let colsStr = request.params[":cols"],
                let rowsStr = request.params[":rows"],
                let cols = Int(colsStr),
                let rows = Int(rowsStr),
                GridLayout.isValid(columns: cols, rows: rows)
            else {
                return .badRequest(.json(["ok": false, "error": "invalid_grid"]))
            }
            state.setGridLayout(GridLayout(columns: cols, rows: rows))
            state.setLayout(.fourUp)
            Self.notifyAppStateChanged()
            return .ok(.json(["ok": true, "gridColumns": cols, "gridRows": rows]))
        }

        /// Which input (1…16) is shown fullscreen in **1-up** / program monitor mode.
        server.POST["/layout/primary/:slot"] = { [weak self] request in
            guard let self else { return .internalServerError }
            guard
                let slotStr = request.params[":slot"],
                let slot = Int(slotStr),
                (1 ... MultiviewLimits.maxSlots).contains(slot)
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
                let slot = Int(slotStr),
                (1 ... MultiviewLimits.maxSlots).contains(slot)
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

        registerMonitoringRoutes()

        server.listenAddressIPv4 = bindAddress
        try server.start(port, forceIPv4: true)
        boundPort = port
        boundBindAddress = bindAddress
    }

    private func registerMonitoringRoutes() {
        server.POST["/monitoring/peaking/toggle"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.focusPeakingEnabled.toggle() }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/peaking/on"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.focusPeakingEnabled = true }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/peaking/off"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.focusPeakingEnabled = false }
            return .ok(.json(["ok": true]))
        }

        server.POST["/monitoring/falsecolor/toggle"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.falseColorEnabled.toggle() }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/falsecolor/on"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.falseColorEnabled = true }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/falsecolor/off"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.falseColorEnabled = false }
            return .ok(.json(["ok": true]))
        }

        server.POST["/monitoring/zebra/toggle"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.zebraEnabled.toggle() }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/zebra/on"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.zebraEnabled = true }
            return .ok(.json(["ok": true]))
        }
        server.POST["/monitoring/zebra/off"] = { [weak self] _ in
            self?.monitoringStore?.mutate { $0.zebraEnabled = false }
            return .ok(.json(["ok": true]))
        }

        server.POST["/monitoring/zebra/:percent"] = { [weak self] request in
            guard
                let pctStr = request.params[":percent"],
                let pct = Int(pctStr),
                [70, 80, 90, 95, 100].contains(pct)
            else {
                return .badRequest(.json(["ok": false, "error": "invalid_zebra_level"]))
            }
            let level = Float(pct) / 100.0
            self?.monitoringStore?.mutate { $0.zebraLevel = level }
            return .ok(.json(["ok": true, "zebraLevel": level]))
        }
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
