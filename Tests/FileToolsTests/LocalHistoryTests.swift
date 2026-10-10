//
//  LocalHistoryTests.swift
//  FileToolsTests
//
//  Created by David Sherlock on 9/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class LocalHistoryTests: XCTestCase {
    private var root: URL!
    private var history: LocalHistory!
    private let file = URL(fileURLWithPath: "/tmp/project/src/main.swift")
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("local-history-\(UUID().uuidString)", isDirectory: true)
        history = LocalHistory(root: root, maxEntries: 3, mergeWindow: 10, maxFileSize: 64)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    func testSavesApartBecomeSeparateVersionsOldestFirst() throws {
        try history.record(Data("one".utf8), for: file, at: t0)
        try history.record(Data("two".utf8), for: file, at: t0 + 60)
        let entries = history.entries(for: file)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map { history.data(of: $0, for: file).map { String(decoding: $0, as: UTF8.self) } }, ["one", "two"])
        XCTAssertEqual(entries.map(\.timestamp), [t0, t0 + 60])
        XCTAssertEqual(entries.map(\.kind), [.saved, .saved])
        XCTAssertTrue(entries.allSatisfy { $0.id.hasSuffix(".swift") })
    }

    func testSavesWithinTheMergeWindowReplaceTheLastVersion() throws {
        try history.record(Data("one".utf8), for: file, at: t0)
        try history.record(Data("two".utf8), for: file, at: t0 + 3)
        let after = try XCTUnwrap(history.record(Data("three".utf8), for: file, at: t0 + 9))
        let entries = history.entries(for: file)
        XCTAssertEqual(entries.count, 1, "three saves in nine seconds are one version")
        XCTAssertEqual(entries.first, after)
        XCTAssertEqual(history.data(of: after, for: file), Data("three".utf8))
        let blobs = try FileManager.default.contentsOfDirectory(atPath: history.folder(for: file).path).filter { $0 != "entries.json" }
        XCTAssertEqual(blobs, [after.id], "the replaced versions' blobs are gone")
    }

    func testADifferentSourceDoesNotMerge() throws {
        try history.record(Data("one".utf8), for: file, at: t0)
        try history.record(Data("two".utf8), for: file, source: .agent, at: t0 + 3)
        XCTAssertEqual(history.entries(for: file).map(\.source), ["File Saved", "Agent"])
    }

    func testAnUnchangedSaveRecordsNothing() throws {
        let first = try XCTUnwrap(history.record(Data("same".utf8), for: file, at: t0))
        XCTAssertNil(try history.record(Data("same".utf8), for: file, at: t0 + 60))
        XCTAssertEqual(history.entries(for: file), [first])
    }

    func testOnlyTheNewestVersionsAreKept() throws {
        for i in 0..<5 { try history.record(Data("v\(i)".utf8), for: file, at: t0 + Double(i) * 60) }
        let entries = history.entries(for: file)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map { String(decoding: history.data(of: $0, for: file)!, as: UTF8.self) }, ["v2", "v3", "v4"])
        let blobs = try FileManager.default.contentsOfDirectory(atPath: history.folder(for: file).path).filter { $0 != "entries.json" }
        XCTAssertEqual(Set(blobs), Set(entries.map(\.id)), "trimmed versions' blobs are deleted")
    }

    func testAFileOverTheSizeCeilingIsNotKept() throws {
        XCTAssertNil(try history.record(Data(repeating: 65, count: 65), for: file, at: t0))
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.folder(for: file).path))
        XCTAssertNotNil(try history.record(Data(repeating: 65, count: 64), for: file, at: t0))
    }

    func testTheStoreIsBoundedAcrossFilesOldestFirst() throws {
        let other = URL(fileURLWithPath: "/tmp/project/src/other.swift")
        history.maxTotalSize = 10
        try history.record(Data("aaaa".utf8), for: file, at: t0)
        try history.record(Data("bbbb".utf8), for: other, at: t0 + 60)
        try history.record(Data("cccc".utf8), for: file, at: t0 + 120)
        XCTAssertEqual(history.trimToTotalSize(), 1, "twelve bytes over a ten-byte ceiling: the oldest version goes")
        XCTAssertEqual(history.entries(for: file).map { String(decoding: history.data(of: $0, for: file)!, as: UTF8.self) }, ["cccc"])
        XCTAssertEqual(history.entries(for: other).count, 1, "the newer file's version stays")
        let blobs = try FileManager.default.contentsOfDirectory(atPath: history.folder(for: file).path).filter { $0 != "entries.json" }
        XCTAssertEqual(blobs.count, 1, "the dropped blob is gone")
        XCTAssertEqual(history.trimToTotalSize(), 0, "within the ceiling nothing moves")
    }

    func testAMoveCarriesTheVersionsToTheNewPath() throws {
        let renamed = URL(fileURLWithPath: "/tmp/project/src/renamed.swift")
        try history.record(Data("one".utf8), for: file, at: t0)
        try history.record(Data("two".utf8), for: file, at: t0 + 60)
        try history.record(Data("theirs".utf8), for: renamed, at: t0 + 30)
        try history.move(from: file, to: renamed)
        let entries = history.entries(for: renamed)
        XCTAssertEqual(entries.map { String(decoding: history.data(of: $0, for: renamed)!, as: UTF8.self) }, ["one", "theirs", "two"])
        XCTAssertEqual(history.entries(for: file), [], "nothing is left under the old path")
        XCTAssertFalse(FileManager.default.fileExists(atPath: history.folder(for: file).path))
    }

    func testFilesDoNotMixAndFoldersAreStable() throws {
        let other = URL(fileURLWithPath: "/tmp/project/src/other.swift")
        try history.record(Data("a".utf8), for: file, at: t0)
        try history.record(Data("b".utf8), for: other, at: t0)
        XCTAssertEqual(history.entries(for: file).count, 1)
        XCTAssertEqual(history.entries(for: other).count, 1)
        XCTAssertNotEqual(history.folder(for: file), history.folder(for: other))
        let again = LocalHistory(root: root)
        XCTAssertEqual(again.folder(for: file), history.folder(for: file), "the same path finds the same folder from a fresh instance")
        XCTAssertEqual(again.entries(for: file).count, 1)
        history.clear(for: file)
        XCTAssertEqual(history.entries(for: file), [])
        XCTAssertEqual(history.entries(for: other).count, 1)
    }
}
