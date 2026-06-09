import Foundation

/// Owns `/layout` and `/source` HTTP control server lifecycle for `AppState`.
@MainActor
final class ControlServerManager {
    enum Status: Equatable {
        case stopped
        case running(url: String, boundPort: in_port_t, bindAddress: String)
        case failed(String)
    }

    private let state: AppState

    private var server: ControlServer?
    /// Last port that bind succeeded — used for rollback when a preference change fails.
    private var lastGoodPort: in_port_t?
    private var lastGoodBindAddress: String?

    /// Set when rollback kept the prior port after user tried an invalid/busy port.
    private(set) var lastWarning: String?

    private(set) var status: Status = .stopped {
        didSet {
            guard oldValue != status else { return }
            NotificationCenter.default.post(name: Self.statusDidChangeNotification, object: self)
        }
    }

    init(state: AppState) {
        self.state = state
    }

    private var monitoringStore: PictureMonitoringStore?

    /// Applies preference: binds exact port and IPv4 address (predictable URLs for automation).
    func apply(enabled: Bool, port: in_port_t, bindAddress: String, monitoringStore: PictureMonitoringStore? = nil) {
        if let monitoringStore {
            self.monitoringStore = monitoringStore
        }
        lastWarning = nil

        if !enabled {
            server?.stop()
            server = nil
            status = .stopped
            return
        }

        let rollbackPort = server?.boundPort ?? lastGoodPort
        let rollbackBind = server?.boundBindAddress ?? lastGoodBindAddress ?? NetworkInterfaceDiscovery.localhostAddress

        server?.stop()
        server = nil
        status = .stopped

        let next = ControlServer(state: state, monitoringStore: monitoringStore)
        do {
            try next.start(port: port, bindAddress: bindAddress)
            server = next
            if let bound = next.boundPort, let boundAddr = next.boundBindAddress {
                lastGoodPort = bound
                lastGoodBindAddress = boundAddr
                let url = NetworkInterfaceDiscovery.controlURL(bindAddress: boundAddr, port: Int(bound))
                status = .running(url: url, boundPort: bound, bindAddress: boundAddr)
            }
        } catch {
            guard let rollbackPort else {
                status = .failed("\(error)")
                return
            }

            lastWarning = "Could not bind \(bindAddress):\(port): \(error). Restored \(rollbackBind):\(rollbackPort)."
            let rb = ControlServer(state: state, monitoringStore: monitoringStore)
            do {
                try rb.start(port: rollbackPort, bindAddress: rollbackBind)
                server = rb
                if let bound = rb.boundPort, let boundAddr = rb.boundBindAddress {
                    lastGoodPort = bound
                    lastGoodBindAddress = boundAddr
                    let url = NetworkInterfaceDiscovery.controlURL(bindAddress: boundAddr, port: Int(bound))
                    status = .running(url: url, boundPort: bound, bindAddress: boundAddr)
                }
            } catch {
                status = .failed("Bind failed (\(error)). Rollback \(rollbackBind):\(rollbackPort) also failed.")
            }
        }
    }
}

extension ControlServerManager {
    static let statusDidChangeNotification = Notification.Name("MetalMultiviewer.ControlServerStatusDidChange")
}
