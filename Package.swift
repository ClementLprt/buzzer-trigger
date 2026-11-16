// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "BuzzerTrigger",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "BuzzerTrigger", path: "Sources/BuzzerTrigger")
    ]
)
