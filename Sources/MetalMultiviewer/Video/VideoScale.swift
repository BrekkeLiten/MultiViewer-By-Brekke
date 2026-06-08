import Accelerate
import Foundation

enum VideoScale {
    /// Downscale packed BGRA8 row-major (`src` stride = `srcWidth * 4`) into `dst` (`dstWidth * 4` stride).
    static func downscaleBGRA(
        src: UnsafePointer<UInt8>,
        srcWidth: Int,
        srcHeight: Int,
        dst: UnsafeMutablePointer<UInt8>,
        dstWidth: Int,
        dstHeight: Int
    ) -> Bool {
        guard srcWidth >= 2, srcHeight >= 2, dstWidth >= 2, dstHeight >= 2 else { return false }
        guard dstWidth <= srcWidth, dstHeight <= srcHeight else { return false }

        var srcBuf = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: src),
            height: vImagePixelCount(srcHeight),
            width: vImagePixelCount(srcWidth),
            rowBytes: srcWidth * 4
        )
        var dstBuf = vImage_Buffer(
            data: dst,
            height: vImagePixelCount(dstHeight),
            width: vImagePixelCount(dstWidth),
            rowBytes: dstWidth * 4
        )

        let err = vImageScale_ARGB8888(&srcBuf, &dstBuf, nil, vImage_Flags(kvImageHighQualityResampling))
        return err == kvImageNoError
    }
}
