// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacESP32Console",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacESP32Console", targets: ["MacESP32Console"])
    ],
    targets: [
        .executableTarget(
            name: "MacESP32Console",
            path: "Sources/MacESP32Console"
        )
    ]
)
