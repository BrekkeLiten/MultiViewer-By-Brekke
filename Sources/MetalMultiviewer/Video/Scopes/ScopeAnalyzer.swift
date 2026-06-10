import Foundation
import Metal

/// GPU histogram → scope textures for 1-up shading monitor.
final class ScopeAnalyzer: @unchecked Sendable {
    static let analysisColumns = 512
    static let analysisLevels = 256
    static let vectorscopeSize = 1024

    private let device: MTLDevice
    private let accumulatePipeline: MTLComputePipelineState
    private let buildRGBWaveformPipeline: MTLComputePipelineState
    private let buildRGBParadePipeline: MTLComputePipelineState
    private let buildVectorscopePipeline: MTLComputePipelineState

    private let rgbHistBuffer: MTLBuffer
    private let vectorscopeHistBuffer: MTLBuffer

    private(set) var rgbWaveformTexture: MTLTexture
    private(set) var rgbParadeTexture: MTLTexture
    private(set) var vectorscopeTexture: MTLTexture

    init(device: MTLDevice, library: MTLLibrary) throws {
        self.device = device

        accumulatePipeline = try Self.makeComputePipeline(library: library, name: "scopeAccumulateHistogramKernel")
        buildRGBWaveformPipeline = try Self.makeComputePipeline(library: library, name: "scopeBuildRGBWaveformKernel")
        buildRGBParadePipeline = try Self.makeComputePipeline(library: library, name: "scopeBuildRGBParadeKernel")
        buildVectorscopePipeline = try Self.makeComputePipeline(library: library, name: "scopeBuildVectorscopeKernel")

        let rgbCount = Self.analysisColumns * 3 * Self.analysisLevels
        let vectorCount = Self.vectorscopeSize * Self.vectorscopeSize

        guard
            let rgbHist = device.makeBuffer(length: rgbCount * MemoryLayout<UInt32>.stride, options: .storageModeShared),
            let vectorHist = device.makeBuffer(length: vectorCount * MemoryLayout<UInt32>.stride, options: .storageModeShared),
            let waveform = Self.makeScopeTexture(device: device, width: Self.analysisColumns, height: Self.analysisLevels),
            let parade = Self.makeScopeTexture(device: device, width: Self.analysisColumns * 3, height: Self.analysisLevels),
            let vectorscope = Self.makeScopeTexture(device: device, width: Self.vectorscopeSize, height: Self.vectorscopeSize)
        else {
            throw NSError(domain: "ScopeAnalyzer", code: 2, userInfo: [NSLocalizedDescriptionKey: "GPU resource allocation failed"])
        }
        rgbHistBuffer = rgbHist
        vectorscopeHistBuffer = vectorHist
        rgbWaveformTexture = waveform
        rgbParadeTexture = parade
        vectorscopeTexture = vectorscope
    }

    func encodeAnalysis(of source: MTLTexture, on commandBuffer: MTLCommandBuffer) {
        guard source.width > 2, source.height > 2 else { return }

        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.fill(buffer: rgbHistBuffer, range: 0 ..< rgbHistBuffer.length, value: 0)
            blit.fill(buffer: vectorscopeHistBuffer, range: 0 ..< vectorscopeHistBuffer.length, value: 0)
            blit.endEncoding()
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(accumulatePipeline)
        encoder.setTexture(source, index: 0)
        encoder.setBuffer(rgbHistBuffer, offset: 0, index: 0)
        encoder.setBuffer(vectorscopeHistBuffer, offset: 0, index: 1)
        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(
            width: (source.width + 15) / 16,
            height: (source.height + 15) / 16,
            depth: 1
        )
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)

        encoder.setComputePipelineState(buildRGBWaveformPipeline)
        encoder.setTexture(rgbWaveformTexture, index: 0)
        encoder.setBuffer(rgbHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.analysisColumns, height: Self.analysisLevels)

        encoder.setComputePipelineState(buildRGBParadePipeline)
        encoder.setTexture(rgbParadeTexture, index: 0)
        encoder.setBuffer(rgbHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.analysisColumns * 3, height: Self.analysisLevels)

        encoder.setComputePipelineState(buildVectorscopePipeline)
        encoder.setTexture(vectorscopeTexture, index: 0)
        encoder.setBuffer(vectorscopeHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.vectorscopeSize, height: Self.vectorscopeSize)

        encoder.endEncoding()
    }

    /// Zeros histogram buffers and rebuilds scope textures so panels go black when no feed is present.
    func encodeClear(on commandBuffer: MTLCommandBuffer) {
        if let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.fill(buffer: rgbHistBuffer, range: 0 ..< rgbHistBuffer.length, value: 0)
            blit.fill(buffer: vectorscopeHistBuffer, range: 0 ..< vectorscopeHistBuffer.length, value: 0)
            blit.endEncoding()
        }

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(buildRGBWaveformPipeline)
        encoder.setTexture(rgbWaveformTexture, index: 0)
        encoder.setBuffer(rgbHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.analysisColumns, height: Self.analysisLevels)

        encoder.setComputePipelineState(buildRGBParadePipeline)
        encoder.setTexture(rgbParadeTexture, index: 0)
        encoder.setBuffer(rgbHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.analysisColumns * 3, height: Self.analysisLevels)

        encoder.setComputePipelineState(buildVectorscopePipeline)
        encoder.setTexture(vectorscopeTexture, index: 0)
        encoder.setBuffer(vectorscopeHistBuffer, offset: 0, index: 0)
        dispatch2D(encoder: encoder, width: Self.vectorscopeSize, height: Self.vectorscopeSize)

        encoder.endEncoding()
    }

    private func dispatch2D(encoder: MTLComputeCommandEncoder, width: Int, height: Int) {
        let tgSize = MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = MTLSize(width: (width + 15) / 16, height: (height + 15) / 16, depth: 1)
        encoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
    }

    private static func makeComputePipeline(library: MTLLibrary, name: String) throws -> MTLComputePipelineState {
        guard let fn = library.makeFunction(name: name) else {
            throw NSError(domain: "ScopeAnalyzer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing \(name)"])
        }
        return try library.device.makeComputePipelineState(function: fn)
    }

    private static func makeScopeTexture(device: MTLDevice, width: Int, height: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: desc)
    }
}
