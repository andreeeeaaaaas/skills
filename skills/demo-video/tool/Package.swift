// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "demo-video",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "demo-video", path: "Sources/demo-video")
    ]
)
