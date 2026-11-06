// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetDiag",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NetDiag",
            path: "Sources/NetDiag",
            swiftSettings: [.swiftLanguageVersion(.v5)]
        )
    ]
)
