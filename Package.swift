// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileTools",
    platforms: [
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "FileTools", targets: ["FileTools"]),
    ],
    targets: [
        // macOS-only: DirectoryEventStream wraps FSEvents/CoreServices.
        .target(name: "FileTools", path: "Sources",
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .testTarget(name: "FileToolsTests", dependencies: ["FileTools"], path: "Tests"),
    ]
)
