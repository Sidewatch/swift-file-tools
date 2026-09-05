//
//  TerminalPathParserTests.swift
//  FileToolsTests
//
//  TerminalPathParserTests.
//
//  Created by David Sherlock on 7/21/26.
//

import XCTest
@testable import FileTools

final class TerminalPathParserTests: XCTestCase {
    typealias Match = TerminalPathParser.Match

    // MARK: - parse(_:)

    func testParsePathLineColumn() {
        XCTAssertEqual(TerminalPathParser.parse("src/Foo.swift:42:10"),
                       Match(path: "src/Foo.swift", line: 42, column: 10))
    }

    func testParsePathLine() {
        XCTAssertEqual(TerminalPathParser.parse("./a.ts:5"),
                       Match(path: "./a.ts", line: 5, column: nil))
    }

    func testParseRelativeAndAbsolute() {
        XCTAssertEqual(TerminalPathParser.parse("../lib/bar.rb"), Match(path: "../lib/bar.rb"))
        XCTAssertEqual(TerminalPathParser.parse("/Users/x/y/z.py:88"),
                       Match(path: "/Users/x/y/z.py", line: 88))
    }

    func testParseBareFilenameWithExtension() {
        XCTAssertEqual(TerminalPathParser.parse("README.md"), Match(path: "README.md"))
        XCTAssertEqual(TerminalPathParser.parse("Package.swift:3"), Match(path: "Package.swift", line: 3))
    }

    func testStripsWrappingPunctuationAndTrailing() {
        XCTAssertEqual(TerminalPathParser.parse("\"src/App.swift:12\""),
                       Match(path: "src/App.swift", line: 12))
        XCTAssertEqual(TerminalPathParser.parse("(main.go:7:2)"),
                       Match(path: "main.go", line: 7, column: 2))
        XCTAssertEqual(TerminalPathParser.parse("src/x.rs:9."), Match(path: "src/x.rs", line: 9))
    }

    func testRejectsNonPaths() {
        XCTAssertNil(TerminalPathParser.parse("hello"))          // no slash, no extension
        XCTAssertNil(TerminalPathParser.parse("42"))             // just a number
        XCTAssertNil(TerminalPathParser.parse(""))
        XCTAssertNil(TerminalPathParser.parse("::"))
    }

    func testRejectsURLs() {
        XCTAssertNil(TerminalPathParser.parse("https://example.com/a.js"))
        XCTAssertNil(TerminalPathParser.parse("file:///Users/x/y.txt"))
    }

    func testPathWithNoLineButColonInName() {
        // A trailing non-numeric segment isn't a line number.
        XCTAssertEqual(TerminalPathParser.parse("weird:name/file.txt"),
                       Match(path: "weird:name/file.txt"))
    }

    // MARK: - match(in:at:)

    func testMatchAtColumnInMiddleOfToken() {
        let line = "  Modified src/Editor/View.swift:120:4 — done"
        // Click somewhere inside "src/Editor/View.swift:120:4"
        let col = line.distance(from: line.startIndex, to: line.range(of: "Editor")!.lowerBound)
        XCTAssertEqual(TerminalPathParser.match(in: line, at: col),
                       Match(path: "src/Editor/View.swift", line: 120, column: 4))
    }

    func testMatchOnWhitespaceReturnsNil() {
        let line = "a.swift  b.swift"
        let spaceCol = line.distance(from: line.startIndex, to: line.firstIndex(of: " ")!)
        XCTAssertNil(TerminalPathParser.match(in: line, at: spaceCol))
    }

    func testMatchPicksTheTokenUnderTheColumn() {
        let line = "first.txt second.md:3"
        // Column inside "second.md:3"
        let col = line.distance(from: line.startIndex, to: line.range(of: "second")!.lowerBound)
        XCTAssertEqual(TerminalPathParser.match(in: line, at: col), Match(path: "second.md", line: 3))
        // Column inside "first.txt"
        XCTAssertEqual(TerminalPathParser.match(in: line, at: 0), Match(path: "first.txt"))
    }

    func testMatchOutOfRangeAndEmpty() {
        XCTAssertNil(TerminalPathParser.match(in: "", at: 0))
        XCTAssertNil(TerminalPathParser.match(in: "a.txt", at: 999))
        // One past the end of a token resolves the token.
        XCTAssertEqual(TerminalPathParser.match(in: "a.txt", at: 5), Match(path: "a.txt"))
    }
}
