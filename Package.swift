// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIUsageMonitor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "AIUsageMonitor", path: "Sources/AIUsageMonitor")
    ]
)
