import Foundation

/// Rec.709 color math for scope analysis (display-referred 0…1 RGB).
enum ScopeColorMath {
    static func luma709(r: Float, g: Float, b: Float) -> Float {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// BT.709 YCbCr; Cb and Cr nominally in −0.5…0.5 for legal range video.
    static func ycbcr709(r: Float, g: Float, b: Float) -> (y: Float, cb: Float, cr: Float) {
        let y = luma709(r: r, g: g, b: b)
        let cb = -0.1146 * r - 0.3854 * g + 0.5 * b
        let cr = 0.5 * r - 0.4542 * g - 0.0458 * b
        return (y, cb, cr)
    }

    /// Map 0…1 luma to histogram level 0…255.
    static func lumaLevel(_ y: Float) -> Int {
        Int(min(max(y * 255.0, 0), 255).rounded(.down))
    }

    /// Map Cb/Cr (−0.5…0.5) to vectorscope bin 0…255.
    static func chromaBin(_ v: Float) -> Int {
        Int(min(max((v + 0.5) * 255.0, 0), 255).rounded(.down))
    }

    /// Cb/Cr → Resolve-style display axes (+Cb right, +Cr up after texture V flip).
    static func vectorscopeDisplayCbCr(r: Float, g: Float, b: Float) -> (cb: Float, cr: Float) {
        let raw = ycbcr709(r: r, g: g, b: b)
        return (cb: raw.cb, cr: raw.cr)
    }

    /// Texture row for a display-space Cr value (after scopeDisplayUV flip).
    static func vectorscopeDisplayRow(cr: Float) -> Int {
        chromaBin(cr)
    }

    /// Angle on the scope display plane: X = −Cb, Y = +Cr (radians, −π…π).
    static func vectorscopeDisplayAngle(r: Float, g: Float, b: Float) -> Float {
        let chroma = vectorscopeDisplayCbCr(r: r, g: g, b: b)
        return atan2(chroma.cr, chroma.cb)
    }

    /// SMPTE target-box angles on the Resolve vectorscope (radians).
    static let vectorscopeTargetAngles: [Float] = [
        3 * .pi / 4, .pi, 5 * .pi / 4, 7 * .pi / 4, 0, .pi / 4,
    ]
}
