// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileTools", targets: ["FileTools"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
        .package(path: "../swift-process-runner"),
    ],
    targets: [
        // macOS-only: DirectoryEventStream wraps FSEvents/CoreServices.
        .target(name: "FileTools", dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions"), .product(name: "ProcessRunner", package: "swift-process-runner")], path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "FileToolsTests", dependencies: ["FileTools"], path: "Tests"),
    ]
)
