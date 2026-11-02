// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FileTools",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FileTools", targets: ["FileTools"]),
        .library(name: "LogReader", targets: ["LogReader"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
        // The one git launch point: a checkout's fsmonitor and hooks never run, prompts never hang.
        .package(path: "../swift-git-kit"),
    ],
    targets: [
        // macOS-only: DirectoryEventStream wraps FSEvents/CoreServices.
        .target(
            name: "FileTools",
            dependencies: [
                .product(name: "FoundationExtensions", package: "swift-foundation-extensions"),
                .product(name: "ProcessRunner", package: "swift-foundation-extensions"),
                .product(name: "GitKit", package: "swift-git-kit"),
            ], path: "Sources/FileTools",
            swiftSettings: [.swiftLanguageMode(.v6)]),
        // Log files of any size read as entries: every popular format's header, an index, filters.
        .target(name: "LogReader", dependencies: ["FileTools"], path: "Sources/LogReader", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "FileToolsTests", dependencies: ["FileTools"], path: "Tests/FileToolsTests"),
        .testTarget(
            name: "LogReaderTests", dependencies: ["LogReader"], path: "Tests/LogReaderTests", resources: [.copy("Fixtures")]),
    ]
)
