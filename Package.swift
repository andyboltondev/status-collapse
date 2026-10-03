// swift-tools-version:6.4
import PackageDescription

let package = Package(
    name: "StatusCollapse",
    platforms: [.macOS(.v27)],
    targets: [
        .executableTarget(name: "StatusCollapse", path: "Sources/StatusCollapse"),
        .testTarget(name: "StatusCollapseTests", dependencies: ["StatusCollapse"], path: "Tests/StatusCollapseTests"),
    ]
)
