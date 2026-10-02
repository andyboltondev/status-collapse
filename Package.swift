// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "StatusCollapse",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "StatusCollapse", path: "Sources/StatusCollapse")
    ]
)
