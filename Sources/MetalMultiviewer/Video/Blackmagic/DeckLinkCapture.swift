import DeckLinkBridge
import Foundation
import Metal
import os.log

/// Live SDI/HDMI capture via Blackmagic DeckLink Desktop Video APIs (BGRA8 path).
final class DeckLinkCapture: MonitorableProvider, VideoFeedDimensionReporting, VideoBroadcastAspectReporting,
    DisplaySizedUploadProvider, FrameUpdateNotifying, @unchecked Sendable
{
	private static let log = Logger(subsystem: "MetalMultiviewer", category: "DeckLink")

	private let device: MTLDevice
	private let inputIndex: Int
	private let playback: MonitorPlayback

	private let lock = NSLock()
	private var latestTexture: MTLTexture?
	private var sourceWidth = 0
	private var sourceHeight = 0
	private var isRunning = false
	private var _lastFrameAt: Date?

	/// Capture-thread-only texture ring: the CPU writes the next texture while the GPU may still be
	/// sampling the published one (3 deep covers command buffers in flight). No lock needed.
	private var texturePool: [MTLTexture] = []
	private var texturePoolIndex = 0
	private var textureWidth = 0
	private var textureHeight = 0
	private static let texturePoolDepth = 3

	private var thread: Thread?
	private var lastTextureUploadAt = Date.distantPast
	private var bgraScratch = Data()
	private var scaledScratch = Data()

	private var targetUploadWidth = -1
	private var targetUploadHeight = -1

	var onFrameUpdated: (@Sendable () -> Void)?

	init(device: MTLDevice, inputIndex: Int, playback: MonitorPlayback) {
		self.device = device
		self.inputIndex = inputIndex
		self.playback = playback
	}

	func start() {
		lock.lock()
		defer { lock.unlock() }
		guard !isRunning else { return }
		isRunning = true

		let t = Thread { [weak self] in
			self?.captureThreadMain()
		}
		t.name = "DeckLinkCapture(\(inputIndex))"
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
		return sourceWidth
	}

	var feedPixelHeight: Int {
		lock.lock()
		defer { lock.unlock() }
		return sourceHeight
	}

	var broadcastAspectRatio: Float {
		lock.lock()
		defer { lock.unlock() }
		guard sourceWidth > 0, sourceHeight > 0 else { return 0 }
		return Float(sourceWidth) / Float(sourceHeight)
	}

	private func captureThreadMain() {
		guard let drv = mvDeckLinkDriverCreate() else {
			Self.log.error("DeckLink: could not allocate driver.")
			return
		}
		defer {
			mvDeckLinkDriverRelease(drv)
			lock.lock()
			latestTexture = nil
			sourceWidth = 0
			sourceHeight = 0
			lock.unlock()
			texturePool = []
			texturePoolIndex = 0
			textureWidth = 0
			textureHeight = 0
		}

		let startedOk = mvDeckLinkDriverStart(drv, Int32(inputIndex))
		if !startedOk {
			var failStage: Int32 = 0
			var failHR: Int32 = 0
			mvDeckLinkDriverGetLastStartFailure(&failStage, &failHR)
			Self.log.error(
				"DeckLink: could not start device index \(self.inputIndex, privacy: .public) (failStage=\(failStage, privacy: .public) HRESULT=\(failHR, privacy: .public)). Install Desktop Video; check `sdi:` index."
			)
			return
		}
		defer {
			mvDeckLinkDriverStop(drv)
		}

		var scratch = Data()
		while true {
			lock.lock()
			let running = isRunning
			lock.unlock()
			if !running { break }

			var fw: Int32 = 0
			var fh: Int32 = 0
			var have = false
			_ = mvDeckLinkDriverPeekDimensions(drv, &fw, &fh, &have)
			let needBytes = Int(fw * fh * 4)
			let now = Date()
			let iv = playback.minTextureUploadInterval
			let allowUpload = iv <= 0 || now.timeIntervalSince(lastTextureUploadAt) >= iv

			lock.lock()
			let tw = targetUploadWidth
			let th = targetUploadHeight
			lock.unlock()

			if tw == 0 || th == 0 {
				Thread.sleep(forTimeInterval: 0.016)
				continue
			}

			if have, fw > 0, fh > 0, needBytes > 0, allowUpload {
				if scratch.count != needBytes {
					scratch = Data(count: needBytes)
				}
				var info = MVDeckLinkFramePacked(width: 0, height: 0, valid: false)
				let ok = scratch.withUnsafeMutableBytes { raw -> Bool in
					guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self), raw.count >= needBytes else {
						return false
					}
					return mvDeckLinkDriverCopyLatestBGRAPacked(drv, base, raw.count, &info)
				}
				if ok && info.valid {
					if processBGRA(data: scratch, byteCount: needBytes, width: Int(info.width), height: Int(info.height)) {
						lock.lock()
						_lastFrameAt = Date()
						lock.unlock()
						lastTextureUploadAt = Date()
					}
				} else {
					Thread.sleep(forTimeInterval: 0.004)
				}
			} else if have, fw > 0, fh > 0, needBytes > 0 {
				Thread.sleep(forTimeInterval: min(max(iv * 0.2, 0.004), 0.02))
			} else {
				Thread.sleep(forTimeInterval: 0.016)
			}
		}
	}

	private func processBGRA(data: Data, byteCount: Int, width w: Int, height h: Int) -> Bool {
		guard w > 0, h > 0, byteCount >= w * h * 4 else { return false }

		lock.lock()
		sourceWidth = w
		sourceHeight = h
		let tw = targetUploadWidth
		let th = targetUploadHeight
		lock.unlock()

		if tw == 0 || th == 0 { return false }

		let uploadW: Int
		let uploadH: Int
		if tw < 0 || th < 0 {
			uploadW = w
			uploadH = h
		} else {
			uploadW = min(max(tw, 2), w)
			uploadH = min(max(th, 2), h)
		}

		// Texture ring is owned by this thread; the upload below runs without the lock so the
		// render path's copyLatestTexture()/getters never block on a full-frame scale + copy.
		if textureWidth != uploadW || textureHeight != uploadH || texturePool.count < Self.texturePoolDepth {
			var pool: [MTLTexture] = []
			for _ in 0 ..< Self.texturePoolDepth {
				let desc = MTLTextureDescriptor.texture2DDescriptor(
					pixelFormat: .bgra8Unorm,
					width: uploadW,
					height: uploadH,
					mipmapped: false
				)
				desc.usage = [.shaderRead]
				desc.storageMode = .shared
				guard let tex = device.makeTexture(descriptor: desc) else {
					Self.log.error("DeckLink: makeTexture failed for \(uploadW, privacy: .public)×\(uploadH, privacy: .public).")
					return false
				}
				pool.append(tex)
			}
			texturePool = pool
			texturePoolIndex = 0
			textureWidth = uploadW
			textureHeight = uploadH
		}
		let tex = texturePool[texturePoolIndex]
		texturePoolIndex = (texturePoolIndex + 1) % texturePool.count

		let uploaded: Bool
		if uploadW == w, uploadH == h {
			uploaded = data.withUnsafeBytes { raw -> Bool in
				guard raw.count >= w * h * 4, let src = raw.baseAddress else { return false }
				tex.replace(
					region: MTLRegionMake2D(0, 0, w, h),
					mipmapLevel: 0,
					withBytes: src,
					bytesPerRow: w * 4
				)
				return true
			}
		} else {
			uploaded = data.withUnsafeBytes { raw -> Bool in
				guard raw.count >= w * h * 4, let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
					return false
				}
				let scaledBytes = uploadW * uploadH * 4
				if scaledScratch.count != scaledBytes {
					scaledScratch = Data(count: scaledBytes)
				}
				return scaledScratch.withUnsafeMutableBytes { dstRaw -> Bool in
					guard let dst = dstRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return false }
					guard VideoScale.downscaleBGRA(
						src: src,
						srcWidth: w,
						srcHeight: h,
						dst: dst,
						dstWidth: uploadW,
						dstHeight: uploadH
					) else { return false }
					tex.replace(
						region: MTLRegionMake2D(0, 0, uploadW, uploadH),
						mipmapLevel: 0,
						withBytes: dst,
						bytesPerRow: uploadW * 4
					)
					return true
				}
			}
		}

		guard uploaded else { return false }

		lock.lock()
		latestTexture = tex
		let notify = onFrameUpdated
		lock.unlock()
		notify?()
		return true
	}
}
