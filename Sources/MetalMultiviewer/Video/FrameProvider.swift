import CoreVideo
import Metal

protocol FrameProvider: AnyObject {
    /// Returns the latest available frame as a Metal texture, or nil if none is available yet.
    /// Implementations should avoid buffering; a single "latest" frame is ideal.
    func copyLatestTexture() -> MTLTexture?
}

protocol MonitorableProvider: FrameProvider {
    var lastFrameAt: Date? { get }
}

/// Source resolution for HUD overlays (NDI program / SDI wire size). Zero until known.
protocol VideoFeedDimensionReporting: AnyObject {
    var feedPixelWidth: Int { get }
    var feedPixelHeight: Int { get }
}

extension VideoFeedDimensionReporting {
    /// Decoded frame size used for upload geometry; defaults to `feedPixel*` when not overridden.
    var receivedPixelWidth: Int { feedPixelWidth }
    var receivedPixelHeight: Int { feedPixelHeight }
}

/// Display width ÷ height as intended for presentation (e.g. NDI `picture_aspect_ratio`). Use `0` to mean “derive from pixel frame.”
protocol VideoBroadcastAspectReporting: AnyObject {
    var broadcastAspectRatio: Float { get }
}

/// Providers that downscale before GPU upload read the on-screen target from the main thread.
protocol DisplaySizedUploadProvider: AnyObject {
    /// `(0, 0)` skips upload (slot not visible). Otherwise max pixel size to hand to Metal.
    func setTargetUploadSize(width: Int, height: Int)
}

protocol FrameUpdateNotifying: AnyObject {
    var onFrameUpdated: (@Sendable () -> Void)? { get set }
}
