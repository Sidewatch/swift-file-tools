//
//  LargeTextSearchTests.swift
//  FileToolsTests
//
//  A large text file searched for literals and regular expressions: forward and back from any place, wrapping at the
//  ends, across every read boundary, counted, each match's place among them, never across a line break, and at the
//  right bytes through accents, invalid UTF-8 and Windows-1252.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest

@testable import FileTools

final class LargeTextSearchTests: XCTestCase {
    private func file(_ text: String) throws -> LargeTextFile { try file(Data(text.utf8)) }

    private func file(_ data: Data) throws -> LargeTextFile {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("large-search-\(UUID().uuidString).txt")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return try XCTUnwrap(LargeTextFile(url: url))
    }

    private func matcher(_ text: String, caseSensitive: Bool = true, regex: Bool = false, in file: LargeTextFile) throws -> LargeTextMatcher
    {
        try XCTUnwrap(LargeTextMatcher(text: text, caseSensitive: caseSensitive, isRegex: regex, encoding: file.encoding))
    }

    /// Every match from the start, stepping with `next` from each one's end until it wraps, `block` bytes a read.
    private func every(_ matcher: LargeTextMatcher, in file: LargeTextFile, block: Int = LargeTextSearch.block) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var from = 0
        while let match = LargeTextSearch.next(matcher, in: file, from: from, block: block, isCancelled: { false }),
            match.lowerBound >= from, found.count < 10_000
        {
            found.append(match)
            from = match.upperBound
        }
        return found
    }

    /// The text at each range, read back from the file.
    private func texts(_ ranges: [Range<Int>], in file: LargeTextFile) -> [String] { ranges.map(file.text(in:)) }

    /// Every non-overlapping match, the way a plain left-to-right scan finds them (a needle without a line break never
    /// spans one).
    private func truth(_ needle: String, in text: String, caseSensitive: Bool) -> [Range<Int>] {
        let hay = Array((caseSensitive ? text : text.lowercased()).utf8)
        let pin = Array((caseSensitive ? needle : needle.lowercased()).utf8)
        var found: [Range<Int>] = []
        var at = 0
        while at + pin.count <= hay.count {
            if Array(hay[at..<(at + pin.count)]) == pin {
                found.append(at..<(at + pin.count))
                at += pin.count
            } else {
                at += 1
            }
        }
        return found
    }

    // MARK: - Literals

    func testALiteralMatchesEitherCaseUnlessCaseSensitive() throws {
        let text = try file("Error error ERROR errors")
        XCTAssertEqual(every(try matcher("error", caseSensitive: false, in: text), in: text).map(\.lowerBound), [0, 6, 12, 18])
        XCTAssertEqual(every(try matcher("error", in: text), in: text), [6..<11, 18..<23])
        let accents = try file("Café CAFÉ café")
        XCTAssertEqual(
            texts(every(try matcher("café", caseSensitive: false, in: accents), in: accents), in: accents), ["Café", "CAFÉ", "café"],
            "beyond ASCII, every case folds")
    }

    func testMatchesDoNotOverlapAndANonASCIILiteralMatchesItsBytes() throws {
        let a = try file("aaaaa")
        XCTAssertEqual(every(try matcher("aa", in: a), in: a), [0..<2, 2..<4])
        let euro = try file("a€b€")
        XCTAssertEqual(every(try matcher("€", in: euro), in: euro), [1..<4, 5..<8])
        XCTAssertNil(LargeTextMatcher(text: "", caseSensitive: true, isRegex: false, encoding: .utf8), "nothing to look for")
        XCTAssertNil(LargeTextMatcher(text: "a\nb", caseSensitive: true, isRegex: false, encoding: .utf8), "never across a break")
        XCTAssertNil(LargeTextMatcher(text: "(", caseSensitive: true, isRegex: true, encoding: .utf8), "does not compile")
    }

    func testNextAndPreviousWrapAtTheFilesEnds() throws {
        let text = try file("one two\nthree two\nfour")
        let two = try matcher("two", in: text)
        XCTAssertEqual(LargeTextSearch.next(two, in: text, from: 0), 4..<7)
        XCTAssertEqual(LargeTextSearch.next(two, in: text, from: 5), 14..<17, "a match begun before the place is not after it")
        XCTAssertEqual(LargeTextSearch.next(two, in: text, from: 15), 4..<7, "wraps to the start")
        XCTAssertEqual(LargeTextSearch.previous(two, in: text, before: 14), 4..<7)
        XCTAssertEqual(LargeTextSearch.previous(two, in: text, before: 4), 14..<17, "wraps to the end")
        XCTAssertNil(LargeTextSearch.next(try matcher("five", in: text), in: text, from: 3))
        XCTAssertNil(LargeTextSearch.previous(try matcher("five", in: text), in: text, before: 3))
    }

    /// Random texts read a few bytes at a time: from every place, forward and back, every read boundary included, the
    /// matches are what a plain scan finds; the count is theirs and each one's place among them is its own.
    func testEveryReadBoundaryFindsWhatAPlainScanFinds() throws {
        var state: UInt64 = 0x5EA4C
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let alphabet = Array("abAB\n")
        for round in 0..<300 {
            let text = String((0..<Int(next() % 80)).map { _ in alphabet[Int(next() % 5)] })
            let needle = ["ab", "aba", "bb", "AbA", "a"][Int(next() % 5)]
            let caseSensitive = next() % 2 == 0
            // A read always holds a whole line here: one cut inside a line is the documented miss.
            let longest = text.split(separator: "\n", omittingEmptySubsequences: false).map(\.utf8.count).max() ?? 0
            let block = longest + 1 + Int(next() % 9)
            let file = try file(text)
            let matcher = try matcher(needle, caseSensitive: caseSensitive, in: file)
            let expected = truth(needle, in: text, caseSensitive: caseSensitive)
            let context = "round \(round): \(needle) in \(text.debugDescription), block \(block)"
            let found = every(matcher, in: file, block: block)
            guard found == expected else { return XCTFail("\(context): next found \(found)") }
            let from = Int(next() % UInt64(text.utf8.count + 1))
            let after = LargeTextSearch.next(matcher, in: file, from: from, block: block, isCancelled: { false })
            guard after == (expected.first { $0.lowerBound >= from } ?? expected.first) else {
                return XCTFail("\(context): next from \(from) found \(String(describing: after))")
            }
            for (i, match) in expected.enumerated() {
                let before = LargeTextSearch.previous(matcher, in: file, before: match.lowerBound, block: block, isCancelled: { false })
                guard before == expected[(i - 1 + expected.count) % expected.count] else {
                    return XCTFail("\(context): previous before \(match) found \(String(describing: before))")
                }
            }
            let count = try XCTUnwrap(LargeTextSearch.count(matcher, in: file, block: block, isCancelled: { false }))
            guard count.total == expected.count else { return XCTFail("\(context): counted \(count.total)") }
            for (i, match) in expected.enumerated() where LargeTextSearch.index(of: match, in: count, matcher, file: file) != i {
                return XCTFail("\(context): \(match) is not number \(i)")
            }
        }
    }

    func testTheMatchesInAScreenful() throws {
        let text = try file("alpha beta alpha\nalpha")
        XCTAssertEqual(LargeTextSearch.matches(try matcher("alpha", in: text), in: text, within: 0..<16), [0..<5, 11..<16])
        XCTAssertEqual(LargeTextSearch.matches(try matcher("alpha", in: text), in: text, within: 17..<22), [17..<22])
    }

    func testCancellationStopsEverySearch() throws {
        let text = try file(String(repeating: "x ", count: 1000))
        let x = try matcher("x", in: text)
        XCTAssertNil(LargeTextSearch.next(x, in: text, from: 0, isCancelled: { true }))
        XCTAssertNil(LargeTextSearch.previous(x, in: text, before: 100, isCancelled: { true }))
        XCTAssertNil(LargeTextSearch.count(x, in: text, isCancelled: { true }))
        XCTAssertEqual(LargeTextSearch.count(x, in: text)?.total, 1000)
    }

    // MARK: - Regular expressions

    func testARegexMatchesLineByLineAndNeverAcrossABreak() throws {
        let text = try file("status=500 ok\nStatus=503\nb start\nab\r\nend")
        func found(_ pattern: String, caseSensitive: Bool = true) throws -> [String] {
            texts(every(try matcher(pattern, caseSensitive: caseSensitive, regex: true, in: text), in: text), in: text)
        }
        XCTAssertEqual(try found("status=50\\d"), ["status=500"])
        XCTAssertEqual(try found("status=50\\d", caseSensitive: false), ["status=500", "Status=503"])
        XCTAssertEqual(try found("^b\\w*"), ["b"], "^ is a line's start")
        XCTAssertEqual(try found("b$"), ["b"], "$ is a line's end, before a CRLF too")
        XCTAssertEqual(try found("ok\\n"), [], "never across a line break")
        XCTAssertEqual(try found("x*"), [], "never an empty match")
    }

    /// Matches after accented and wide characters land on their own bytes.
    func testARegexMatchInAccentedTextIsAtItsBytes() throws {
        let text = try file("café 😀 é+é\nnaïve")
        XCTAssertEqual(texts(every(try matcher("é\\+é|ï", regex: true, in: text), in: text), in: text), ["é+é", "ï"])
    }

    /// Invalid UTF-8 past the opening the encoding is judged from: each repair is one character however many bytes it
    /// spans, and the matches after it still land on their bytes.
    func testARegexAfterInvalidUTF8IsAtItsBytes() throws {
        var bytes = Array((0..<8_000).map { "line \($0)" }.joined(separator: "\n").utf8)
        bytes += Array("\nok é ".utf8) + [0xFF] + Array("X1 ".utf8) + [0xE2, 0x82] + Array("X2 ".utf8) + [0xC0, 0xAF]
        bytes += Array("X3 ".utf8) + [0xED, 0xA0, 0x80] + Array("X4 😀 ".utf8) + [0xF0, 0x9F] + Array("X5\n".utf8) + [0x80, 0x80]
        bytes += Array("X6".utf8)
        let text = try file(Data(bytes))
        XCTAssertEqual(text.encoding, .utf8, "the opening is valid UTF-8")
        let expected = bytes.indices.filter { bytes[$0] == 0x58 }.map { $0..<($0 + 2) }
        XCTAssertEqual(expected.count, 6)
        XCTAssertEqual(every(try matcher("X\\d", regex: true, in: text), in: text), expected)
    }

    func testAWindows1252FileIsSearchedAtItsBytes() throws {
        let text = try file(Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94, 0x0A]))
        XCTAssertEqual(text.encoding, .windowsCP1252)
        XCTAssertEqual(every(try matcher("\u{201C}q", regex: true, in: text), in: text), [5..<7])
        XCTAssertEqual(every(try matcher("café", in: text), in: text), [0..<4], "a literal in the file's encoding")
        XCTAssertEqual(every(try matcher("CAFÉ", caseSensitive: false, in: text), in: text), [0..<4])
    }

    // MARK: - The walk from text back to bytes

    /// From every character of randomly broken UTF-8, the walk lands on the bytes that decode to the rest of the text,
    /// so the decoder's repairs and the walk's agree.
    func testTheWalkLandsWhereTheDecoderRepairedFrom() {
        let pieces: [[UInt8]] = [
            [0x61], [0xC3, 0xA9], [0xE2, 0x82, 0xAC], [0xF0, 0x9F, 0x98, 0x80], [0xFF], [0x80], [0xE2, 0x82], [0xC0, 0xAF],
            [0xED, 0xA0, 0x80], [0xF0, 0x9F], [0xF4, 0x90, 0x80, 0x80], [0xE0, 0x80, 0x80],
        ]
        var state: UInt64 = 0xC0FFEE
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        for round in 0..<500 {
            let bytes = (0..<Int(next() % 12)).flatMap { _ in pieces[Int(next() % UInt64(pieces.count))] }
            let decoded = String(decoding: bytes, as: UTF8.self)
            var walker = UTF8OffsetWalker(bytes[...])
            var index = decoded.unicodeScalars.startIndex
            var utf16 = 0
            while index < decoded.unicodeScalars.endIndex {
                let byte = walker.byteOffset(ofUTF16: utf16)
                guard String(decoding: bytes[byte...], as: UTF8.self) == String(decoded.unicodeScalars[index...]) else {
                    return XCTFail("round \(round): \(bytes) at UTF-16 \(utf16) walked to byte \(byte)")
                }
                utf16 += decoded.unicodeScalars[index].utf16.count
                index = decoded.unicodeScalars.index(after: index)
            }
            XCTAssertEqual(walker.byteOffset(ofUTF16: utf16), bytes.count, "round \(round): the end")
        }
    }
}
