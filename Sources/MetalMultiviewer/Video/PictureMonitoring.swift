import Foundation

enum FocusPeakingColor: String, Codable, Sendable, CaseIterable {
    case green
    case red
    case white
    case yellow

    var displayName: String {
        switch self {
        case .green: "Green"
        case .red: "Red"
        case .white: "White"
        case .yellow: "Yellow"
        }
    }

    /// Linear RGB 0…1 for Metal uniforms.
    var linearRGB: (r: Float, g: Float, b: Float) {
        switch self {
        case .green: (0.0, 1.0, 0.0)
        case .red: (1.0, 0.0, 0.0)
        case .white: (1.0, 1.0, 1.0)
        case .yellow: (1.0, 1.0, 0.0)
        }
    }
}

struct PictureMonitoringSettings: Equatable, Codable, Sendable {
    var focusPeakingEnabled: Bool
    var falseColorEnabled: Bool
    var zebraEnabled: Bool
    var focusPeakingColor: FocusPeakingColor
    /// Edge threshold for focus peaking (higher = fewer edges).
    var focusPeakingSensitivity: Float
    /// Zebra threshold as fraction of peak white (0.70…1.00).
    var zebraLevel: Float

    static let defaults = PictureMonitoringSettings(
        focusPeakingEnabled: false,
        falseColorEnabled: false,
        zebraEnabled: false,
        focusPeakingColor: .green,
        focusPeakingSensitivity: 0.12,
        zebraLevel: 0.9
    )

    static let sensitivityRange: ClosedRange<Float> = 0.05 ... 0.35
    static let zebraLevelRange: ClosedRange<Float> = 0.70 ... 1.00

    /// Discrete zebra presets shown in Preferences (%).
    static let zebraLevelPresets: [Float] = [0.70, 0.80, 0.90, 0.95, 1.00]

    func clamped() -> PictureMonitoringSettings {
        var copy = self
        copy.focusPeakingSensitivity = min(max(copy.focusPeakingSensitivity, Self.sensitivityRange.lowerBound), Self.sensitivityRange.upperBound)
        copy.zebraLevel = min(max(copy.zebraLevel, Self.zebraLevelRange.lowerBound), Self.zebraLevelRange.upperBound)
        return copy
    }
}

extension Notification.Name {
    /// Posted when picture monitoring toggles or prefs change (live apply).
    static let metalMultiviewerPictureMonitoringChanged = Notification.Name("MetalMultiviewerPictureMonitoringChanged")
}

/// Thread-safe picture monitoring state for HTTP control + UI.
final class PictureMonitoringStore: @unchecked Sendable {
    private let queue = DispatchQueue(label: "MetalMultiviewer.PictureMonitoringStore")
    private var settings: PictureMonitoringSettings

    init(settings: PictureMonitoringSettings = .defaults) {
        self.settings = settings.clamped()
    }

    func get() -> PictureMonitoringSettings {
        queue.sync { settings }
    }

    func set(_ newSettings: PictureMonitoringSettings, notify: Bool = true) {
        queue.sync { settings = newSettings.clamped() }
        if notify {
            Self.postChanged()
        }
    }

    func mutate(_ block: (inout PictureMonitoringSettings) -> Void, notify: Bool = true) {
        queue.sync {
            block(&settings)
            settings = settings.clamped()
        }
        if notify {
            Self.postChanged()
        }
    }

    private static func postChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .metalMultiviewerPictureMonitoringChanged, object: nil)
        }
    }
}
