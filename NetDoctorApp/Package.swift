// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NetDoctor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NetDoctor",
            path: "Sources/NetDoctor"
        )
    ]
)
