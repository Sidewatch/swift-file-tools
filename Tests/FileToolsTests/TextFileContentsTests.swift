//
//  TextFileContentsTests.swift
//  FileToolsTests
//
//  Decoding a file's bytes the way a text editor must: UTF-8 with its byte-order mark
//  remembered, Latin-1 when the bytes are not UTF-8, and nothing for a binary file.
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

    func testBytesThatAreNotUTF8FallBackToLatin1() throws {
        let contents = try XCTUnwrap(TextFileContents(data: Data([0x63, 0x61, 0x66, 0xE9])))
        XCTAssertEqual(contents.text, "café")
        XCTAssertEqual(contents.encoding.encoding, .isoLatin1)
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

    func testLatin1IsReportedAsTheFallbackItIs() throws {
        XCTAssertTrue(try XCTUnwrap(TextFileContents(data: Data([0x63, 0x61, 0x66, 0xE9]))).decodedByFallback)
        XCTAssertFalse(try XCTUnwrap(TextFileContents(data: Data("café".utf8))).decodedByFallback)
        XCTAssertEqual(TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false).displayName, "Latin-1")
        XCTAssertEqual(TextFileEncoding.utf16LittleEndian.displayName, "UTF-16 LE")
        XCTAssertNil(TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false).data(for: "→"), "never re-encoded on its own")
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
