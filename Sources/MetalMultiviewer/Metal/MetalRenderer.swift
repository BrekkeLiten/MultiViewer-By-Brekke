import Foundation
import Metal
import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    enum LayoutMode: Int {
        case oneUp = 1
        case fourUp = 4
    }

    enum ScopeDisplayKind: UInt32 {
        case rgbWaveform = 0
        case rgbParade = 1
        case vectorscope = 2
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let monitoredPipeline: MTLRenderPipelineState
    private let scopeDisplayPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let scopeAnalyzer: ScopeAnalyzer

    private var layoutMode: LayoutMode = .fourUp
    /// Slot to draw in fullscreen when `layoutMode == .oneUp` (Metal slot index 1…4).
    private var primarySlot: Int = 1
    private var oneUpScopeMonitorEnabled = false
    private var scopeMonitorSplit = ScopeMonitorSplit.defaults
    private var pictureMonitoring = PictureMonitoringSettings.defaults

    /// Holds one triangle-strip (4 verts) per 4-up slot; reused each frame with distinct offsets (GPU-safe).
    private var vertexArenaBuffer: MTLBuffer?
    private static let triangleStripVertexCount = 4

    private var viewportSize: SIMD2<Float> = .zero

    /// Black 2×2 texture for unassigned slots or feeds waiting for the first frame.
    private let textureEmpty: MTLTexture

    /// Empty placeholder quads are 2×2; live NDI/DeckLink textures are larger.
    private static let placeholderSide = 2

    private let providerLock = NSLock()
    private var slotProviders: [Int: FrameProvider] = [:]

    init(device: MTLDevice, drawablePixelFormat: MTLPixelFormat) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw NSError(domain: "MetalMultiviewer", code: 1)
        }
        self.commandQueue = commandQueue

        let library = try MetalRenderer.loadLibrary(device: device)
        let vertexFn = library.makeFunction(name: "texturedVertex")
        let fragmentFn = library.makeFunction(name: "texturedFragment")

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.label = "TexturedQuadPipeline"
        pipelineDesc.vertexFunction = vertexFn
        pipelineDesc.fragmentFunction = fragmentFn
        pipelineDesc.colorAttachments[0].pixelFormat = drawablePixelFormat

        pipelineDesc.vertexDescriptor = MetalRenderer.vertexDescriptor
        self.pipeline = try device.makeRenderPipelineState(descriptor: pipelineDesc)

        let monitoredPipelineDesc = MTLRenderPipelineDescriptor()
        monitoredPipelineDesc.label = "MonitoredVideoPipeline"
        monitoredPipelineDesc.vertexFunction = vertexFn
        monitoredPipelineDesc.fragmentFunction = library.makeFunction(name: "monitoredFragment")
        monitoredPipelineDesc.colorAttachments[0].pixelFormat = drawablePixelFormat
        monitoredPipelineDesc.vertexDescriptor = MetalRenderer.vertexDescriptor
        self.monitoredPipeline = try device.makeRenderPipelineState(descriptor: monitoredPipelineDesc)

        let scopePipelineDesc = MTLRenderPipelineDescriptor()
        scopePipelineDesc.label = "ScopeDisplayPipeline"
        scopePipelineDesc.vertexFunction = library.makeFunction(name: "scopeDisplayVertex")
        scopePipelineDesc.fragmentFunction = library.makeFunction(name: "scopeDisplayFragment")
        scopePipelineDesc.colorAttachments[0].pixelFormat = drawablePixelFormat
        scopePipelineDesc.vertexDescriptor = MetalRenderer.vertexDescriptor
        self.scopeDisplayPipeline = try device.makeRenderPipelineState(descriptor: scopePipelineDesc)

        self.scopeAnalyzer = try ScopeAnalyzer(device: device, library: library)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let samp = device.makeSamplerState(descriptor: samplerDesc) else {
            throw NSError(domain: "MetalMultiviewer", code: 2)
        }
        self.sampler = samp

        guard let emptyTexture = MetalRenderer.makeSolidTexture(device: device, rgba: (0, 0, 0, 255)) else {
            throw NSError(domain: "MetalMultiviewer", code: 3)
        }
        self.textureEmpty = emptyTexture

        super.init()
    }

    func setLayoutMode(_ mode: LayoutMode) {
        self.layoutMode = mode
    }

    func setPrimarySlot(_ slot: Int) {
        primarySlot = min(max(slot, 1), 4)
    }

    func setOneUpScopeMonitorEnabled(_ enabled: Bool) {
        oneUpScopeMonitorEnabled = enabled
    }

    func setScopeMonitorSplit(_ split: ScopeMonitorSplit) {
        scopeMonitorSplit = split
    }

    func setPictureMonitoring(_ settings: PictureMonitoringSettings) {
        pictureMonitoring = settings.clamped()
    }

    func setProvider(forSlot slot: Int, provider: FrameProvider?) {
        providerLock.lock()
        defer { providerLock.unlock() }
        if let provider {
            slotProviders[slot] = provider
        } else {
            slotProviders.removeValue(forKey: slot)
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        autoreleasepool {
            guard
                let drawable = view.currentDrawable,
                let rpd = view.currentRenderPassDescriptor,
                let commandBuffer = commandQueue.makeCommandBuffer()
            else { return }

            let quadStripsPerFrame: Int = switch layoutMode {
            case .fourUp: 4
            case .oneUp where oneUpScopeMonitorEnabled: 4
            case .oneUp: 1
            }
            let stripBytes = MemoryLayout<Vertex>.stride * Self.triangleStripVertexCount
            let arenaNeeded = stripBytes * quadStripsPerFrame
            if vertexArenaBuffer == nil || vertexArenaBuffer!.length < arenaNeeded {
                vertexArenaBuffer = device.makeBuffer(length: arenaNeeded, options: [.storageModeShared])
            }
            guard let vb = vertexArenaBuffer else { return }

            let drawableTex = drawable.texture
            let vp = effectiveViewportPx(
                drawableWidth: drawableTex.width,
                drawableHeight: drawableTex.height
            )

            let t1 = feedTexture(forSlot: 1)
            let t2 = feedTexture(forSlot: 2)
            let t3 = feedTexture(forSlot: 3)
            let t4 = feedTexture(forSlot: 4)

            let ps = layoutMode == .oneUp ? primarySlot : 1
            let oneTex = layoutMode == .oneUp ? feedTexture(forSlot: ps) : t1
            if layoutMode == .oneUp, oneUpScopeMonitorEnabled, oneTex.width > Self.placeholderSide {
                scopeAnalyzer.encodeAnalysis(of: oneTex, on: commandBuffer)
            }

            // CPU `replace` on `.storageModeShared` textures is typically visible to the GPU in the same
            // submitted command buffer without `synchronize`; per-frame sync here caused heavy stalls with
            // multiple NDI streams.

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
            else { return }

            encoder.setRenderPipelineState(monitoredPipeline)
            encoder.setFragmentSamplerState(sampler, index: 0)

            switch layoutMode {
            case .oneUp:
                // Reuse the texture fetched for scope analysis above so the scopes and
                // the picture can't show two different frames within one draw.
                if oneUpScopeMonitorEnabled {
                    let scopeRegions = ScopeMonitorLayout.regions(from: scopeMonitorSplit)
                    let pictureCell = Self.ndcRect(from: scopeRegions.picture)
                    drawFittedQuad(
                        encoder: encoder,
                        vb: vb,
                        stripByteOffset: 0,
                        texture: oneTex,
                        cell: pictureCell,
                        slot: ps,
                        viewportPx: vp
                    )

                    var scopeOffset = stripBytes
                    drawScopeQuad(
                        encoder: encoder,
                        vb: vb,
                        stripByteOffset: scopeOffset,
                        texture: scopeAnalyzer.rgbWaveformTexture,
                        cell: Self.ndcRect(from: scopeRegions.rgbWaveform),
                        viewportPx: vp,
                        kind: .rgbWaveform
                    )
                    scopeOffset += stripBytes
                    drawScopeQuad(
                        encoder: encoder,
                        vb: vb,
                        stripByteOffset: scopeOffset,
                        texture: scopeAnalyzer.rgbParadeTexture,
                        cell: Self.ndcRect(from: scopeRegions.rgbParade),
                        viewportPx: vp,
                        kind: .rgbParade
                    )
                    scopeOffset += stripBytes
                    let vectorCell = Self.ndcRect(from: scopeRegions.vectorscope)
                    let vectorDrawRect = Self.vectorscopeDrawRect(cell: vectorCell, viewportPx: vp)
                    drawScopeQuad(
                        encoder: encoder,
                        vb: vb,
                        stripByteOffset: scopeOffset,
                        texture: scopeAnalyzer.vectorscopeTexture,
                        cell: vectorDrawRect,
                        kind: .vectorscope
                    )
                } else {
                    drawFittedQuad(
                        encoder: encoder,
                        vb: vb,
                        stripByteOffset: 0,
                        texture: oneTex,
                        cell: RectNDC.fullscreen,
                        slot: ps,
                        viewportPx: vp
                    )
                }
            case .fourUp:
                drawFittedQuad(
                    encoder: encoder,
                    vb: vb,
                    stripByteOffset: 0,
                    texture: t1,
                    cell: RectNDC.quadrant(.topLeft),
                    slot: 1,
                    viewportPx: vp
                )
                drawFittedQuad(
                    encoder: encoder,
                    vb: vb,
                    stripByteOffset: stripBytes,
                    texture: t2,
                    cell: RectNDC.quadrant(.topRight),
                    slot: 2,
                    viewportPx: vp
                )
                drawFittedQuad(
                    encoder: encoder,
                    vb: vb,
                    stripByteOffset: stripBytes * 2,
                    texture: t3,
                    cell: RectNDC.quadrant(.bottomLeft),
                    slot: 3,
                    viewportPx: vp
                )
                drawFittedQuad(
                    encoder: encoder,
                    vb: vb,
                    stripByteOffset: stripBytes * 3,
                    texture: t4,
                    cell: RectNDC.quadrant(.bottomRight),
                    slot: 4,
                    viewportPx: vp
                )
            }

            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }

    private func feedTexture(forSlot slot: Int) -> MTLTexture {
        guard slotHasProvider(slot), let tex = latestTexture(slot: slot) else {
            return textureEmpty
        }
        return tex
    }

    private func latestTexture(slot: Int) -> MTLTexture? {
        providerLock.lock()
        let provider = slotProviders[slot]
        providerLock.unlock()
        return provider?.copyLatestTexture()
    }

    private func effectiveViewportPx(drawableWidth: Int, drawableHeight: Int) -> SIMD2<Float> {
        if viewportSize.x > 0.5, viewportSize.y > 0.5 {
            return viewportSize
        }
        return SIMD2(Float(max(drawableWidth, 1)), Float(max(drawableHeight, 1)))
    }

    private func slotHasProvider(_ slot: Int) -> Bool {
        providerLock.lock()
        defer { providerLock.unlock() }
        return slotProviders[slot] != nil
    }

    /// `nil` = stretch to cell (no configured feed / unknown).
    private func contentAspectForSlot(_ slot: Int, texture: MTLTexture) -> Float? {
        guard slotHasProvider(slot) else { return nil }
        providerLock.lock()
        let provider = slotProviders[slot]
        providerLock.unlock()
        if let reporter = provider as? VideoBroadcastAspectReporting {
            let r = reporter.broadcastAspectRatio
            if r > 0.001 { return r }
        }
        if let dims = provider as? VideoFeedDimensionReporting {
            let w = dims.feedPixelWidth
            let h = dims.feedPixelHeight
            if w > 0, h > 0 { return Float(w) / Float(h) }
        }
        let w = texture.width
        let h = texture.height
        guard w > 0, h > 0 else { return nil }
        return Float(w) / Float(h)
    }

    private func drawFittedQuad(
        encoder: MTLRenderCommandEncoder,
        vb: MTLBuffer,
        stripByteOffset: Int,
        texture: MTLTexture,
        cell: RectNDC,
        slot: Int,
        viewportPx: SIMD2<Float>
    ) {
        let aspect = contentAspectForSlot(slot, texture: texture)
        let rect = RectNDC.aspectFitBroadcast(cell: cell, contentWidthOverHeight: aspect, viewportPx: viewportPx)
        drawQuad(
            encoder: encoder,
            texture: texture,
            rectNDC: rect,
            vertexBuffer: vb,
            vertexBufferOffsetBytes: stripByteOffset,
            monitoringUniforms: makeMonitoringUniforms(texture: texture)
        )
    }

    private func drawQuad(
        encoder: MTLRenderCommandEncoder,
        texture: MTLTexture,
        rectNDC: RectNDC,
        vertexBuffer: MTLBuffer,
        vertexBufferOffsetBytes: Int,
        pipeline: MTLRenderPipelineState? = nil,
        monitoringUniforms: PictureMonitoringUniforms? = nil,
        fragmentUniforms: ScopeDisplayUniforms? = nil,
        uvMin: SIMD2<Float> = SIMD2(0, 0),
        uvMax: SIMD2<Float> = SIMD2(1, 1)
    ) {
        // Write the strip directly into the arena buffer — no per-draw array allocation.
        // Triangle strip order: TL, BL, TR, BR.
        let verts = vertexBuffer.contents()
            .advanced(by: vertexBufferOffsetBytes)
            .assumingMemoryBound(to: Vertex.self)
        verts[0] = Vertex(position: SIMD2(rectNDC.minX, rectNDC.maxY), uv: SIMD2(uvMin.x, uvMin.y))
        verts[1] = Vertex(position: SIMD2(rectNDC.minX, rectNDC.minY), uv: SIMD2(uvMin.x, uvMax.y))
        verts[2] = Vertex(position: SIMD2(rectNDC.maxX, rectNDC.maxY), uv: SIMD2(uvMax.x, uvMin.y))
        verts[3] = Vertex(position: SIMD2(rectNDC.maxX, rectNDC.minY), uv: SIMD2(uvMax.x, uvMax.y))

        if let pipeline {
            encoder.setRenderPipelineState(pipeline)
        }
        encoder.setVertexBuffer(vertexBuffer, offset: vertexBufferOffsetBytes, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        if var uniforms = monitoringUniforms {
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<PictureMonitoringUniforms>.stride, index: 0)
        } else if var uniforms = fragmentUniforms {
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<ScopeDisplayUniforms>.stride, index: 0)
        }
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.triangleStripVertexCount
        )
        if pipeline != nil {
            encoder.setRenderPipelineState(monitoredPipeline)
        }
    }

    private struct PictureMonitoringUniforms {
        var flags: UInt32
        var peakingThreshold: Float
        var zebraLevel: Float
        var texelSize: SIMD2<Float>
        var peakingColor: SIMD4<Float>
    }

    private struct ScopeDisplayUniforms {
        var scopeKind: UInt32
    }

    private func makeMonitoringUniforms(texture: MTLTexture) -> PictureMonitoringUniforms {
        var flags: UInt32 = 0
        if pictureMonitoring.focusPeakingEnabled { flags |= 1 }
        if pictureMonitoring.falseColorEnabled { flags |= 2 }
        if pictureMonitoring.zebraEnabled { flags |= 4 }
        let rgb = pictureMonitoring.focusPeakingColor.linearRGB
        let w = max(texture.width, 1)
        let h = max(texture.height, 1)
        return PictureMonitoringUniforms(
            flags: flags,
            peakingThreshold: pictureMonitoring.focusPeakingSensitivity,
            zebraLevel: pictureMonitoring.zebraLevel,
            texelSize: SIMD2(1.0 / Float(w), 1.0 / Float(h)),
            peakingColor: SIMD4(rgb.r, rgb.g, rgb.b, 0)
        )
    }

    private func drawScopeQuad(
        encoder: MTLRenderCommandEncoder,
        vb: MTLBuffer,
        stripByteOffset: Int,
        texture: MTLTexture,
        cell: RectNDC,
        viewportPx: SIMD2<Float> = SIMD2(1, 1),
        kind: ScopeDisplayKind
    ) {
        let uniforms = ScopeDisplayUniforms(scopeKind: kind.rawValue)
        let traceCell: RectNDC = switch kind {
        case .rgbWaveform, .rgbParade:
            Self.scopeTraceRect(in: cell, viewportPx: viewportPx)
        case .vectorscope:
            cell
        }
        drawQuad(
            encoder: encoder,
            texture: texture,
            rectNDC: traceCell,
            vertexBuffer: vb,
            vertexBufferOffsetBytes: stripByteOffset,
            pipeline: scopeDisplayPipeline,
            fragmentUniforms: uniforms
        )
    }

    /// Trace area inside a scope panel, matching overlay label gutter and scale rail insets.
    private static func scopeTraceRect(in cell: RectNDC, viewportPx: SIMD2<Float>) -> RectNDC {
        let cellWidthNdc = cell.maxX - cell.minX
        let panelWidthPx = cellWidthNdc * 0.5 * viewportPx.x
        let gutter = ScopeIntensityScale.traceLeftInsetNDC(cellWidthNdc: cellWidthNdc, panelWidthPx: panelWidthPx)
        let panelHeightPx = max((cell.maxY - cell.minY) * 0.5 * viewportPx.y, 1)
        let topInsetNdc = (ScopeIntensityScale.scaleTopInsetPx / panelHeightPx) * (cell.maxY - cell.minY)
        let bottomInsetNdc = (ScopeIntensityScale.scaleBottomInsetPx / panelHeightPx) * (cell.maxY - cell.minY)
        return RectNDC(
            minX: cell.minX + gutter,
            maxX: cell.maxX,
            minY: cell.minY + bottomInsetNdc,
            maxY: cell.maxY - topInsetNdc
        )
    }

    /// Square vectorscope inset and scaled down within its layout cell.
    private static func vectorscopeDrawRect(cell: RectNDC, viewportPx: SIMD2<Float>) -> RectNDC {
        let square = RectNDC.aspectFitBroadcast(cell: cell, contentWidthOverHeight: 1, viewportPx: viewportPx)
        let scale = ScopeMonitorLayout.vectorscopeDiameterFraction
        let cx = (square.minX + square.maxX) * 0.5
        let cy = (square.minY + square.maxY) * 0.5
        let halfW = (square.maxX - square.minX) * 0.5 * scale
        let halfH = (square.maxY - square.minY) * 0.5 * scale
        return RectNDC(minX: cx - halfW, maxX: cx + halfW, minY: cy - halfH, maxY: cy + halfH)
    }

    private static func ndcRect(from region: ScopeMonitorLayout.NDCRegion) -> RectNDC {
        RectNDC(minX: region.minX, maxX: region.maxX, minY: region.minY, maxY: region.maxY)
    }
}

private extension MetalRenderer {
    struct Vertex {
        var position: SIMD2<Float>
        var uv: SIMD2<Float>
    }

    enum Quad {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    struct RectNDC {
        var minX: Float
        var maxX: Float
        var minY: Float
        var maxY: Float

        static let fullscreen = RectNDC(minX: -1, maxX: 1, minY: -1, maxY: 1)

        static func quadrant(_ q: Quad) -> RectNDC {
            switch q {
            case .topLeft: return RectNDC(minX: -1, maxX: 0, minY: 0, maxY: 1)
            case .topRight: return RectNDC(minX: 0, maxX: 1, minY: 0, maxY: 1)
            case .bottomLeft: return RectNDC(minX: -1, maxX: 0, minY: -1, maxY: 0)
            case .bottomRight: return RectNDC(minX: 0, maxX: 1, minY: -1, maxY: 0)
            }
        }

        /// Letterboxed / pillarboxed fit preserving broadcast aspect inside `cell` (NDC coords, y upward).
        static func aspectFitBroadcast(
            cell: RectNDC,
            contentWidthOverHeight: Float?,
            viewportPx: SIMD2<Float>
        ) -> RectNDC {
            guard let ar = contentWidthOverHeight, ar > 0.001, viewportPx.x > 1, viewportPx.y > 1 else {
                return cell
            }
            let cwNDC = cell.maxX - cell.minX
            let chNDC = cell.maxY - cell.minY
            let halfWRecip: Float = 2 / viewportPx.x
            let halfHRecip: Float = 2 / viewportPx.y
            let cellWpx = cwNDC / halfWRecip
            let cellHpx = chNDC / halfHRecip
            guard cellWpx > 1, cellHpx > 1 else { return cell }

            let cellAR = cellWpx / cellHpx
            let fitWpx: Float
            let fitHpx: Float
            if ar > cellAR {
                fitWpx = cellWpx
                fitHpx = cellWpx / ar
            } else {
                fitHpx = cellHpx
                fitWpx = cellHpx * ar
            }

            let ndcW = fitWpx * halfWRecip
            let ndcH = fitHpx * halfHRecip

            let cx = (cell.minX + cell.maxX) * 0.5
            let cy = (cell.minY + cell.maxY) * 0.5

            return RectNDC(
                minX: cx - ndcW * 0.5,
                maxX: cx + ndcW * 0.5,
                minY: cy - ndcH * 0.5,
                maxY: cy + ndcH * 0.5
            )
        }

    }

    static var vertexDescriptor: MTLVertexDescriptor {
        let vd = MTLVertexDescriptor()
        vd.attributes[0].format = .float2
        vd.attributes[0].offset = 0
        vd.attributes[0].bufferIndex = 0

        vd.attributes[1].format = .float2
        vd.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vd.attributes[1].bufferIndex = 0

        vd.layouts[0].stride = MemoryLayout<Vertex>.stride
        vd.layouts[0].stepFunction = .perVertex
        return vd
    }

    static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        var source = ""
        for name in ["Shaders", "ScopeShaders"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "metal") else {
                throw NSError(domain: "MetalMultiviewer", code: 10, userInfo: [NSLocalizedDescriptionKey: "Missing \(name).metal"])
            }
            source += try String(contentsOf: url)
            source += "\n"
        }
        return try device.makeLibrary(source: source, options: nil)
    }

    static func makeSolidTexture(device: MTLDevice, rgba: (UInt8, UInt8, UInt8, UInt8)) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 2 * 2 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i + 0] = rgba.0
            bytes[i + 1] = rgba.1
            bytes[i + 2] = rgba.2
            bytes[i + 3] = rgba.3
        }
        tex.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 2 * 4)
        return tex
    }
}

