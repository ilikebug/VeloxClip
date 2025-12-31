// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VeloxClip",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VeloxClip", targets: ["VeloxClip"])
    ],
    dependencies: [
        // Add dependencies here, e.g., GRDB, KeyboardShortcuts, etc.
    ],
    targets: [
        .executableTarget(
            name: "VeloxClip",
            dependencies: [],
            path: "VeloxClip"
        )
    ]
)
