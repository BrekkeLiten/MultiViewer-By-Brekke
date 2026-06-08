import Foundation
import Metal
import MetalKit

final class MetalRenderer: NSObject, MTKViewDelegate, @unchecked Sendable {
    enum LayoutMode: Int {
        case oneUp = 1
        case fourUp = 4
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    private var layoutMode: LayoutMode = .fourUp
    /// Slot to draw in fullscreen when `layoutMode == .oneUp` (Metal slot index 1…4).
    private var primarySlot: Int = 1

    /// Holds one triangle-strip (4 verts) per 4-up slot; reused each frame with distinct offsets (GPU-safe).
    private var vertexArenaBuffer: MTLBuffer?
    private static let triangleStripVertexCount = 4

    private var viewportSize: SIMD2<Float> = .zero

    private let textureA: MTLTexture
    private let textureB: MTLTexture
    private let textureC: MTLTexture
    private let textureD: MTLTexture

    /// Placeholder quads from `makeSolidTexture` are 2×2; live NDI/DeckLink textures are larger.
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

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        guard let samp = device.makeSamplerState(descriptor: samplerDesc) else {
            throw NSError(domain: "MetalMultiviewer", code: 2)
        }
        self.sampler = samp

        // Dummy test textures (solid colors).
        self.textureA = MetalRenderer.makeSolidTexture(device: device, rgba: (255, 80, 80, 255))
        self.textureB = MetalRenderer.makeSolidTexture(device: device, rgba: (80, 255, 80, 255))
        self.textureC = MetalRenderer.makeSolidTexture(device: device, rgba: (80, 80, 255, 255))
        self.textureD = MetalRenderer.makeSolidTexture(device: device, rgba: (240, 200, 80, 255))

        super.init()
    }

    func setLayoutMode(_ mode: LayoutMode) {
        self.layoutMode = mode
    }

    func setPrimarySlot(_ slot: Int) {
        primarySlot = min(max(slot, 1), 4)
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

            let quadStripsPerFrame = layoutMode == .fourUp ? 4 : 1
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

            let t1 = latestTexture(slot: 1) ?? textureA
            let t2 = latestTexture(slot: 2) ?? textureB
            let t3 = latestTexture(slot: 3) ?? textureC
            let t4 = latestTexture(slot: 4) ?? textureD

            // CPU `replace` on `.storageModeShared` textures is typically visible to the GPU in the same
            // submitted command buffer without `synchronize`; per-frame sync here caused heavy stalls with
            // multiple NDI streams.

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)
            else { return }

            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentSamplerState(sampler, index: 0)

            switch layoutMode {
            case .oneUp:
                let ps = primarySlot
                let oneTex = textureForPrimarySlot(ps, t1: t1, t2: t2, t3: t3, t4: t4)
                drawFittedQuad(
                    encoder: encoder,
                    vb: vb,
                    stripByteOffset: 0,
                    texture: oneTex,
                    cell: RectNDC.fullscreen,
                    slot: ps,
                    viewportPx: vp
                )
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

    /// Chooses slot `N`'s texture or colored placeholder consistent with four-up placeholders.
    private func textureForPrimarySlot(
        _ slot: Int,
        t1: MTLTexture,
        t2: MTLTexture,
        t3: MTLTexture,
        t4: MTLTexture
    ) -> MTLTexture {
        switch slot {
        case 2: return latestTexture(slot: 2) ?? t2
        case 3: return latestTexture(slot: 3) ?? t3
        case 4: return latestTexture(slot: 4) ?? t4
        default: return latestTexture(slot: 1) ?? t1
        }
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
            vertexBufferOffsetBytes: stripByteOffset
        )
    }

    private func drawQuad(
        encoder: MTLRenderCommandEncoder,
        texture: MTLTexture,
        rectNDC: RectNDC,
        vertexBuffer: MTLBuffer,
        vertexBufferOffsetBytes: Int
    ) {
        let verts = rectNDC.makeTriangleStripVertices()
        assert(verts.count == Self.triangleStripVertexCount)
        let len = MemoryLayout<Vertex>.stride * verts.count
        verts.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            vertexBuffer.contents()
                .advanced(by: vertexBufferOffsetBytes)
                .copyMemory(from: src, byteCount: len)
        }

        encoder.setVertexBuffer(vertexBuffer, offset: vertexBufferOffsetBytes, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: Self.triangleStripVertexCount
        )
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

        func makeTriangleStripVertices() -> [Vertex] {
            // Triangle strip order: TL, BL, TR, BR
            return [
                Vertex(position: SIMD2(minX, maxY), uv: SIMD2(0, 0)),
                Vertex(position: SIMD2(minX, minY), uv: SIMD2(0, 1)),
                Vertex(position: SIMD2(maxX, maxY), uv: SIMD2(1, 0)),
                Vertex(position: SIMD2(maxX, minY), uv: SIMD2(1, 1)),
            ]
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
        guard let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal") else {
            throw NSError(domain: "MetalMultiviewer", code: 10)
        }
        let source = try String(contentsOf: url)
        return try device.makeLibrary(source: source, options: nil)
    }

    static func makeSolidTexture(device: MTLDevice, rgba: (UInt8, UInt8, UInt8, UInt8)) -> MTLTexture {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 2,
            height: 2,
            mipmapped: false
        )
        desc.usage = [.shaderRead]
        let tex = device.makeTexture(descriptor: desc)!
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

