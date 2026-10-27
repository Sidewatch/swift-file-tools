//
//  LargeTextFileTests.swift
//  FileToolsTests
//
//  A large text file's lines, found by its scan and read back one at a time, against a plain split of the same
//  text: at sizes small enough to cross every index, long-line and read boundary many times over.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import FileTools

final class LargeTextFileTests: XCTestCase {
    /// `bytes` written to a scratch file, opened with small sizes and scanned.
    private func scanned(_ bytes: [UInt8], stride: Int = 4, longLine: Int = 16, chunk: Int = 32) throws -> LargeTextFile {
        let url = try write(bytes)
        let file = try XCTUnwrap(LargeTextFile(url: url, stride: stride, longLine: longLine, chunk: chunk))
        file.scan()
        return file
    }

    private func write(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-text-\(UUID().uuidString).txt")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The lines a split finds: at every `\n`, a `\r` before it dropped, the text after the last one a line too.
    private func split(_ bytes: [UInt8]) -> [[UInt8]] {
        bytes.split(separator: 0x0A, omittingEmptySubsequences: false).map { line in
            line.last == 0x0D ? Array(line.dropLast()) : Array(line)
        }
    }

    func testLinesEndAtLineFeedsAndACarriageReturnBeforeOneIsDropped() throws {
        let file = try scanned(Array("a\nbb\r\nccc".utf8))
        XCTAssertEqual(file.lineCount, 3)
        XCTAssertEqual((0..<3).compactMap(file.text(ofLine:)), ["a", "bb", "ccc"])
        XCTAssertNil(file.text(ofLine: 3))
        XCTAssertNil(file.text(ofLine: -1))
    }

    func testAFinalBreakLeavesAnEmptyLastLineAndAnEmptyFileHasOne() throws {
        let ended = try scanned(Array("a\n".utf8))
        XCTAssertEqual(ended.lineCount, 2)
        XCTAssertEqual(ended.text(ofLine: 1), "")
        let empty = try scanned([])
        XCTAssertEqual(empty.lineCount, 1)
        XCTAssertEqual(empty.text(ofLine: 0), "")
    }

    /// Random texts with empty, short and long lines (past the long-line length), CRLF and LF, with and without a
    /// final break: every line read back equals the split's, from any starting point, and every byte names its line.
    func testEveryLineAndEveryByteMatchASplit() throws {
        var rng = SplitMix(seed: 0x1A26)
        for round in 0..<60 {
            var bytes: [UInt8] = []
            for _ in 0..<Int(rng.next() % 40) {
                let length = [0, 1, 3, 7, 15, 16, 17, 40][Int(rng.next() % 8)]
                bytes += (0..<length).map { _ in UInt8(97 + rng.next() % 26) }
                bytes += rng.next() % 3 == 0 ? [0x0D, 0x0A] : [0x0A]
            }
            if rng.next() % 2 == 0 { bytes += Array("tail".utf8) }
            let truth = split(bytes)
            let file = try scanned(bytes, stride: 1 + Int(rng.next() % 5), chunk: 8 + Int(rng.next() % 40))
            XCTAssertEqual(file.lineCount, truth.count, "round \(round)")
            XCTAssertTrue(file.progress.isComplete)
            for i in (0..<truth.count).reversed() where file.text(ofLine: i) != String(decoding: truth[i], as: UTF8.self) {
                return XCTFail("round \(round), line \(i): \(String(describing: file.text(ofLine: i))) for \(bytes)")
            }
            var expected = 0
            for (offset, byte) in bytes.enumerated() {
                if file.line(containingByte: offset) != expected { return XCTFail("round \(round), byte \(offset) for \(bytes)") }
                if byte == 0x0A { expected += 1 }
            }
            let longest = truth.map(\.count).max() ?? 0  // a `\r` before a break counts in the file's measure
            XCTAssertGreaterThanOrEqual(file.progress.longestLineBytes, longest, "round \(round)")
        }
    }

    func testAFileWhoseOpeningIsNotUTF8ReadsAsWindows1252() throws {
        let file = try scanned([0x63, 0x61, 0x66, 0xE9, 0x0A, 0x93, 0x71, 0x94])
        XCTAssertEqual(file.encoding, .windowsCP1252)
        XCTAssertEqual(file.text(ofLine: 0), "café")
        XCTAssertEqual(file.text(ofLine: 1), "\u{201C}q\u{201D}")
    }

    func testANULInTheOpeningMakesItBinary() throws {
        XCTAssertTrue(try scanned([0x61, 0x00, 0x62]).isBinary)
        XCTAssertFalse(try scanned(Array("text\n".utf8)).isBinary)
    }

    func testAWindowIntoALongLineStartsOnACharacter() throws {
        let file = try scanned(Array("a€b".utf8))  // 61 E2 82 AC 62
        XCTAssertEqual([0, 1, 2, 3, 4, 5].map(file.characterStart(atOrBefore:)), [0, 1, 1, 1, 4, 5])
    }

    /// A line's start is found back from any byte without the scan, as far as the limit allows: across the reads it
    /// takes, at the file's start, and not at all inside a line longer than the limit.
    func testALineStartIsFoundBackToItsLimit() throws {
        let file = try XCTUnwrap(LargeTextFile(url: try write(Array("abc\ndefgh\nij".utf8))))
        XCTAssertEqual([0, 3, 4, 6, 9, 10, 11].map { file.lineStart(atOrBefore: $0, within: 100) }, [0, 0, 4, 4, 4, 10, 10])
        XCTAssertEqual(file.lineStart(atOrBefore: 11, within: 2), 10)
        XCTAssertEqual(file.lineStart(atOrBefore: 11, within: 1), 11, "no break that near: the place itself")
        let long = try XCTUnwrap(LargeTextFile(url: try write(Array(("x\n" + String(repeating: "y", count: 150_000)).utf8))))
        XCTAssertEqual(long.lineStart(atOrBefore: 150_001, within: 200_000), 2, "back across three reads")
        XCTAssertEqual(long.lineStart(atOrBefore: 150_001, within: 100_000), 150_001)
    }

    /// A log that grows is read on from where the scan stopped; its unfinished last line gets longer.
    func testAGrowingFileIsReadOn() throws {
        let url = try write(Array("one\ntw".utf8))
        let file = try XCTUnwrap(LargeTextFile(url: url, stride: 2, longLine: 16, chunk: 4))
        file.scan()
        XCTAssertEqual((0..<file.lineCount).compactMap(file.text(ofLine:)), ["one", "tw"])
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("o\nthree\n".utf8))
        try handle.close()
        XCTAssertTrue(file.grew())
        XCTAssertFalse(file.progress.isComplete)
        file.scan()
        XCTAssertEqual((0..<file.lineCount).compactMap(file.text(ofLine:)), ["one", "two", "three", ""])
        XCTAssertFalse(file.grew(), "nothing new")
    }

    /// Part way through a scan, only the lines it has seen end count, never the one it is in the middle of (it may be
    /// longer than it has read so far); finished, the last line counts too.
    func testALineTheScanIsStillReadingIsNotCounted() throws {
        let url = try write(Array("one\ntwo\nthree\nfour".utf8))
        let file = try XCTUnwrap(LargeTextFile(url: url, stride: 2, longLine: 16, chunk: 6))
        var afterTheFirstRead: (count: Int, lines: [String])?
        file.scan {  // the first read is "one\ntw"
            if afterTheFirstRead == nil {
                afterTheFirstRead = (file.lineCount, (0..<file.lineCount).compactMap(file.text(ofLine:)))
            }
        }
        XCTAssertEqual(afterTheFirstRead?.count, 1, "\"tw\" is not yet a line")
        XCTAssertEqual(afterTheFirstRead?.lines, ["one"])
        XCTAssertEqual((0..<file.lineCount).compactMap(file.text(ofLine:)), ["one", "two", "three", "four"])
    }

    /// Truncation is told apart from growth: an unchanged or longer file is not truncated, a shorter one is.
    func testTruncationIsToldApartFromGrowth() throws {
        let url = try write(Array("one\ntwo\n".utf8))
        let file = try XCTUnwrap(LargeTextFile(url: url))
        XCTAssertFalse(file.isTruncated, "unchanged")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("three\n".utf8))
        try handle.close()
        XCTAssertFalse(file.isTruncated, "longer")
        XCTAssertTrue(file.grew())
        XCTAssertFalse(file.isTruncated, "longer, and taken in")
        try FileHandle(forWritingTo: url).truncate(atOffset: 4)
        XCTAssertTrue(file.isTruncated, "shorter than was read")
    }

    /// A file truncated under the reader (a log rotation) reads short, never past its end, and says so.
    func testAFileTruncatedBeforeTheScanEndsWhereItNowEnds() throws {
        let url = try write(Array("one\ntwo\nthree\n".utf8))
        let file = try XCTUnwrap(LargeTextFile(url: url, stride: 2, longLine: 16, chunk: 4))
        try FileHandle(forWritingTo: url).truncate(atOffset: 6)
        XCTAssertTrue(file.isTruncated)
        file.scan()
        XCTAssertEqual((0..<file.lineCount).compactMap(file.text(ofLine:)), ["one", "tw"])
    }

    /// A scan runs off the main thread and reports its progress there, ending with a complete one.
    func testTheBackgroundScanReportsToTheMainQueue() throws {
        let file = try XCTUnwrap(LargeTextFile(url: try write(Array(String(repeating: "line\n", count: 1000).utf8))))
        let done = expectation(description: "scan complete")
        file.scanLines { progress in
            XCTAssertTrue(Thread.isMainThread)
            if progress.isComplete {
                XCTAssertEqual(progress.lineCount, 1001)
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
    }
}

/// A deterministic generator, so a failing round replays.
private struct SplitMix {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
