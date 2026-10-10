//
//  LocalHistoryDiskTests.swift
//  FileToolsTests
//
//  Created by David Sherlock on 10/10/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class LocalHistoryDiskTests: XCTestCase {
    private var base: URL!
    private var project: URL!
    private var history: LocalHistory!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("local-history-disk-\(UUID().uuidString)", isDirectory: true)
        project = base.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        history = LocalHistory(root: base.appendingPathComponent("history"), maxEntries: 10, mergeWindow: 10, maxFileSize: 64)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    private func file(_ name: String, _ contents: String) throws -> URL {
        try file(name, Data(contents.utf8))
    }
    private func file(_ name: String, _ data: Data) throws -> URL {
        let url = project.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }
    private func texts(_ url: URL) -> [String] {
        history.entries(for: url).map { String(decoding: history.data(of: $0, for: url)!, as: UTF8.self) }
    }

    func testAChangedTextFileIsKeptUnderTheGivenSource() throws {
        let a = try file("a.txt", "agent wrote this\n")
        let outcome = history.recordFromDisk([a], source: .agent, at: t0)
        XCTAssertEqual(outcome.recorded, [a])
        XCTAssertEqual(history.entries(for: a).map(\.kind), [.agent])
        XCTAssertEqual(texts(a), ["agent wrote this\n"])
    }

    func testASecondChangeIsKeptAgainAndTheSameBytesAreNot() throws {
        let a = try file("a.txt", "one\n")
        history.recordFromDisk([a], source: .changedOnDisk, at: t0)
        try Data("two\n".utf8).write(to: a)
        XCTAssertEqual(history.recordFromDisk([a], source: .changedOnDisk, at: t0 + 60).recorded, [a])
        let unchanged = history.recordFromDisk([a], source: .changedOnDisk, at: t0 + 120)
        XCTAssertEqual(unchanged.recorded, [])
        XCTAssertEqual(unchanged.skipped, 1)
        XCTAssertEqual(texts(a), ["one\n", "two\n"])
    }

    func testTheHostsOwnSaveComingBackFromDiskIsKeptOnce() throws {
        let a = try file("a.txt", "saved\n")
        try history.record(Data("saved\n".utf8), for: a, source: .saved, at: t0)
        XCTAssertEqual(history.recordFromDisk([a], source: .agent, at: t0 + 1).recorded, [])
        XCTAssertEqual(history.entries(for: a).map(\.kind), [.saved])
    }

    func testDirectoriesBinariesOversizedAndMissingFilesAreLeftOut() throws {
        let dir = project.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let binary = try file("image.bin", Data([0x89, 0x50, 0x00, 0x01, 0x02]))
        let big = try file("big.txt", String(repeating: "x", count: 65))
        let missing = project.appendingPathComponent("gone.txt")
        var asked: [URL] = []
        let outcome = history.recordFromDisk([dir, binary, big, missing], source: .agent, at: t0) {
            asked = $0; return [:]
        }
        XCTAssertEqual(asked, [binary], "only a regular file within the ceiling is opened; the sniff then refuses the binary")
        XCTAssertEqual(outcome.recorded, [])
        XCTAssertEqual(outcome.skipped, 4)
        for url in [dir, binary, big, missing] { XCTAssertEqual(history.entries(for: url), [], url.lastPathComponent) }
    }

    func testAFIFOIsNeverOpened() throws {
        let fifo = project.appendingPathComponent("pipe.txt")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)
        var asked: [URL] = []
        let outcome = history.recordFromDisk([fifo], source: .agent, at: t0) {
            asked = $0; return [:]
        }
        XCTAssertEqual(asked, [], "a pipe is not a first sighting")
        XCTAssertEqual(outcome.recorded, [])
        XCTAssertEqual(outcome.skipped, 1)
    }

    func testAFileAtTheCeilingIsKept() throws {
        let edge = try file("edge.txt", String(repeating: "x", count: 64))
        XCTAssertEqual(history.recordFromDisk([edge], source: .agent, at: t0).recorded, [edge])
    }

    func testALinkIsReadThroughToItsTarget() throws {
        let target = try file("target.txt", "through the link\n")
        let link = project.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertEqual(history.recordFromDisk([link], source: .agent, at: t0).recorded, [link])
        XCTAssertEqual(texts(link), ["through the link\n"])
    }

    func testAtMostTheLimitIsExaminedInPathOrder() throws {
        let urls = try (0..<10).map { try file(String(format: "f%02d.txt", $0), "v\($0)\n") }
        var asked: [URL] = []
        let outcome = history.recordFromDisk(urls.reversed(), source: .agent, limit: 4, at: t0) {
            asked = $0; return [:]
        }
        XCTAssertEqual(outcome.recorded, Array(urls.prefix(4)))
        XCTAssertEqual(outcome.unexamined, 6)
        XCTAssertEqual(asked, Array(urls.prefix(4)), "only examined files are first sightings")
        for url in urls.dropFirst(4) { XCTAssertEqual(history.entries(for: url), [], url.lastPathComponent) }
    }

    func testTheFirstSightingKeepsThePreviousContentFirst() throws {
        let a = try file("a.txt", "after\n")
        let outcome = history.recordFromDisk([a], source: .agent, at: t0) { files in
            Dictionary(uniqueKeysWithValues: files.map { ($0, Data("before\n".utf8)) })
        }
        XCTAssertEqual(outcome.previousKept, [a])
        XCTAssertEqual(history.entries(for: a).map(\.kind), [.previous, .agent])
        XCTAssertEqual(texts(a), ["before\n", "after\n"])
        let times = history.entries(for: a).map(\.timestamp)
        XCTAssertTrue(times.count == 2 && times[0] < times[1], "the before sorts before the change: \(times)")
    }

    func testPreviousIsAskedOnlyForFilesWithNoVersionsAndOnlyOnce() throws {
        let known = try file("known.txt", "new\n")
        let fresh = try file("fresh.txt", "new\n")
        try history.record(Data("old\n".utf8), for: known, source: .saved, at: t0 - 60)
        var calls: [[URL]] = []
        history.recordFromDisk([known, fresh], source: .agent, at: t0) {
            calls.append($0); return [:]
        }
        XCTAssertEqual(calls, [[fresh]])
        XCTAssertEqual(history.entries(for: known).map(\.kind), [.saved, .agent], "a file with versions gets no before")
        var again = 0
        history.recordFromDisk([known, fresh], source: .agent, at: t0 + 60) { _ in
            again += 1; return [:]
        }
        XCTAssertEqual(again, 0, "nothing is a first sighting the second time")
    }

    func testAPreviousEqualToTheNewBytesBinaryOrOversizedIsNotKept() throws {
        let same = try file("same.txt", "same\n")
        let bin = try file("bin.txt", "text now\n")
        let big = try file("big.txt", "small now\n")
        history.recordFromDisk([same, bin, big], source: .agent, at: t0) { _ in
            [same: Data("same\n".utf8), bin: Data([0, 1, 2]), big: Data(repeating: 65, count: 65)]
        }
        for url in [same, bin, big] { XCTAssertEqual(history.entries(for: url).map(\.kind), [.agent], url.lastPathComponent) }
    }

    func testAnUnknownSourceInTheIndexStillReads() throws {
        let a = try file("a.txt", "x\n")
        try history.record(Data("x\n".utf8), for: a, source: .saved, at: t0)
        let indexURL = history.folder(for: a).appendingPathComponent("entries.json")
        let edited = try String(contentsOf: indexURL, encoding: .utf8).replacingOccurrences(of: "File Saved", with: "Restored")
        try edited.write(to: indexURL, atomically: true, encoding: .utf8)
        let entries = history.entries(for: a)
        XCTAssertEqual(entries.map(\.source), ["Restored"])
        XCTAssertNil(entries.first?.kind)
    }

    func testTheStoredRawValuesNeverChange() {
        XCTAssertEqual(
            LocalHistorySource.allCases.map(\.rawValue), ["File Saved", "Overwritten on disk", "Agent", "Changed on disk", "Before change"])
    }
}
