//
//  RecentItemsTests.swift
//  FileToolsTests
//
//  Tests for `RecentItems`: newest first, no duplicates, capped, missing paths dropped on read,
//  and every read and write going to the store it was given.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `RecentItems`: newest first, no duplicates, capped, missing paths dropped on read,
/// and every read and write going to the store it was given.
final class RecentItemsTests: XCTestCase {
    private let suite = "RecentItemsTests-\(UUID().uuidString)"
    private var folder: URL!

    override func setUpWithError() throws {
        RecentItems.defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("recents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        RecentItems.defaults.removePersistentDomain(forName: suite)
        RecentItems.defaults = .standard
        try? FileManager.default.removeItem(at: folder)
    }

    /// A file that exists in the scratch folder.
    private func file(_ name: String) -> URL {
        let url = folder.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data())
        return url
    }

    func testFilesAreNewestFirstWithoutDuplicates() {
        let a = file("a.txt"), b = file("b.txt")
        RecentItems.addFile(a)
        RecentItems.addFile(b)
        RecentItems.addFile(a)
        XCTAssertEqual(RecentItems.files.map(\.path), [a.path, b.path])
    }

    func testFilesAreCappedAtFifteenAndFoldersAtFive() {
        let files = (0..<17).map { file("f\($0).txt") }
        files.forEach(RecentItems.addFile)
        XCTAssertEqual(RecentItems.files.map(\.path), files.reversed().prefix(15).map(\.path))
        let folders = (0..<7).map { i -> URL in
            let url = folder.appendingPathComponent("d\(i)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        folders.forEach(RecentItems.addFolder)
        XCTAssertEqual(RecentItems.folders.map(\.path), folders.reversed().prefix(5).map(\.path))
    }

    func testAPathThatNoLongerExistsIsDroppedOnRead() throws {
        let kept = file("kept.txt"), gone = file("gone.txt")
        RecentItems.addFile(kept)
        RecentItems.addFile(gone)
        try FileManager.default.removeItem(at: gone)
        XCTAssertEqual(RecentItems.files.map(\.path), [kept.path])
    }

    func testClearAllEmptiesBothLists() {
        RecentItems.addFile(file("a.txt"))
        RecentItems.addFolder(folder)
        RecentItems.clearAll()
        XCTAssertTrue(RecentItems.files.isEmpty)
        XCTAssertTrue(RecentItems.folders.isEmpty)
    }

    func testReadsAndWritesGoToTheGivenStoreAndNotTheStandardOne() throws {
        let store = try XCTUnwrap(UserDefaults(suiteName: suite))
        let standardBefore = UserDefaults.standard.object(forKey: "RecentFiles") as? [String]
        let a = file("a.txt")
        RecentItems.addFile(a)
        RecentItems.addFolder(folder)
        XCTAssertEqual(store.stringArray(forKey: "RecentFiles"), [a.path])
        XCTAssertEqual(store.stringArray(forKey: "RecentFolders"), [folder.path])
        XCTAssertEqual(UserDefaults.standard.object(forKey: "RecentFiles") as? [String], standardBefore)
        // Reads come from the given store too: a list written there by hand is what comes back.
        let b = file("b.txt")
        store.set([b.path], forKey: "RecentFiles")
        XCTAssertEqual(RecentItems.files.map(\.path), [b.path])
        RecentItems.clearAll()
        XCTAssertNil(store.object(forKey: "RecentFiles"))
        XCTAssertNil(store.object(forKey: "RecentFolders"))
    }
}
