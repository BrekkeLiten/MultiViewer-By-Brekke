import CoreGraphics
import Foundation

/// Four-up quadrant geometry (AppKit top-left origin, y grows downward).
enum MultiviewSlotLayout {
    /// Maps a point in view bounds to slot 1…4, or nil when outside bounds.
    static func slotForPoint(_ point: CGPoint, in size: CGSize) -> Int? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard point.x >= 0, point.y >= 0, point.x <= size.width, point.y <= size.height else { return nil }

        let midX = size.width * 0.5
        let midY = size.height * 0.5
        let top = point.y < midY
        let left = point.x < midX

        switch (top, left) {
        case (true, true): return 1
        case (true, false): return 2
        case (false, true): return 3
        case (false, false): return 4
        }
    }

    /// Pixel frame for `slot` (1…4) within `size`.
    static func quadrantFrame(slot: Int, in size: CGSize) -> CGRect {
        let w = max(size.width, 0)
        let h = max(size.height, 0)
        let halfW = w * 0.5
        let halfH = h * 0.5

        switch slot {
        case 1:
            return CGRect(x: 0, y: 0, width: halfW, height: halfH)
        case 2:
            return CGRect(x: halfW, y: 0, width: w - halfW, height: halfH)
        case 3:
            return CGRect(x: 0, y: halfH, width: halfW, height: h - halfH)
        case 4:
            return CGRect(x: halfW, y: halfH, width: w - halfW, height: h - halfH)
        default:
            return .zero
        }
    }
}
