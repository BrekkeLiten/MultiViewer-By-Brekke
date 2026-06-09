import Foundation

enum FeedSignalStatus: Equatable, Sendable {
    case live
    case noSource
    case noSignal
}

/// Shared staleness / reconnect timing for provider restarts and on-screen overlays.
enum FeedSignalPolicy {
    static let staleInterval: TimeInterval = 2.0

    static func status(
        assignment: AppState.SourceRef?,
        hasProvider: Bool,
        lastFrameAt: Date?,
        lastRestartAt: Date?,
        hasDisplayableTexture: Bool = false,
        now: Date = Date()
    ) -> FeedSignalStatus {
        guard assignment != nil else { return .noSource }
        guard hasProvider else { return .noSignal }

        // GPU still holds a real frame (scopes / preview can render) even when uploads are throttled.
        if hasDisplayableTexture { return .live }

        if let last = lastFrameAt, now.timeIntervalSince(last) <= staleInterval {
            return .live
        }
        if lastFrameAt == nil,
           let restart = lastRestartAt,
           now.timeIntervalSince(restart) <= staleInterval
        {
            return .live
        }
        return .noSignal
    }
}
