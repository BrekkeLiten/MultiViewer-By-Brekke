import Darwin
import Foundation
import Metal
import os.log

/// NDI receiver backed by dynamically loaded `libndi.3.dylib` — uploads BGRA into a shared `MTLTexture`.
final class NDIReceiver: MonitorableProvider, VideoFeedDimensionReporting, VideoBroadcastAspectReporting,
    DisplaySizedUploadProvider, FrameUpdateNotifying, @unchecked Sendable
{
    private static let log = Logger(subsystem: "MetalMultiviewer", category: "NDI")

    private let device: MTLDevice
    private let playback: MonitorPlayback
    private let lock = NSLock()
    private var latestTexture: MTLTexture?
    /// Wire/source resolution from the last decoded frame (preview size when NDI bandwidth is low).
    private var sourceWidth = 0
    private var sourceHeight = 0
    /// Program/source resolution for HUD (full NDI stream size; from metadata when receiving preview).
    private var programSourceWidth = 0
    private var programSourceHeight = 0
    private var textureWidth = 0
    private var textureHeight = 0

    /// NDI picture DAR (`picture_aspect_ratio` when set, else pixel `xres/yres`).
    private var broadcastAspectWidthOverHeight: Float = 1

    private var thread: Thread?
    private var isRunning = false
    /// Reused packed BGRA buffer for UYVY→BGRA (avoid per-frame allocations).
    private var uyvyScratch = Data()
    private var bgraScratch = Data()

    /// `NDIlib_source_t.p_ndi_name` (finder-style), or omitted when connecting via `p_ip_address` only.
    private let ndiDisplayNameCString: UnsafeMutablePointer<CChar>?

    /// `NDIlib_source_t.p_ip_address` as `"host:port"` when using IP connect; mutually exclusive preference with display name unless both set by typed config later.
    private let ndiIPCString: UnsafeMutablePointer<CChar>?
    private var _lastFrameAt: Date?
    private var lastTextureUploadAt = Date.distantPast

    /// `-1` = no geometry yet (use full source); `0` = slot hidden (skip upload).
    private var targetUploadWidth = -1
    private var targetUploadHeight = -1

    var onFrameUpdated: (@Sendable () -> Void)?

    init(device: MTLDevice, streamName: String, playback: MonitorPlayback) {
        self.device = device
        self.playback = playback
        var n = streamName.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.lowercased().hasPrefix("ndi:") {
            n = String(n.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let trimmed = n.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            ndiDisplayNameCString = nil
            ndiIPCString = nil
        } else if let hostPort = Self.normalizedIPv4HostPort(trimmed) {
            ndiDisplayNameCString = nil
            ndiIPCString = strdup("\(hostPort.host):\(hostPort.port)")
        } else {
            ndiDisplayNameCString = strdup(trimmed)
            ndiIPCString = nil
        }
    }

    deinit {
        if let ndiDisplayNameCString { free(ndiDisplayNameCString) }
        if let ndiIPCString { free(ndiIPCString) }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true

        let t = Thread { [weak self] in
            self?.receiverThreadMain()
        }
        t.name = "NDIReceiver"
        t.qualityOfService = .userInitiated
        t.start()
        thread = t
    }

    func stop() {
        lock.lock()
        isRunning = false
        lock.unlock()
    }

    func setTargetUploadSize(width: Int, height: Int) {
        lock.lock()
        if width <= 0 || height <= 0 {
            targetUploadWidth = 0
            targetUploadHeight = 0
        } else {
            targetUploadWidth = width
            targetUploadHeight = height
        }
        lock.unlock()
    }

    func copyLatestTexture() -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        return latestTexture
    }

    var lastFrameAt: Date? {
        lock.lock()
        defer { lock.unlock() }
        return _lastFrameAt
    }

    var feedPixelWidth: Int {
        lock.lock()
        defer { lock.unlock() }
        if programSourceWidth > 0 { return programSourceWidth }
        return sourceWidth
    }

    var feedPixelHeight: Int {
        lock.lock()
        defer { lock.unlock() }
        if programSourceHeight > 0 { return programSourceHeight }
        return sourceHeight
    }

    var receivedPixelWidth: Int {
        lock.lock()
        defer { lock.unlock() }
        return sourceWidth
    }

    var receivedPixelHeight: Int {
        lock.lock()
        defer { lock.unlock() }
        return sourceHeight
    }

    var broadcastAspectRatio: Float {
        lock.lock()
        defer { lock.unlock() }
        return broadcastAspectWidthOverHeight
    }

    private func receiverThreadMain() {
        let api: NDILibraryLoader.API
        do {
            api = try NDILibraryLoader.sharedAPI()
        } catch {
            Self.log.error("NDI runtime not available: \(String(describing: error), privacy: .public)")
            return
        }

        if ndiDisplayNameCString == nil, ndiIPCString == nil {
            Self.log.error("NDI target empty after parsing.")
            return
        }

        let createBuf = Self.makeRecvCreateSettings(
            ndiDisplayNameCString.map { UnsafePointer($0) },
            ndiIPCString.map { UnsafePointer($0) },
            recvBandwidth: playback.ndiBandwidth
        )
        defer { createBuf.deallocate() }

        guard let recv = api.recvCreateV3(UnsafeRawPointer(createBuf)) else {
            Self.log.error(
                "NDIlib_recv_create_v3 returned NULL for '\(self.connectionLogLabel(), privacy: .public)'."
            )
            return
        }
        defer { api.recvDestroy(recv) }

        Self.log.info(
            "NDI receiver connected (create OK): '\(self.connectionLogLabel(), privacy: .public)'."
        )

        var video = NDIlib_video_frame_v2_swift()
        var metadata = NDIlib_metadata_frame_swift()
        while true {
            lock.lock()
            let running = isRunning
            lock.unlock()
            if !running { break }

            let iv = playback.minTextureUploadInterval
            let now = Date()
            let allowUpload = iv <= 0 || now.timeIntervalSince(lastTextureUploadAt) >= iv

            video = NDIlib_video_frame_v2_swift()
            metadata = NDIlib_metadata_frame_swift()
            let frameType = withUnsafeMutablePointer(to: &video) { vptr in
                withUnsafeMutablePointer(to: &metadata) { mptr in
                    api.recvCaptureV2(
                        recv,
                        UnsafeMutableRawPointer(vptr),
                        nil,
                        UnsafeMutableRawPointer(mptr),
                        100
                    )
                }
            }

            if frameType == Self.frameTypeVideo {
                defer {
                    withUnsafePointer(to: &video) { ptr in
                        api.recvFreeVideoV2(recv, UnsafeRawPointer(ptr))
                    }
                }
                if allowUpload, processVideoFrame(video: &video) {
                    lastTextureUploadAt = Date()
                }
            } else if frameType == Self.frameTypeNone {
                if !allowUpload {
                    Thread.sleep(forTimeInterval: min(max(iv * 0.25, 0.002), 0.016))
                } else {
                    Thread.sleep(forTimeInterval: 0.002)
                }
            } else if frameType == Self.frameTypeMetadata {
                ingestProgramDimensions(fromMetadata: metadata)
                if let freeMeta = api.recvFreeMetadata {
                    withUnsafePointer(to: &metadata) { ptr in
                        freeMeta(recv, UnsafeRawPointer(ptr))
                    }
                }
            } else if frameType == Self.frameTypeError {
                Self.log.warning("NDI recv error frame marker — reconnecting loop sleep.")
                Thread.sleep(forTimeInterval: 0.2)
            } else if frameType == Self.frameTypeStatusChange {
                // ignore status_change without an attached video blob
            }
        }

        Self.log.debug("NDI receiver thread exit.")
    }

    /// Returns whether pixels were uploaded to Metal.
    private func processVideoFrame(video: inout NDIlib_video_frame_v2_swift) -> Bool {
        guard let pixels = video.p_data else { return false }
        let w = Int(video.xres)
        let h = Int(video.yres)
        guard w > 0, h > 0, Int(video.line_stride_in_bytes) > 0 else { return false }

        let fourCC = video.FourCC
        updateDimensionsForVideoFrame(
            width: w,
            height: h,
            metadataXML: Self.utf8String(fromOptional: video.p_metadata, declaredLength: 0)
        )

        lock.lock()
        let tw = targetUploadWidth
        let th = targetUploadHeight
        lock.unlock()

        if tw == 0 || th == 0 {
            return false
        }

        let uploadW: Int
        let uploadH: Int
        if tw < 0 || th < 0 {
            uploadW = w
            uploadH = h
        } else {
            uploadW = min(max(tw, 2), w)
            uploadH = min(max(th, 2), h)
        }

        let par = video.picture_aspect_ratio
        let pixelAR = Float(w) / Float(max(h, 1))
        lock.lock()
        let progW = programSourceWidth
        let progH = programSourceHeight
        let dar: Float
        if par > 0.001 {
            dar = par
        } else if progW > 0, progH > 0 {
            dar = Float(progW) / Float(progH)
        } else {
            dar = pixelAR
        }
        broadcastAspectWidthOverHeight = max(dar, 0.01)

        if textureWidth != uploadW || textureHeight != uploadH {
            guard let newTex = Self.makeBGRATexture(device: device, width: uploadW, height: uploadH) else {
                lock.unlock()
                return false
            }
            latestTexture = newTex
            textureWidth = uploadW
            textureHeight = uploadH
        }
        guard let tex = latestTexture else {
            lock.unlock()
            return false
        }

        let uploaded: Bool
        if fourCC == Self.fourCC(UInt8(ascii: "U"), UInt8(ascii: "Y"), UInt8(ascii: "V"), UInt8(ascii: "Y")) {
            uploaded = Self.fillUYVYtoBGRAPacked(
                scratch: &uyvyScratch,
                srcWidth: w,
                srcHeight: h,
                dstWidth: uploadW,
                dstHeight: uploadH,
                stride: Int(video.line_stride_in_bytes),
                base: UnsafePointer(pixels)
            ) { base, rowBytes in
                tex.replace(
                    region: MTLRegionMake2D(0, 0, uploadW, uploadH),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: rowBytes
                )
            }
        } else if fourCC == Self.fourCC(UInt8(ascii: "B"), UInt8(ascii: "G"), UInt8(ascii: "R"), UInt8(ascii: "A"))
            || fourCC == Self.fourCC(UInt8(ascii: "B"), UInt8(ascii: "G"), UInt8(ascii: "R"), UInt8(ascii: "X")) {
            uploaded = uploadBGRAFromSource(
                pixels: pixels,
                srcWidth: w,
                srcHeight: h,
                srcStride: Int(video.line_stride_in_bytes),
                uploadWidth: uploadW,
                uploadHeight: uploadH,
                texture: tex
            )
        } else {
            Self.log.warning("Unhandled NDI FourCC \(fourCC); frame skipped.")
            lock.unlock()
            return false
        }

        guard uploaded else {
            lock.unlock()
            return false
        }

        _lastFrameAt = Date()
        let notify = onFrameUpdated
        lock.unlock()
        notify?()
        return true
    }

    private func uploadBGRAFromSource(
        pixels: UnsafeMutablePointer<UInt8>,
        srcWidth w: Int,
        srcHeight h: Int,
        srcStride: Int,
        uploadWidth: Int,
        uploadHeight: Int,
        texture tex: MTLTexture
    ) -> Bool {
        if uploadWidth == w, uploadHeight == h {
            if srcStride == w * 4 {
                tex.replace(
                    region: MTLRegionMake2D(0, 0, w, h),
                    mipmapLevel: 0,
                    withBytes: UnsafeRawPointer(pixels),
                    bytesPerRow: srcStride
                )
                return true
            }
            for y in 0 ..< h {
                let srcRow = pixels.advanced(by: y * srcStride)
                tex.replace(
                    region: MTLRegionMake2D(0, y, w, 1),
                    mipmapLevel: 0,
                    withBytes: srcRow,
                    bytesPerRow: srcStride
                )
            }
            return true
        }

        let fullBytes = w * h * 4
        if bgraScratch.count != fullBytes {
            bgraScratch = Data(count: fullBytes)
        }
        let packed = bgraScratch.withUnsafeMutableBytes { raw -> Bool in
            guard let dstBase = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            if srcStride == w * 4 {
                dstBase.update(from: pixels, count: fullBytes)
                return true
            }
            for y in 0 ..< h {
                let srcRow = pixels.advanced(by: y * srcStride)
                dstBase.advanced(by: y * w * 4).update(from: srcRow, count: w * 4)
            }
            return true
        }
        guard packed else { return false }

        let scaledBytes = uploadWidth * uploadHeight * 4
        if uyvyScratch.count != scaledBytes {
            uyvyScratch = Data(count: scaledBytes)
        }
        let scaled = uyvyScratch.withUnsafeMutableBytes { raw -> Bool in
            guard let dst = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            return bgraScratch.withUnsafeBytes { srcRaw in
                guard let src = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
                return VideoScale.downscaleBGRA(
                    src: src,
                    srcWidth: w,
                    srcHeight: h,
                    dst: dst,
                    dstWidth: uploadWidth,
                    dstHeight: uploadHeight
                )
            }
        }
        guard scaled else { return false }

        uyvyScratch.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            tex.replace(
                region: MTLRegionMake2D(0, 0, uploadWidth, uploadHeight),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: uploadWidth * 4
            )
        }
        return true
    }

    private func updateDimensionsForVideoFrame(width w: Int, height h: Int, metadataXML: String?) {
        lock.lock()
        sourceWidth = w
        sourceHeight = h

        if playback.ndiBandwidth >= 100 {
            programSourceWidth = w
            programSourceHeight = h
        } else if !Self.isLikelyPreviewPixelSize(width: w, height: h),
                  programSourceWidth <= 0 || programSourceHeight <= 0
        {
            programSourceWidth = w
            programSourceHeight = h
        }
        lock.unlock()

        if let metadataXML {
            ingestProgramDimensions(fromXML: metadataXML)
        }
    }

    private func ingestProgramDimensions(fromMetadata metadata: NDIlib_metadata_frame_swift) {
        guard let xml = Self.utf8String(fromOptional: metadata.p_data, declaredLength: metadata.length),
              !xml.isEmpty
        else {
            return
        }
        ingestProgramDimensions(fromXML: xml)
    }

    private func ingestProgramDimensions(fromXML xml: String) {
        guard let (w, h) = NDIMetadataFormatParser.videoDimensions(from: xml) else { return }
        lock.lock()
        programSourceWidth = w
        programSourceHeight = h
        lock.unlock()
    }

    /// NDI `NDIlib_metadata_frame_t`: `length`, `timecode`, then `p_data` (LP64).
    private static func utf8String(fromOptional p: UnsafePointer<CChar>?, declaredLength: Int32) -> String? {
        guard let p else { return nil }
        let maxBytes: Int
        if declaredLength > 0 {
            maxBytes = min(Int(declaredLength), 256 * 1024)
        } else {
            maxBytes = 256 * 1024
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(min(maxBytes, 4096))
        for i in 0 ..< maxBytes {
            let c = UInt8(bitPattern: p[i])
            if c == 0 { break }
            bytes.append(c)
        }
        guard !bytes.isEmpty else { return nil }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Low-bandwidth NDI preview frames are often much smaller than program resolution.
    private static func isLikelyPreviewPixelSize(width: Int, height: Int) -> Bool {
        max(width, height) <= 640 || min(width, height) <= 240
    }

    private func connectionLogLabel() -> String {
        if let ndiDisplayNameCString {
            let s = String(cString: ndiDisplayNameCString)
            if let ndiIPCString {
                return "\(s) [ip \(String(cString: ndiIPCString))]"
            }
            return s
        }
        if let ndiIPCString {
            return String(cString: ndiIPCString)
        }
        return "(no target)"
    }

    /// IPv4 `a.b.c.d:port` only (NDI `p_ip_address` form).
    private static func normalizedIPv4HostPort(_ raw: String) -> (host: String, port: Int)? {
        guard let colon = raw.lastIndex(of: ":"), colon != raw.startIndex else { return nil }
        let hostPart = String(raw[..<colon].trimmingCharacters(in: .whitespaces))
        let portPart = raw[raw.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let port = Int(portPart), (1 ..< 65536).contains(port) else { return nil }
        let octets = hostPart.split(separator: ".").compactMap { octet0to255($0) }
        guard octets.count == 4 else { return nil }
        return ("\(octets[0]).\(octets[1]).\(octets[2]).\(octets[3])", port)
    }

    private static func octet0to255(_ s: Substring) -> Int? {
        guard !s.isEmpty, let n = Int(s), n >= 0, n <= 255 else { return nil }
        return n
    }

    /// Mirrors `NDIlib_recv_create_v3_t` packing on macOS LP64 (`bool` padded to pointer alignment).
    /// First 16 bytes: embedded `NDIlib_source_t` (`p_ndi_name`, then `p_ip_address`).
    private static func makeRecvCreateSettings(
        _ ndiDisplayName: UnsafePointer<CChar>?,
        _ ipHostPort: UnsafePointer<CChar>?,
        recvBandwidth: Int32
    ) -> UnsafeMutableRawPointer {
        let p = UnsafeMutableRawPointer.allocate(byteCount: 48, alignment: 8)
        p.initializeMemory(as: UInt8.self, repeating: 0, count: 48)
        let namePtr: UnsafePointer<CChar>? = ndiDisplayName
        let ipPtrOpt: UnsafePointer<CChar>? = ipHostPort
        let nullRecvChannel: UnsafePointer<CChar>? = nil
        p.storeBytes(of: namePtr, toByteOffset: 0, as: Optional<UnsafePointer<CChar>>.self)
        p.storeBytes(of: ipPtrOpt, toByteOffset: 8, as: Optional<UnsafePointer<CChar>>.self)
        // Prefer native BGRA when the sender provides it; UYVY is converted on receive.
        p.storeBytes(of: Int32(0), toByteOffset: 16, as: Int32.self) // NDIlib_recv_color_format_BGRX_BGRA
        p.storeBytes(of: recvBandwidth, toByteOffset: 20, as: Int32.self)
        p.storeBytes(of: CBool(false), toByteOffset: 24, as: CBool.self)
        p.storeBytes(of: nullRecvChannel, toByteOffset: 32, as: Optional<UnsafePointer<CChar>>.self)
        return p
    }

    private static func makeBGRATexture(device: MTLDevice, width w: Int, height h: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: max(w, 1),
            height: max(h, 1),
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        desc.storageMode = .shared
        return device.makeTexture(descriptor: desc)
    }

    private static func fourCC(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int32 {
        Int32(bitPattern: UInt32(a) | UInt32(b) << 8 | UInt32(c) << 16 | UInt32(d) << 24)
    }

    private static let frameTypeNone: Int32 = 0
    private static let frameTypeVideo: Int32 = 1
    private static let frameTypeMetadata: Int32 = 3
    private static let frameTypeError: Int32 = 4
    private static let frameTypeStatusChange: Int32 = 100

    /// UYVY → packed BGRA8, optionally downscaled while converting.
    private static func fillUYVYtoBGRAPacked(
        scratch: inout Data,
        srcWidth: Int,
        srcHeight: Int,
        dstWidth: Int,
        dstHeight: Int,
        stride rowStride: Int,
        base: UnsafePointer<UInt8>,
        upload: (_ base: UnsafeRawPointer, _ bytesPerRow: Int) -> Void
    ) -> Bool {
        guard srcWidth >= 2, srcWidth.isMultiple(of: 2), rowStride >= srcWidth * 2 else { return false }
        guard dstWidth >= 2, dstHeight >= 2 else { return false }
        guard dstWidth <= srcWidth, dstHeight <= srcHeight else { return false }

        let need = dstWidth * dstHeight * 4
        if scratch.count != need {
            scratch = Data(count: need)
        }

        let scaleX = Float(srcWidth) / Float(dstWidth)
        let scaleY = Float(srcHeight) / Float(dstHeight)

        return scratch.withUnsafeMutableBytes { raw -> Bool in
            guard let dstBase = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
            for dy in 0 ..< dstHeight {
                let sy = min(Int(Float(dy) * scaleY), srcHeight - 1)
                let srcRow = base.advanced(by: sy * rowStride)
                let dstRow = dstBase.advanced(by: dy * dstWidth * 4)
                for dx in 0 ..< dstWidth {
                    let sx = min(Int(Float(dx) * scaleX), srcWidth - 2)
                    let xPair = sx - (sx % 2)
                    let off = xPair * 2
                    let u = Int32(srcRow[off])
                    let y0 = Int32(srcRow[off + 1])
                    let v = Int32(srcRow[off + 2])
                    let y1 = Int32(srcRow[off + 3])
                    let useSecond = sx % 2 == 1
                    let yv = useSecond ? y1 : y0

                    let c = yv - 16
                    let d = u - 128
                    let e = v - 128
                    let ri = (298 * c + 409 * e + 128) >> 8
                    let gi = (298 * c - 100 * d - 208 * e + 128) >> 8
                    let bi = (298 * c + 516 * d + 128) >> 8

                    let dst = dstRow.advanced(by: dx * 4)
                    dst[0] = UInt8(clamping: bi)
                    dst[1] = UInt8(clamping: gi)
                    dst[2] = UInt8(clamping: ri)
                    dst[3] = 255
                }
            }
            upload(raw.baseAddress!, dstWidth * 4)
            return true
        }
    }
}

private struct NDIlib_metadata_frame_swift {
    var length: Int32 = 0
    var timecode: Int64 = 0
    var p_data: UnsafePointer<CChar>?
}

private struct NDIlib_video_frame_v2_swift {
    var xres: Int32 = 0
    var yres: Int32 = 0
    var FourCC: Int32 = 0
    var frame_rate_N: Int32 = 0
    var frame_rate_D: Int32 = 0
    var picture_aspect_ratio: Float = 0
    var frame_format_type: Int32 = 0
    var timecode: Int64 = 0
    var p_data: UnsafeMutablePointer<UInt8>?
    var line_stride_in_bytes: Int32 = 0
    var p_metadata: UnsafePointer<CChar>?
    var timestamp: Int64 = 0
}
