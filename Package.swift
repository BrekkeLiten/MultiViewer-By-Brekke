// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MetalMultiviewer",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "DeckLinkBridge",
            path: "Sources/DeckLinkBridge",
            sources: [
                "DeckLinkBridge.mm",
                "decklink-sdk/DeckLinkAPIDispatch.cpp",
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("decklink-sdk"),
                .unsafeFlags(["-std=c++17"], .when(platforms: [.macOS])),
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "MetalMultiviewer",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                "DeckLinkBridge",
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .testTarget(
            name: "MetalMultiviewerTests",
            dependencies: [
                "MetalMultiviewer",
                .product(name: "Testing", package: "swift-testing"),
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
