import Darwin
import Foundation
import SystemConfiguration

struct ControlBindOption: Equatable {
    let address: String
    let label: String
}

enum NetworkInterfaceDiscovery {
    static let allInterfacesAddress = "0.0.0.0"
    static let localhostAddress = "127.0.0.1"

    /// Dropdown choices for the control-server bind address (IPv4).
    static func bindOptions() -> [ControlBindOption] {
        var options: [ControlBindOption] = [
            ControlBindOption(
                address: allInterfacesAddress,
                label: "All interfaces 0.0.0.0"
            ),
            ControlBindOption(
                address: localhostAddress,
                label: adapterLabel(friendly: "Localhost", bsdName: "lo0", address: localhostAddress)
            ),
        ]

        for iface in ipv4Interfaces() {
            let friendly = localizedInterfaceName(bsdName: iface.name)
            options.append(
                ControlBindOption(
                    address: iface.address,
                    label: adapterLabel(friendly: friendly, bsdName: iface.name, address: iface.address)
                )
            )
        }
        return options
    }

    /// Companion-facing URL for a bind address + port (uses first LAN IP when bound to all interfaces).
    static func controlURL(bindAddress: String, port: Int) -> String {
        let host = displayHost(forBindAddress: bindAddress)
        return "http://\(host):\(port)"
    }

    static func displayHost(forBindAddress bindAddress: String) -> String {
        if bindAddress == allInterfacesAddress {
            return ipv4Interfaces().first?.address ?? localhostAddress
        }
        return bindAddress
    }

    private struct IPv4Interface: Equatable {
        var name: String
        var address: String
    }

    private static func ipv4Interfaces() -> [IPv4Interface] {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var results: [IPv4Interface] = []
        var seenAddresses = Set<String>()
        var ptr: UnsafeMutablePointer<ifaddrs>? = first

        while let ifa = ptr?.pointee {
            defer { ptr = ifa.ifa_next }

            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let flags = Int32(ifa.ifa_flags)
            guard (flags & IFF_UP) != 0 else { continue }
            guard (flags & IFF_LOOPBACK) == 0 else { continue }

            let name = String(cString: ifa.ifa_name)
            guard isNormalNetworkAdapter(bsdName: name) else { continue }

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let err = getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &hostBuf,
                socklen_t(hostBuf.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard err == 0 else { continue }

            let bytes = hostBuf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
            let ip = String(decoding: bytes, as: UTF8.self)
            guard !ip.isEmpty, seenAddresses.insert(ip).inserted else { continue }
            results.append(IPv4Interface(name: name, address: ip))
        }

        return results.sorted { $0.address.localizedStandardCompare($1.address) == .orderedAscending }
    }

    /// Wi‑Fi and Ethernet only — excludes VM/docker bridges, VPN tunnels, AWDL, etc.
    private static func isNormalNetworkAdapter(bsdName: String) -> Bool {
        if bsdName.hasPrefix("bridge")
            || bsdName.hasPrefix("utun")
            || bsdName.hasPrefix("awdl")
            || bsdName.hasPrefix("llw")
            || bsdName.hasPrefix("vmenet")
            || bsdName.hasPrefix("vboxnet")
        {
            return false
        }

        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else {
            return bsdName.hasPrefix("en")
        }

        let ethernet = kSCNetworkInterfaceTypeEthernet as String
        let wifi = kSCNetworkInterfaceTypeIEEE80211 as String

        for iface in all {
            guard let name = SCNetworkInterfaceGetBSDName(iface) as String?, name == bsdName else { continue }
            guard let type = SCNetworkInterfaceGetInterfaceType(iface) as String? else { return false }
            return type == ethernet || type == wifi
        }
        return false
    }

    private static func adapterLabel(friendly: String, bsdName: String, address: String) -> String {
        "\(friendly) (\(bsdName)) \(address)"
    }

    private static func localizedInterfaceName(bsdName: String) -> String {
        guard let all = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] else { return bsdName }
        for iface in all {
            guard let name = SCNetworkInterfaceGetBSDName(iface) as String?, name == bsdName else { continue }
            if let localized = SCNetworkInterfaceGetLocalizedDisplayName(iface) as String?, !localized.isEmpty {
                return localized
            }
        }
        return bsdName
    }
}
