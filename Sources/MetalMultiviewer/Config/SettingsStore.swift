import Foundation

@MainActor
final class SettingsStore {
    private let url: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder = JSONDecoder()

    init(url: URL = ConfigLoader.persistedConfigURL()) {
        self.url = url
    }

    /// Loads config from disk, or returns defaults matching “no file” behavior.
    func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .empty
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }
}
