//
//  EngineCachesTests.swift
//  FileToolsTests
//
//  A game engine's cache folders, skipped only beside the entry that marks the engine's project,
//  by the rule itself, the listings and the event filter.
//
//  Created by David Sherlock on 10/26/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class EngineCachesTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("engine-caches-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func make(_ paths: [String], in folder: URL? = nil) throws {
        for path in paths {
            let url = (folder ?? root).appendingPathComponent(path)
            if path.hasSuffix("/") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("x".utf8).write(to: url)
            }
        }
    }

    func testEachEnginesCachesAreSkippedBesideItsMarkerOnly() {
        XCTAssertEqual(
            EngineCaches.skipped(among: ["Assets", "ProjectSettings", "Packages", "Library", "Temp", "obj", "Logs", "UserSettings"]),
            ["Library", "Temp", "obj"], "Unity: the logs and user settings stay")
        XCTAssertEqual(
            EngineCaches.skipped(among: ["Shooter.uproject", "Content", "Intermediate", "DerivedDataCache", "Saved", "Binaries"]),
            ["Intermediate", "DerivedDataCache"], "Unreal: Saved (the logs) and Binaries stay")
        XCTAssertEqual(EngineCaches.skipped(among: ["Inventory.uplugin", "Source", "Intermediate"]), ["Intermediate"], "an Unreal plugin")
        XCTAssertEqual(EngineCaches.skipped(among: ["project.godot", ".godot", ".import", "scenes"]), [".godot", ".import"], "Godot")
        XCTAssertEqual(
            EngineCaches.skipped(among: ["Library", "Temp", "obj", "Intermediate", ".godot", "Sources"]), [],
            "no marker, no skip: a Library in any other project stays")
        XCTAssertEqual(EngineCaches.skipped(among: ["ProjectSettings", "Library"]), [], "Unity needs Assets beside ProjectSettings")
    }

    func testAFolderOnDiskIsACacheOnlyBesideItsMarker() throws {
        try make(["Game/Assets/", "Game/ProjectSettings/", "Game/Library/", "Tools/Library/"])
        XCTAssertTrue(EngineCaches.isCache(root.appendingPathComponent("Game/Library")))
        XCTAssertFalse(EngineCaches.isCache(root.appendingPathComponent("Tools/Library")))
        XCTAssertFalse(EngineCaches.isCache(root.appendingPathComponent("Game/Assets")), "a name no rule skips is never listed for")
    }

    func testAListingThatSkipsTheNoiseSkipsAnEnginesCachesToo() throws {
        try make(["Assets/", "ProjectSettings/", "Library/", "Temp/", "Logs/", "obj"])
        let skipping = FastDirectoryListing.list(root, skipping: ["node_modules"]).map(\.url.lastPathComponent)
        XCTAssertEqual(Set(skipping), ["Assets", "ProjectSettings", "Logs", "obj"], "a FILE named obj is not the cache folder")
        let everything = FastDirectoryListing.list(root).map(\.url.lastPathComponent)
        XCTAssertTrue(everything.contains("Library"), "a listing that skips nothing shows everything")
        let tree = DirectoryChildren.sorted(in: root, skipping: ["node_modules"]).map(\.lastPathComponent)
        XCTAssertEqual(Set(tree), ["Assets", "ProjectSettings", "Logs", "obj"])
    }

    func testEventsInsideACacheAreDroppedAndTheSameNamesElsewhereKept() throws {
        try make(["unity/Assets/", "unity/ProjectSettings/", "unity/Library/Artifacts/", "plain/Library/"])
        let base = root.path + "/"
        let events = [
            base + "unity/Library/Artifacts/0a/1b2c", base + "unity/Library", base + "unity/Assets/Player.cs",
            base + "plain/Library/notes.md",
        ]
        XCTAssertEqual(
            EventPaths.relevant(events, root: base, skipping: [".git"]), [base + "unity/Assets/Player.cs", base + "plain/Library/notes.md"])
        XCTAssertEqual(EventPaths.relevant(events, root: base, skipping: []).count, 4, "an unfiltered tree hears everything")
    }
}
