//
//  TextFileContentsTests.swift
//  FileToolsTests
//
//  Decoding a file's bytes the way a text editor must: UTF-8 with its byte-order mark
//  remembered, Windows-1252 when the bytes are not UTF-8, Latin-1 when they are not Windows-1252
//  either, and nothing for a binary file.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class TextFileContentsTests: XCTestCase {
    func testUTF8WithAByteOrderMarkDropsItFromTheTextAndRemembersIt() throws {
        let contents = try XCTUnwrap(TextFileContents(data: Data([0xEF, 0xBB, 0xBF]) + Data("hi".utf8)))
        XCTAssertEqual(contents.text, "hi")
        XCTAssertTrue(contents.encoding.hasByteOrderMark)
    }

    func testBytesThatAreNotUTF8ReadAsWindows1252() throws {
        let contents = try XCTUnwrap(TextFileContents(data: Data([0x63, 0x61, 0x66, 0xE9])))
        XCTAssertEqual(contents.text, "café")
        XCTAssertEqual(contents.encoding.encoding, .windowsCP1252)
    }

    func testWindows1252ShowsItsQuotesEuroAndDashesAndSavesThemBackByteExact() throws {
        // “hi” €5 – … in Windows-1252: 0x80–0x9F are printable there, control characters in Latin-1.
        let bytes = Data([0x93, 0x68, 0x69, 0x94, 0x20, 0x80, 0x35, 0x20, 0x96, 0x20, 0x85, 0x0A])
        let contents = try XCTUnwrap(TextFileContents(data: bytes))
        XCTAssertEqual(contents.text, "\u{201C}hi\u{201D} \u{20AC}5 \u{2013} \u{2026}\n")
        XCTAssertEqual(contents.data(for: contents.text), bytes, "a no-op save writes the same bytes")
        XCTAssertNotNil(contents.data(for: contents.text + "\u{20AC}"), "a typed euro fits the file's own encoding")
        XCTAssertNil(contents.data(for: "\u{2192}"), "an arrow does not, and is never re-encoded on its own")
    }

    func testEveryDefinedWindows1252ByteRoundTrips() throws {
        let undefined: Set<UInt8> = [0x81, 0x8D, 0x8F, 0x90, 0x9D]
        let bytes = Data((0x80...0xFF).map { UInt8($0) }.filter { !undefined.contains($0) })
        let contents = try XCTUnwrap(TextFileContents(data: bytes))
        XCTAssertEqual(contents.encoding.encoding, .windowsCP1252)
        XCTAssertEqual(contents.data(for: contents.text), bytes)
    }

    func testAByteWindows1252LeavesUndefinedFallsBackToLatin1AndRoundTrips() throws {
        for byte: UInt8 in [0x81, 0x8D, 0x8F, 0x90, 0x9D] {
            let bytes = Data([0x93, 0x61, byte, 0x94])
            let contents = try XCTUnwrap(TextFileContents(data: bytes))
            XCTAssertEqual(contents.encoding.encoding, .isoLatin1, String(format: "%02X", byte))
            XCTAssertTrue(contents.decodedByFallback)
            XCTAssertEqual(contents.data(for: contents.text), bytes, "Latin-1 maps every byte, so nothing is lost")
        }
    }

    func testUTF16WithAMarkOpensAsTextAndRoundTripsByteExact() throws {
        let little = Data([0xFF, 0xFE]) + "hi\n".data(using: .utf16LittleEndian)!
        let le = try XCTUnwrap(TextFileContents(data: little), "the mark is read before the NUL sniff")
        XCTAssertEqual(le.text, "hi\n")
        XCTAssertEqual(le.encoding, .utf16LittleEndian)
        XCTAssertEqual(le.data(for: le.text), little, "a no-op save writes the same bytes")
        let big = Data([0xFE, 0xFF]) + "hi\n".data(using: .utf16BigEndian)!
        let be = try XCTUnwrap(TextFileContents(data: big))
        XCTAssertEqual(be.encoding, .utf16BigEndian)
        XCTAssertEqual(be.data(for: be.text), big)
        XCTAssertNil(TextFileContents(data: "hi\n".data(using: .utf16LittleEndian)!), "an unmarked UTF-16 file still reads as binary")
    }

    func testANonUTF8DecodeIsReportedAsTheFallbackItIs() throws {
        XCTAssertTrue(try XCTUnwrap(TextFileContents(data: Data([0x63, 0x61, 0x66, 0xE9]))).decodedByFallback)
        XCTAssertFalse(try XCTUnwrap(TextFileContents(data: Data("café".utf8))).decodedByFallback)
        XCTAssertEqual(TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false).displayName, "Latin-1")
        XCTAssertEqual(TextFileEncoding(encoding: .windowsCP1252, hasByteOrderMark: false).displayName, "Windows-1252")
        XCTAssertEqual(TextFileEncoding.utf16LittleEndian.displayName, "UTF-16 LE")
        XCTAssertNil(TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false).data(for: "→"), "never re-encoded on its own")
    }

    func testTheBinarySniffReadsTheFirst8000BytesOnly() {
        var bytes = Data(repeating: 0x61, count: 9000)
        bytes[7999] = 0
        XCTAssertTrue(TextFileContents.hasBinaryPrefix(bytes), "a NUL at the 8,000th byte")
        XCTAssertNil(TextFileContents(data: bytes))
        bytes[7999] = 0x61
        bytes[8000] = 0
        XCTAssertFalse(TextFileContents.hasBinaryPrefix(bytes), "a NUL past the sniff")
        XCTAssertNotNil(TextFileContents(data: bytes), "decoded as text, as before")
    }

    func testALongLineIsFoundWhereverItIs() {
        let short = Data("ab\ncd\n".utf8)
        XCTAssertFalse(TextFileContents.hasLine(atLeast: 3, in: short))
        XCTAssertTrue(TextFileContents.hasLine(atLeast: 2, in: short))
        XCTAssertTrue(TextFileContents.hasLine(atLeast: 3, in: Data("a\nbbb".utf8)), "the last line, with no break after it")
        XCTAssertTrue(TextFileContents.hasLine(atLeast: 3, in: Data("ccc\nd".utf8)), "the first line")
        XCTAssertTrue(TextFileContents.hasLine(atLeast: 3, in: Data("cc\r\nd".utf8)), "a carriage return counts as a byte of its line")
        XCTAssertFalse(TextFileContents.hasLine(atLeast: 1, in: Data()))
    }

    func testABinaryFileIsNotText() {
        XCTAssertNil(TextFileContents(data: Data([0x50, 0x4B, 0x00, 0x03])))
    }

    func testContentsOfURLReadsAndDecodesAndAnswersNilForAMissingFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tfc-\(UUID()).txt")
        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(TextFileContents(contentsOf: url)?.text, "café")
        XCTAssertNil(TextFileContents(contentsOf: url.appendingPathExtension("missing")))
    }
}
