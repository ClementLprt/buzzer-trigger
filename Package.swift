// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "CueStation",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "CueStation", path: "Sources/CueStation")
    ]
)
