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
func displayUploadGeometryFourUpCellIsHalfViewport() {
    let cell = DisplayUploadGeometry.cellPixelSize(
        slot: 2,
        layout: .fourUp,
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

