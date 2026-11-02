//
//  LogFixtureTests.swift
//  LogReaderTests
//
//  Every fixture log against the answers its own generator wrote: real tool output (Python, pino, bunyan, winston,
//  structlog, Ruby's Logger, PHP and Monolog, Rust, Apache httpd, macOS's log, logfmt) and documentation-derived
//  samples for the tools not installed (nginx, PostgreSQL, MySQL, Redis, Docker, klog, logcat, Elixir, Go, Java).
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import FileTools
import XCTest
@testable import LogReader

final class LogFixtureTests: XCTestCase {
    struct Expected: Decodable {
        let source: String
        let referenceDate: String
        let entries: [Entry]
        struct Entry: Decodable {
            let line: Int
            let lines: Int
            let level: String?
            let time: String?
            let zoned: Bool
            let component: String?
        }
    }

    /// Every `<name>.log` beside its `<name>.expected.json`; the headers-less lines a format writes between entries
    /// (separators, a file header) are the reader's own `text` entries and are not in the answers.
    func testEveryFixtureReadsAsItsGeneratorSays() throws {
        let root = try XCTUnwrap(Bundle.module.url(forResource: "logs", withExtension: nil, subdirectory: "Fixtures"))
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)).compactMap { $0 as? URL }
            .filter { $0.lastPathComponent.hasSuffix(".expected.json") }.sorted { $0.path < $1.path }
        XCTAssertGreaterThanOrEqual(files.count, 44)
        var report: [String] = []
        var total = 0
        for answers in files {
            let log = answers.deletingLastPathComponent().appendingPathComponent(
                answers.lastPathComponent.replacingOccurrences(of: ".expected.json", with: ".log"))
            let expected = try JSONDecoder().decode(Expected.self, from: Data(contentsOf: answers))
            let mismatches = try compare(log, expected)
            total += expected.entries.count
            if !mismatches.isEmpty {
                let name = log.pathComponents.suffix(2).joined(separator: "/")
                report.append(
                    "\(name): \(mismatches.count) of \(expected.entries.count)\n    " + mismatches.prefix(4).joined(separator: "\n    "))
            }
        }
        print("FIXTURES \(files.count) files, \(total) entries, \(report.count) with mismatches")
        XCTAssertEqual(report.count, 0, "\n" + report.joined(separator: "\n"))
    }

    private func compare(_ url: URL, _ expected: Expected) throws -> [String] {
        let parts = expected.referenceDate.split(separator: "-").compactMap { Int($0) }
        let index = LogIndex(
            file: try XCTUnwrap(LargeTextFile(url: url)), reference: LogReference(year: parts[0], month: parts[1], day: parts[2]))
        let done = expectation(description: url.lastPathComponent)
        index.scan { if $0.isComplete { done.fulfill() } }
        wait(for: [done], timeout: 20)
        let mine = (0..<index.entryCount).compactMap(index.entry(at:)).filter { $0.format != .text }
        var out: [String] = []
        if mine.count != expected.entries.count { out.append("entries: \(mine.count), expected \(expected.entries.count)") }
        var byLine: [Int: LogEntry] = [:]
        for entry in mine { byLine[entry.firstLine + 1] = entry }
        for want in expected.entries {
            guard let got = byLine[want.line] else {
                out.append("line \(want.line): no entry starts here")
                continue
            }
            var diffs: [String] = []
            if got.lineCount != want.lines { diffs.append("lines \(got.lineCount)≠\(want.lines)") }
            let level = got.level.map { "\($0)" }
            if level != want.level { diffs.append("level \(level ?? "nil")≠\(want.level ?? "nil")") }
            if got.component != want.component { diffs.append("component \(got.component ?? "nil")≠\(want.component ?? "nil")") }
            switch (got.time, want.time.flatMap(Self.seconds)) {
            case (nil, nil): break
            case (let g?, let w?):
                // A line that prints whole seconds (java.util.logging) can only say the second.
                let wholeSecond = g.seconds == g.seconds.rounded(.down) && w - g.seconds >= 0 && w - g.seconds < 1
                if abs(g.seconds - w) > 0.0015, !wholeSecond { diffs.append("time \(g.seconds)≠\(w)") }
                if g.zoned != want.zoned { diffs.append("zoned \(g.zoned)≠\(want.zoned)") }
            default: diffs.append("time \(got.time.map { "\($0.seconds)" } ?? "nil")≠\(want.time ?? "nil")")
            }
            if !diffs.isEmpty { out.append("line \(want.line): " + diffs.joined(separator: ", ")) }
        }
        return out
    }

    /// `2026-10-01T00:00:00.123Z` as seconds since the epoch.
    static func seconds(_ iso: String) -> Double? {
        var c = ByteCursor(Array(iso.utf8)[...])
        return LogTimeParser.iso(&c)?.seconds
    }
}
