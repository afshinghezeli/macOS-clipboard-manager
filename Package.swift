// swift-tools-version: 6.1
import PackageDescription

// Only upcoming features that Swift 6.1 knows about. A compiler silently ignores names it doesn't
// recognize, so enabling a newer one would make local and CI builds behave differently.
let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "Spindle",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Spindle", targets: ["Spindle"])
    ],
    dependencies: [
        // Pinned exactly: upgrades are deliberate, and must keep building with Swift 6.1 (ADR 0003).
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
        // Updates for builds distributed outside the Mac App Store (ADR 0002).
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Spindle",
            dependencies: [
                "SpindleCore", "SpindleStorage", "SpindleSystem", "SpindleUI",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: swiftSettings,
            // Sparkle.framework is embedded in Spindle.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(
            name: "SpindleCore",
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SpindleStorage",
            dependencies: [
                "SpindleCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SpindleSystem",
            dependencies: ["SpindleCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "SpindleUI",
            dependencies: ["SpindleCore", "SpindleStorage", "SpindleSystem"],
            resources: [.process("Resources")],
            swiftSettings: swiftSettings
        ),
        // `make bench`: timings against generated histories (docs/performance.md).
        .executableTarget(
            name: "SpindleBench",
            dependencies: ["SpindleCore", "SpindleStorage"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpindleCoreTests",
            dependencies: ["SpindleCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpindleStorageTests",
            dependencies: ["SpindleCore", "SpindleStorage"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpindleSystemTests",
            dependencies: ["SpindleCore", "SpindleSystem"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "SpindleUITests",
            dependencies: ["SpindleCore", "SpindleStorage", "SpindleSystem", "SpindleUI"],
            swiftSettings: swiftSettings
        ),
    ]
)
