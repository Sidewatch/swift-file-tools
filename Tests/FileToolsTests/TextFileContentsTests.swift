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
