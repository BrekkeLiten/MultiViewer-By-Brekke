import CoreGraphics
import Foundation
import Testing
@testable import MetalMultiviewer

@Test
func configLoaderEffectivePortDefaultsTo8080() {
    #expect(ConfigLoader.effectivePort(config: nil) == 8080)
}

@Test
func monitorPlaybackDefaultsUseFullNdiQualityAnd30Fps() {
    let p = MonitorPlayback.from(config: .empty)
    #expect(p.ndiBandwidth == 100)
    #expect(abs(p.minTextureUploadInterval - 1.0 / 30.0) < 0.000_1)
}

@Test
func monitorPlaybackLowBandwidthWhenExplicitlyDisabled() {
    var cfg = AppConfig.empty
    cfg.ndiFullQuality = false
    cfg.previewMaxFPS = 60
    let p = MonitorPlayback.from(config: cfg)
    #expect(p.ndiBandwidth == 0)
    #expect(abs(p.minTextureUploadInterval - 1.0 / 60.0) < 0.000_1)
}

@Test
func displayUploadGeometryGrid2x2CellIsHalfViewport() {
    let split = GridSplit.equal(columns: 2, rows: 2)
    let cell = DisplayUploadGeometry.cellPixelSize(
        slot: 2,
        layout: .grid(columns: 2, rows: 2, split: split),
        viewportWidth: 1920,
        viewportHeight: 1080
    )
    #expect(cell.width == 960)
    #expect(cell.height == 540)
}

@Test
func displayUploadGeometryDownscalesToFitOnScreen() {
    let target = DisplayUploadGeometry.uploadPixelSize(
        sourceWidth: 1920,
        sourceHeight: 1080,
        cellWidth: 960,
        cellHeight: 540,
        contentWidthOverHeight: 16.0 / 9.0
    )
    #expect(target.width == 960)
    #expect(target.height == 540)
}

@Test
func multiviewBadgeTextShowsSlotWhenEmpty() {
    #expect(
        SourceDisplayLabels.multiviewBadgeText(
            slot: 3,
            sourcePersistenceString: nil,
            pixelWidth: 0,
            pixelHeight: 0
        ) == "Slot 3"
    )
}

@Test
func multiviewBadgeTextIncludesNameAndResolution() {
    let text = SourceDisplayLabels.multiviewBadgeText(
        slot: 1,
        sourcePersistenceString: "ndi:MACBOOK (Arena - Composition)",
        pixelWidth: 1920,
        pixelHeight: 1080
    )
    #expect(text.contains("Arena - Composition"))
    #expect(text.contains("1920×1080"))
}

@Test
func ndiDisplayLabelIncludesHostAndStreamName() {
    let label = SourceDisplayLabels.displayLabel(
        for: "ndi:MACBOOK-PRO-4.LOCAL (Arena - Composition)"
    )
    #expect(label.contains("MACBOOK-PRO-4"))
    #expect(label.contains("Arena - Composition"))
    #expect(label.contains("·"))
}

@Test
func ndiDisplayLabelWithoutParensUsesHostOnly() {
    let label = SourceDisplayLabels.displayLabel(for: "ndi:192.168.1.10:5961")
    #expect(label == "192.168.1.10:5961")
}

@Test
func configLoaderControlBindAddressDefaultsToLocalhost() {
    #expect(ConfigLoader.persistedControlBindAddress(config: nil) == "127.0.0.1")
    #expect(ConfigLoader.persistedControlBindAddress(config: .empty) == "127.0.0.1")
}

@Test
func controlURLUsesLocalhostForLoopbackBind() {
    #expect(NetworkInterfaceDiscovery.controlURL(bindAddress: "127.0.0.1", port: 8080) == "http://127.0.0.1:8080")
}

@Test
func controlURLUsesFirstLanIPWhenBoundToAllInterfaces() {
    let url = NetworkInterfaceDiscovery.controlURL(bindAddress: "0.0.0.0", port: 9000)
    #expect(url.hasPrefix("http://"))
    #expect(url.hasSuffix(":9000"))
    #expect(!url.contains("0.0.0.0"))
}

@Test
func bindOptionsExcludeVirtualBridgeInterfaces() {
    for option in NetworkInterfaceDiscovery.bindOptions() {
        #expect(!option.label.contains("(bridge"))
    }
}

@Test
func ndiMetadataParserReadsVideoFormatDimensions() {
    let xml = """
    <ndi_format>
      <video_format xres="1920" yres="1080" frame_rate_n="60000" frame_rate_d="1001"/>
    </ndi_format>
    """
    let dims = NDIMetadataFormatParser.videoDimensions(from: xml)
    #expect(dims?.width == 1920)
    #expect(dims?.height == 1080)
}

@Test
func displayUploadGeometryHiddenSlotSkipsUpload() {
    let cell = DisplayUploadGeometry.cellPixelSize(
        slot: 2,
        layout: .oneUp(primarySlot: 1),
        viewportWidth: 1920,
        viewportHeight: 1080
    )
    #expect(cell.width == 0)
    #expect(cell.height == 0)
}

@Test
func displayUploadGeometryOneUpScopeMonitorUsesPictureHeavyCell() {
    let cell = DisplayUploadGeometry.cellPixelSize(
        slot: 1,
        layout: .oneUpScopeMonitor(primarySlot: 1, split: .defaults),
        viewportWidth: 1920,
        viewportHeight: 1080
    )
    #expect(cell.width == 1228)
    #expect(cell.height == 777)
}

@Test
func displayUploadGeometryOneUpScopeMonitorRespectsCustomSplit() {
    let split = ScopeMonitorSplit(columnFraction: 0.5, rowFraction: 0.5)
    let cell = DisplayUploadGeometry.cellPixelSize(
        slot: 1,
        layout: .oneUpScopeMonitor(primarySlot: 1, split: split),
        viewportWidth: 1000,
        viewportHeight: 800
    )
    #expect(cell.width == 500)
    #expect(cell.height == 400)
}

@Test
func scopeMonitorSplitClampsOutOfRangeValues() {
    let split = ScopeMonitorSplit(columnFraction: 0.1, rowFraction: 0.99)
    #expect(split.columnFraction == ScopeMonitorSplit.columnRange.lowerBound)
    #expect(split.rowFraction == ScopeMonitorSplit.rowRange.upperBound)
}

@Test
func scopeMonitorLayoutNDCRegionsFormLiveScopesGrid() {
    let regions = ScopeMonitorLayout.regions(from: .defaults)
    #expect(abs(regions.picture.maxX - 0.28) < 0.001)
    #expect(abs(regions.vectorscope.minX - 0.28) < 0.001)
    #expect(abs(regions.rgbWaveform.maxX - regions.picture.maxX) < 0.001)
    #expect(abs(regions.rgbParade.minX - regions.vectorscope.minX) < 0.001)
    #expect(abs(regions.picture.minY - (-0.44)) < 0.001)
}

@Test
func scopeColorMathRec709LumaWhiteIsOne() {
    let y = ScopeColorMath.luma709(r: 1, g: 1, b: 1)
    #expect(abs(y - 1) < 0.001)
}

@Test
func scopeIntensityScalePeakWhiteMapsTo100IRE() {
    #expect(ScopeIntensityScale.ireForSignalValue(1) == 100)
    #expect(ScopeIntensityScale.ireForSignalValue(0) == 0)
    #expect(abs(ScopeIntensityScale.displayFractionFromSignalValue(1) - 20.0 / 140.0) < 0.001)
    #expect(abs(ScopeIntensityScale.displayFractionFromSignalValue(0) - 120.0 / 140.0) < 0.001)
}

@Test
func scopeIntensityScaleSpansIREMinus20To120() {
    #expect(ScopeIntensityScale.ireTickValues.first == 120)
    #expect(ScopeIntensityScale.ireTickValues.last == -20)
    #expect(ScopeIntensityScale.ireTickValues.count == 8)
    #expect(abs(ScopeIntensityScale.displayFractionFromTop(ire: 120)) < 0.001)
    #expect(abs(ScopeIntensityScale.displayFractionFromTop(ire: -20) - 1) < 0.001)
    #expect(abs(ScopeIntensityScale.displayFractionFromTop(ire: 100) - 20.0 / 140.0) < 0.001)
    #expect(abs(ScopeIntensityScale.displayFractionFromTop(ire: 0) - 120.0 / 140.0) < 0.001)
}

@Test
func scopeColorMathBlueSkyPlotsRightOnResolveVectorscope() {
    let chroma = ScopeColorMath.vectorscopeDisplayCbCr(r: 0.15, g: 0.45, b: 0.92)
    let cbBin = ScopeColorMath.chromaBin(chroma.cb)
    let row = ScopeColorMath.vectorscopeDisplayRow(cr: chroma.cr)
    // Resolve: +Cb right (blue/cyan side), negative Cr slightly below center.
    #expect(cbBin > 128)
    #expect(row < 128)
}

@Test
func scopeColorMathPureRedPlotsUpperLeftOnResolveVectorscope() {
    let chroma = ScopeColorMath.vectorscopeDisplayCbCr(r: 1, g: 0, b: 0)
    let cbBin = ScopeColorMath.chromaBin(chroma.cb)
    let row = ScopeColorMath.vectorscopeDisplayRow(cr: chroma.cr)
    #expect(cbBin < 128)
    #expect(row > 200)
}

@Test
func scopeColorMathGreenAndMagentaMatchResolveTargets() {
    let green = ScopeColorMath.vectorscopeDisplayAngle(r: 0, g: 1, b: 0)
    let magenta = ScopeColorMath.vectorscopeDisplayAngle(r: 1, g: 0, b: 1)
    // Green → lower-left (~7:30); magenta → upper-right (~1:30).
    #expect(green < -2.0)
    #expect(green > -2.7)
    #expect(magenta > 0.6)
    #expect(magenta < 1.2)
    let greenTarget = ScopeColorMath.vectorscopeTargetAngles[2]
    let magentaTarget = ScopeColorMath.vectorscopeTargetAngles[5]
    #expect(angularDistance(green, greenTarget) < 0.45)
    #expect(angularDistance(magenta, magentaTarget) < 0.45)
}

private func angularDistance(_ a: Float, _ b: Float) -> Float {
    var d = abs(a - b).truncatingRemainder(dividingBy: 2 * Float.pi)
    if d > Float.pi { d = 2 * Float.pi - d }
    return d
}

@Test
func scopeColorMathRec709GrayChromaNearZero() {
    let y = ScopeColorMath.luma709(r: 0.5, g: 0.5, b: 0.5)
    let c = ScopeColorMath.ycbcr709(r: 0.5, g: 0.5, b: 0.5)
    #expect(abs(y - 0.5) < 0.01)
    #expect(abs(c.cb) < 0.01)
    #expect(abs(c.cr) < 0.01)
}

@Test
func multiviewSlotLayoutMapsQuadrantMidpoints() {
    let size = CGSize(width: 800, height: 600)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 100, y: 100), in: size) == 1)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 700, y: 100), in: size) == 2)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 100, y: 500), in: size) == 3)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 700, y: 500), in: size) == 4)
}

@Test
func multiviewSlotLayoutQuadrantFramesTileViewport() {
    let size = CGSize(width: 1000, height: 800)
    let split = GridSplit.equal(columns: 2, rows: 2)
    let q1 = MultiviewSlotLayout.cellFrame(slot: 1, columns: 2, rows: 2, split: split, in: size)
    let q2 = MultiviewSlotLayout.cellFrame(slot: 2, columns: 2, rows: 2, split: split, in: size)
    let q3 = MultiviewSlotLayout.cellFrame(slot: 3, columns: 2, rows: 2, split: split, in: size)
    let q4 = MultiviewSlotLayout.cellFrame(slot: 4, columns: 2, rows: 2, split: split, in: size)
    #expect(q1 == CGRect(x: 0, y: 0, width: 500, height: 400))
    #expect(q2 == CGRect(x: 500, y: 0, width: 500, height: 400))
    #expect(q3 == CGRect(x: 0, y: 400, width: 500, height: 400))
    #expect(q4 == CGRect(x: 500, y: 400, width: 500, height: 400))
}

@Test
func gridLayoutClampsToMaxSlots() {
    let grid = GridLayout(columns: 4, rows: 4)
    #expect(grid.slotCount == 16)
    #expect(GridLayout.isValid(columns: 4, rows: 4))
    #expect(!GridLayout.isValid(columns: 5, rows: 5))
    let clamped = GridLayout(columns: 5, rows: 5)
    #expect(clamped.rows <= 3)
    #expect(clamped.slotCount <= 16)
}

@Test
func gridLayout3x2SlotNumbering() {
    let size = CGSize(width: 900, height: 600)
    let split = GridSplit.equal(columns: 3, rows: 2)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 50, y: 50), columns: 3, rows: 2, split: split, in: size) == 1)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 450, y: 50), columns: 3, rows: 2, split: split, in: size) == 2)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 850, y: 50), columns: 3, rows: 2, split: split, in: size) == 3)
    #expect(MultiviewSlotLayout.slotForPoint(CGPoint(x: 50, y: 550), columns: 3, rows: 2, split: split, in: size) == 4)
}

@Test
func configLoaderEffectiveGridDefaults2x2() {
    let grid = ConfigLoader.effectiveGridLayout(config: nil)
    #expect(grid.columns == 2)
    #expect(grid.rows == 2)
}

@Test
func feedSignalPolicyNoSourceWhenUnassigned() {
    let now = Date()
    #expect(
        FeedSignalPolicy.status(
            assignment: nil,
            hasProvider: false,
            lastFrameAt: nil,
            lastRestartAt: nil,
            now: now
        ) == .noSource
    )
}

@Test
func feedSignalPolicyLiveWhenRecentFrame() {
    let now = Date()
    let last = now.addingTimeInterval(-0.5)
    #expect(
        FeedSignalPolicy.status(
            assignment: .ndi(name: "HOST (Stream)"),
            hasProvider: true,
            lastFrameAt: last,
            lastRestartAt: now,
            now: now
        ) == .live
    )
}

@Test
func feedSignalPolicyGraceWhileConnecting() {
    let now = Date()
    let restart = now.addingTimeInterval(-0.5)
    #expect(
        FeedSignalPolicy.status(
            assignment: .ndi(name: "HOST (Stream)"),
            hasProvider: true,
            lastFrameAt: nil,
            lastRestartAt: restart,
            now: now
        ) == .live
    )
}

@Test
func feedSignalPolicyNoSignalWhenStale() {
    let now = Date()
    let last = now.addingTimeInterval(-3.0)
    #expect(
        FeedSignalPolicy.status(
            assignment: .sdi(index: 0),
            hasProvider: true,
            lastFrameAt: last,
            lastRestartAt: now.addingTimeInterval(-5.0),
            now: now
        ) == .noSignal
    )
}

@Test
func feedSignalPolicyLiveWhenDisplayableTexturePresentDespiteStaleClock() {
    let now = Date()
    let last = now.addingTimeInterval(-5.0)
    #expect(
        FeedSignalPolicy.status(
            assignment: .ndi(name: "HOST (Stream)"),
            hasProvider: true,
            lastFrameAt: last,
            lastRestartAt: now.addingTimeInterval(-10.0),
            hasDisplayableTexture: true,
            now: now
        ) == .live
    )
}

@Test
func configLoaderOneUpScopeMonitorDefaultsOff() {
    #expect(ConfigLoader.effectiveOneUpScopeMonitor(config: nil) == false)
    #expect(ConfigLoader.effectiveOneUpScopeMonitor(config: .empty) == false)
}

@Test
func configLoaderPictureMonitoringDefaults() {
    let m = ConfigLoader.effectivePictureMonitoring(config: nil)
    #expect(m == .defaults)
    #expect(m.focusPeakingEnabled == false)
    #expect(m.zebraLevel == 0.9)
    #expect(m.focusPeakingColor == .green)
}

@Test
func configLoaderPictureMonitoringClampsSensitivityAndZebra() {
    var cfg = AppConfig.empty
    cfg.focusPeakingSensitivity = 0.01
    cfg.zebraLevel = 1.5
    let m = ConfigLoader.effectivePictureMonitoring(config: cfg)
    #expect(m.focusPeakingSensitivity == PictureMonitoringSettings.sensitivityRange.lowerBound)
    #expect(m.zebraLevel == PictureMonitoringSettings.zebraLevelRange.upperBound)
}

@Test
func focusPeakingColorRoundTripsThroughConfig() {
    var cfg = AppConfig.empty
    cfg.focusPeakingColor = FocusPeakingColor.yellow.rawValue
    let m = ConfigLoader.effectivePictureMonitoring(config: cfg)
    #expect(m.focusPeakingColor == .yellow)
}

@Test
@MainActor
func professionalScanDetailHidesTechnicalBonjourDump() {
    let technical = "NDI Finder: no sources. Bonjour `_ndi._tcp`: none. Start a sender on the LAN or check Local Network permission."
    let detail = SourcesDiscoveryService.professionalScanDetail(ndiCount: 0, technicalStatus: technical)
    #expect(detail?.contains("Bonjour") == false)
    #expect(detail?.contains("Local Network") == true)
}

@Test
@MainActor
func professionalScanDetailNilWhenSourcesFound() {
    let detail = SourcesDiscoveryService.professionalScanDetail(
        ndiCount: 2,
        technicalStatus: "NDI Finder (SDK): 2 source(s)."
    )
    #expect(detail == nil)
}

