// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileTools", targets: ["FileTools"]),
    ],
    targets: [
        // macOS-only: DirectoryEventStream wraps FSEvents/CoreServices.
        .target(name: "FileTools", path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "FileToolsTests", dependencies: ["FileTools"], path: "Tests"),
    ]
)
