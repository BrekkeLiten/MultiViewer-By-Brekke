import Foundation

/// Loads NDI Dynamic Library (`libndi.3.dylib`) at runtime; no SDK headers at compile time.
enum NDILibraryLoader {
    enum LoadError: Error {
        case libraryNotFound
        case missingSymbol(String)
        case unsupportedCPU
    }

    /// Function pointers resolved from libndi once per process (`NDIlib_initialize` succeeds once).
    struct API {
        let recvCreateV3: (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)!
        let recvDestroy: (@convention(c) (UnsafeMutableRawPointer?) -> Void)!
        let recvCaptureV2: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32) -> Int32)!
        let recvFreeVideoV2: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)!
        let recvFreeMetadata: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)?

        /// Optional: present in full redistributables; absent in some stubs.
        let findCreateV2: (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)?
        let findDestroy: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?
        let findWaitForSources: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> CBool)?
        let findGetCurrentSources: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeRawPointer?)?
    }

    private static let lock = NSLock()
    /// Guarded exclusively by `lock`; `nonisolated(unsafe)` satisfies Swift 6 global-state checking.
    private nonisolated(unsafe) static var cached: API?
    private nonisolated(unsafe) static var handle: UnsafeMutableRawPointer?

    static func sharedAPI() throws -> API {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        let h = try openNDIDylib()

        func sym<T>(_ name: String) throws -> T {
            guard let raw = dlsym(h, name) else { throw LoadError.missingSymbol(name) }
            return unsafeBitCast(raw, to: T.self)
        }

        func symOptional<T>(_ name: String) -> T? {
            guard let raw = dlsym(h, name) else { return nil }
            return unsafeBitCast(raw, to: T.self)
        }

        let initialize: @convention(c) () -> CBool = try sym("NDIlib_initialize")
        let recvCreateV3: @convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer? = try sym("NDIlib_recv_create_v3")
        let recvDestroy: @convention(c) (UnsafeMutableRawPointer?) -> Void = try sym("NDIlib_recv_destroy")
        let recvCaptureV2: @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, UInt32) -> Int32 = try sym("NDIlib_recv_capture_v2")
        let recvFreeVideoV2: @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void = try sym("NDIlib_recv_free_video_v2")
        let recvFreeMetadata: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?) -> Void)? =
            symOptional("NDIlib_recv_free_metadata")

        let findCreateV2: (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)? =
            symOptional("NDIlib_find_create_v2")
        let findDestroy: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? =
            symOptional("NDIlib_find_destroy")
        let findWaitForSources: (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> CBool)? =
            symOptional("NDIlib_find_wait_for_sources")
        let findGetCurrentSources: (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeRawPointer?)? =
            symOptional("NDIlib_find_get_current_sources")

        guard initialize() else {
            dlclose(h)
            throw LoadError.unsupportedCPU
        }

        handle = h

        let findBundle: (
            (@convention(c) (UnsafeRawPointer?) -> UnsafeMutableRawPointer?)?,
            (@convention(c) (UnsafeMutableRawPointer?) -> Void)?,
            (@convention(c) (UnsafeMutableRawPointer?, UInt32) -> CBool)?,
            (@convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt32>?) -> UnsafeRawPointer?)?
        )
        if let findCreateV2, let findDestroy, let findWaitForSources, let findGetCurrentSources {
            findBundle = (findCreateV2, findDestroy, findWaitForSources, findGetCurrentSources)
        } else {
            findBundle = (nil, nil, nil, nil)
        }

        let api = API(
            recvCreateV3: recvCreateV3,
            recvDestroy: recvDestroy,
            recvCaptureV2: recvCaptureV2,
            recvFreeVideoV2: recvFreeVideoV2,
            recvFreeMetadata: recvFreeMetadata,
            findCreateV2: findBundle.0,
            findDestroy: findBundle.1,
            findWaitForSources: findBundle.2,
            findGetCurrentSources: findBundle.3
        )
        cached = api
        return api
    }

    /// NDI Tools for macOS often ship the runtime as `libndi.dylib` inside `.app` bundles, not `libndi.3.dylib` under `/Library/NDI`.
    private static func ndiToolsBundledDylibPaths() -> [String] {
        let routerNested =
            "Contents/Frameworks/NTFramework.framework/Versions/A/Frameworks/libndi.dylib"
        let toolsFolders = ["/Applications/NDI tools", "/Applications/NDI Tools"]
        var paths: [String] = [
            "/Applications/NDI Scan Converter.app/Contents/Frameworks/libndi.dylib",
            "/Applications/NDI Scan Converter.app/Contents/Frameworks/libndi.3.dylib",
            "/Applications/NDI Router.app/\(routerNested)",
            "/Applications/NDI Router.app/Contents/Frameworks/libndi.3.dylib",
        ]
        for root in toolsFolders {
            paths.append("\(root)/NDI Launcher.app/Contents/Frameworks/libndi.dylib")
            paths.append("\(root)/NDI Launcher.app/Contents/Frameworks/libndi.3.dylib")
            paths.append("\(root)/NDI Scan Converter.app/Contents/Frameworks/libndi.dylib")
            paths.append("\(root)/NDI Scan Converter.app/Contents/Frameworks/libndi.3.dylib")
            paths.append("\(root)/NDI Router.app/\(routerNested)")
        }
        return paths
    }

    private static func packagedAppFrameworkDylibPaths() -> [String] {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return [] }
        let bundleFrameworks = Bundle.main.bundleURL.appendingPathComponent("Contents/Frameworks").path
        return [
            "\(bundleFrameworks)/libndi.3.dylib",
            "\(bundleFrameworks)/libndi.dylib",
            "\(bundleFrameworks)/libndi.4.dylib",
        ]
    }

    private static func openNDIDylib() throws -> UnsafeMutableRawPointer {
        var paths: [String] = []

        if let env = ProcessInfo.processInfo.environment["NDI_RUNTIME_DIR_V3"], !env.isEmpty {
            paths.append("\(env)/libndi.3.dylib")
            paths.append("\(env)/libndi.dylib")
        }
        if let env = ProcessInfo.processInfo.environment["NDI_SDK_DIR"], !env.isEmpty {
            paths.append("\(env)/lib/macOS/libndi.3.dylib")
            paths.append("\(env)/lib/macOS/libndi.dylib")
        }

        // Prefer runtime shipped inside the .app (NDI SDK redistribution) before system installs.
        paths.append(contentsOf: packagedAppFrameworkDylibPaths())

        paths.append(contentsOf: ndiToolsBundledDylibPaths())

        let home = FileManager.default.homeDirectoryForCurrentUser.path

        paths.append(contentsOf: [
            "/Library/NDI/libndi.3.dylib",
            "/Library/NDI/libndi.dylib",
            // Some installs lay files under NewTek; HX_Driver is FFmpeg plugins only — core lib lives next to `/Library/NDI` install.
            "/Library/Application Support/NewTek/NDI/libndi.3.dylib",
            "/Library/Application Support/NewTek/NDI/libndi.dylib",
            "/Library/Application Support/NDI/libndi.3.dylib",
            "/Library/Application Support/NDI/libndi.dylib",
            "\(home)/Library/Application Support/NDI/libndi.3.dylib",
            "\(home)/Library/Application Support/NDI/libndi.dylib",
            "/opt/homebrew/lib/libndi.3.dylib",
            "/opt/homebrew/lib/libndi.dylib",
            "/usr/local/lib/libndi.3.dylib",
            "/usr/local/lib/libndi.dylib",
            "libndi.3.dylib",
            "libndi.dylib",
        ])

        for p in paths {
            if let h = dlopen(p, RTLD_NOW) {
                return h
            }
        }
        throw LoadError.libraryNotFound
    }
}
