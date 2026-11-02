//
//  LogIndexTests.swift
//  LogReaderTests
//
//  A log read as entries: grouping, growth, the provisional last line, long lines, and every filter.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import FileTools
import XCTest
@testable import LogReader

final class LogIndexTests: XCTestCase {
    var dir: URL!
    let ref = LogReference(year: 2026, month: 10, day: 1)

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("logindex-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    func write(_ text: String, name: String = "app.log") -> URL {
        let url = dir.appendingPathComponent(name)
        try? Data(text.utf8).write(to: url)
        return url
    }

    func append(_ text: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(text.utf8))
        try handle.close()
    }

    /// Scans to the end, synchronously.
    func scanned(_ url: URL) throws -> LogIndex {
        let index = LogIndex(file: try XCTUnwrap(LargeTextFile(url: url)), reference: ref)
        rescan(index)
        return index
    }

    func rescan(_ index: LogIndex) {
        let done = expectation(description: "scan")
        index.scan { summary in if summary.isComplete { done.fulfill() } }
        wait(for: [done], timeout: 10)
    }

    let sample = """
        starting up
        2026-10-01T00:00:00.000Z INFO  [auth] first
        2026-10-01T00:00:01.000Z ERROR [db] query failed
        java.sql.SQLException: timeout
            at com.example.Db.run(Db.java:42)
        {"ts":"2026-10-01T00:00:02.000Z","level":"warn","service":"auth","msg":"slow login"}
        2026-10-01T00:00:03.000Z DEBUG [cache] miss key=Alpha
        2026-10-01 00:00:04.000 UTC [77] ERROR:  relation "users" does not exist
        2026-10-01 00:00:04.000 UTC [77] STATEMENT:  SELECT * FROM users

        """

    func testEntriesGroupContinuationLines() throws {
        let index = try scanned(write(sample))
        XCTAssertEqual(index.entryCount, 6)
        let entries = (0..<6).compactMap(index.entry(at:))
        XCTAssertEqual(entries.map(\.format), [.text, .plain, .plain, .json, .plain, .plain])
        XCTAssertEqual(entries.map(\.firstLine), [0, 1, 2, 5, 6, 7])
        XCTAssertEqual(entries.map(\.lineCount), [1, 1, 3, 1, 1, 2])
        XCTAssertEqual(entries.map(\.level), [nil, .info, .error, .warning, .debug, .error])
        XCTAssertEqual(entries.map(\.component), [nil, "auth", "db", "auth", "cache", nil])
        XCTAssertEqual(
            index.text(of: entries[2]),
            "2026-10-01T00:00:01.000Z ERROR [db] query failed\njava.sql.SQLException: timeout\n    at com.example.Db.run(Db.java:42)")
        XCTAssertEqual(index.firstLine(of: entries[3]).head?.message, "slow login")
        let summary = index.summary
        XCTAssertEqual(summary.entryCount, 6)
        XCTAssertEqual(summary.levelCounts, [.info: 1, .error: 2, .warning: 1, .debug: 1])
        XCTAssertEqual(summary.unleveledCount, 1)
        XCTAssertEqual(summary.components.map(\.name), ["auth", "cache", "db"])
        XCTAssertEqual(summary.components.map(\.count), [2, 1, 1])
        XCTAssertEqual(summary.formats.first, .plain)
        XCTAssertTrue(summary.isComplete)
    }

    func testFilters() throws {
        let index = try scanned(write(sample))
        XCTAssertEqual(index.matching(LogFilter()), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(index.matching(LogFilter(levels: [.error, .fatal], showsUnleveled: false)), [2, 5])
        XCTAssertEqual(index.matching(LogFilter(levels: [], showsUnleveled: true)), [0])
        let one = LogTimeParser.daysFromCivil(2026, 10, 1) * 86_400
        XCTAssertEqual(
            index.matching(LogFilter(from: Double(one + 1), to: Double(one + 3))), [0, 2, 3, 4], "untimed entries pass a time bound")
        XCTAssertEqual(index.matching(LogFilter(components: ["auth"])), [1, 3])
        XCTAssertEqual(index.matching(LogFilter(text: "timeout")), [2], "text in a continuation line counts")
        XCTAssertEqual(index.matching(LogFilter(text: "alpha")), [4])
        XCTAssertEqual(index.matching(LogFilter(text: "alpha", caseSensitive: true)), [])
        XCTAssertEqual(index.matching(LogFilter(text: "SELECT \\* FROM \\w+", isRegex: true)), [5])
        XCTAssertEqual(index.matching(LogFilter(text: "(unclosed", isRegex: true)), [])
        XCTAssertEqual(index.matching(LogFilter(levels: [.error], showsUnleveled: false, text: "users")), [5])
        XCTAssertNil(index.matching(LogFilter(), isCancelled: { true }))
    }

    func testAFileWithNoHeadersIsOneEntryALine() throws {
        let index = try scanned(write("plain words\nan ERROR happened here\nWARNING and FATAL both\nlower case error\n"))
        XCTAssertEqual(index.entryCount, 4)
        XCTAssertEqual((0..<4).compactMap(index.entry(at:)).map(\.level), [nil, .error, .fatal, nil])
    }

    func testJavaUtilLoggingTakesItsLevelFromTheNextLine() throws {
        let index = try scanned(
            write(
                "Oct 01, 2026 12:00:00 AM com.example.Main run\nSEVERE: it broke\nOct 01, 2026 12:00:01 AM com.example.Main run\nINFO: fine\n"
            ))
        XCTAssertEqual(index.entryCount, 2)
        XCTAssertEqual((0..<2).compactMap(index.entry(at:)).map(\.level), [.error, .info])
        XCTAssertEqual(index.summary.levelCounts, [.error: 1, .info: 1])
        XCTAssertEqual(index.summary.unleveledCount, 0)
    }

    /// A log being written: the last line, with no break yet, is read provisionally and read again whole.
    func testGrowthReadsOnAndRereadsTheUnfinishedLastLine() throws {
        let url = write("2026-10-01T00:00:00Z INFO [a] one\n2026-10-01T00:00:01Z WARN [b] tw")
        let index = try scanned(url)
        XCTAssertEqual(index.entryCount, 2)
        XCTAssertEqual(index.entry(at: 1)?.level, .warning)
        try append("o\n    continued\n2026-10-01T00:00:02Z ERROR [c] three\n", to: url)
        XCTAssertTrue(index.file.grew())
        rescan(index)
        XCTAssertEqual(index.entryCount, 3)
        XCTAssertEqual((0..<3).compactMap(index.entry(at:)).map(\.lineCount), [1, 2, 1])
        XCTAssertEqual(index.entry(at: 1).map { index.text(of: $0) }, "2026-10-01T00:00:01Z WARN [b] two\n    continued")
        XCTAssertEqual(index.summary.levelCounts, [.info: 1, .warning: 1, .error: 1])
        XCTAssertEqual(index.summary.components.map(\.name), ["a", "b", "c"])
    }

    func testALineLongerThanABlockIsReadForItsHeader() throws {
        let long = "2026-10-01T00:00:00Z ERROR [big] " + String(repeating: "x", count: LogIndex.block + 10)
        let index = try scanned(write("\(long)\n2026-10-01T00:00:01Z INFO [small] after\n"))
        XCTAssertEqual(index.entryCount, 2)
        XCTAssertEqual((0..<2).compactMap(index.entry(at:)).map(\.component), ["big", "small"])
        XCTAssertEqual(index.entry(at: 1)?.firstLine, 1)
        XCTAssertEqual(index.matching(LogFilter(text: "after")), [1])
    }

    func testCRLFLinesReadTheSame() throws {
        let index = try scanned(write("2026-10-01T00:00:00Z INFO [a] one\r\n  more\r\n2026-10-01T00:00:01Z WARN [b] two\r\n"))
        XCTAssertEqual(index.entryCount, 2)
        XCTAssertEqual(index.entry(at: 0).map { index.text(of: $0) }, "2026-10-01T00:00:00Z INFO [a] one\r\n  more")
        XCTAssertEqual(index.entry(at: 1)?.component, "b")
    }
}
