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
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "VeloxClip",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            path: "VeloxClip"
        )
    ]
)
