import Foundation

struct AppConfig: Codable, Equatable {
    var slots: [String: String]?
    var layout: Int?
    /// Which slot fills the canvas in **1-up** layout (1…4). Omitted/`nil` ⇒ 1 for backward compatibility.
    var primarySlot: Int?
    var port: Int?
    /// IPv4 address the HTTP control server binds to. Omit/`nil` ⇒ `127.0.0.1`.
    var controlBindAddress: String?
    /// When nil/absent from JSON: treat as **enabled** for backward compatibility.
    var controlEnabled: Bool?
    /// Max ingest/upload rate per feed (cap over source FPS). Omit/`nil` ⇒ 30 FPS.
    var previewMaxFPS: Double?
    /// When **false**, NDI recv uses SDK low-bandwidth mode. Omit/`nil`/`true` ⇒ full source quality (default).
    var ndiFullQuality: Bool?
}

/// Live monitoring playback: full NDI quality by default, capped upload rate, display-sized downscale before GPU.
struct MonitorPlayback: Sendable {
    /// `NDIlib_recv_bandwidth_*` wire value (`0` = lowest, `100` = typical “highest”).
    var ndiBandwidth: Int32
    /// Minimum seconds between Metal `replace` uploads; `0` = no limit.
    var minTextureUploadInterval: TimeInterval

    var previewMaxFPS: Double {
        1.0 / minTextureUploadInterval
    }

    static func from(config: AppConfig) -> MonitorPlayback {
        let rawFps = config.previewMaxFPS ?? 30
        let fps = min(max(rawFps, 5), 120)
        let interval = 1.0 / fps
        let bw: Int32 = config.ndiFullQuality == false ? 0 : 100
        return MonitorPlayback(ndiBandwidth: bw, minTextureUploadInterval: interval)
    }
}

extension AppConfig {
    /// Default “no saved file” baseline; new fields stay `nil` so `MonitorPlayback.from` supplies monitoring defaults.
    static var empty: AppConfig {
        AppConfig(slots: nil, layout: nil, primarySlot: nil, port: nil, controlBindAddress: nil, controlEnabled: nil, previewMaxFPS: nil, ndiFullQuality: nil)
    }
}

enum ConfigLoader {
    static func load() -> (config: AppConfig?, path: String?) {
        let args = CommandLine.arguments
        if let cfgPath = parseArgValue(args, name: "--config") {
            return (loadFile(at: cfgPath), cfgPath)
        }

        let defaultPath = defaultConfigPath().path
        if FileManager.default.fileExists(atPath: defaultPath) {
            return (loadFile(at: defaultPath), defaultPath)
        }

        return (nil, nil)
    }

    static func effectivePort(config: AppConfig?) -> in_port_t {
        if let portStr = parseArgValue(CommandLine.arguments, name: "--port"), let p = Int(portStr) {
            return in_port_t(clamping: p)
        }
        return persistedPreferredPort(config: config)
    }

    /// Port from persisted config — **CLI `--port` is not applied.** Used when applying Preference UI changes so file wins over dev CLI.
    static func persistedPreferredPort(config: AppConfig?) -> in_port_t {
        if let p = config?.port {
            return in_port_t(clamping: p)
        }
        return 8080
    }

    static func persistedControlBindAddress(config: AppConfig?) -> String {
        let raw = config?.controlBindAddress?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? NetworkInterfaceDiscovery.localhostAddress : raw
    }

    static func persistedConfigURL() -> URL {
        if let path = parseArgValue(CommandLine.arguments, name: "--config") {
            return URL(fileURLWithPath: path)
        }
        return defaultConfigPath()
    }

    static func effectiveControlEnabled(config: AppConfig?) -> Bool {
        config?.controlEnabled ?? true
    }

    static func defaultLayout(config: AppConfig?) -> AppState.LayoutMode {
        let raw = config?.layout
        switch raw {
        case 1: return .oneUp
        case 4: return .fourUp
        default: return .fourUp
        }
    }

    static func defaultConfigPath() -> URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Multiviewer/config.json")
    }

    private static func loadFile(at path: String) -> AppConfig? {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            return nil
        }
    }

    private static func parseArgValue(_ args: [String], name: String) -> String? {
        guard let idx = args.firstIndex(of: name) else { return nil }
        let valIdx = args.index(after: idx)
        guard valIdx < args.endIndex else { return nil }
        return args[valIdx]
    }
}
