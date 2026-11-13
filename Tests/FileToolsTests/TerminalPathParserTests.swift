//
//  TerminalPathParserTests.swift
//  FileToolsTests
//
//  Tests for `TerminalPathParser.parse`: `path:line:column`, `path:line`, bare paths, and the
//  shapes that must not match.
//
//  Created by David Sherlock on 7/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `TerminalPathParser.parse`: `path:line:column`, `path:line`, bare paths, and the
/// shapes that must not match.
final class TerminalPathParserTests: XCTestCase {
    typealias Match = TerminalPathParser.Match

    // MARK: - parse(_:)

    func testParsePathLineColumn() {
        XCTAssertEqual(
            TerminalPathParser.parse("src/Foo.swift:42:10"),
            Match(path: "src/Foo.swift", line: 42, column: 10))
    }

    func testParsePathLine() {
        XCTAssertEqual(
            TerminalPathParser.parse("./a.ts:5"),
            Match(path: "./a.ts", line: 5, column: nil))
    }

    func testParseRelativeAndAbsolute() {
        XCTAssertEqual(TerminalPathParser.parse("../lib/bar.rb"), Match(path: "../lib/bar.rb"))
        XCTAssertEqual(
            TerminalPathParser.parse("/Users/x/y/z.py:88"),
            Match(path: "/Users/x/y/z.py", line: 88))
    }

    func testParseBareFilenameWithExtension() {
        XCTAssertEqual(TerminalPathParser.parse("README.md"), Match(path: "README.md"))
        XCTAssertEqual(TerminalPathParser.parse("Package.swift:3"), Match(path: "Package.swift", line: 3))
    }

    func testStripsWrappingPunctuationAndTrailing() {
        XCTAssertEqual(
            TerminalPathParser.parse("\"src/App.swift:12\""),
            Match(path: "src/App.swift", line: 12))
        XCTAssertEqual(
            TerminalPathParser.parse("(main.go:7:2)"),
            Match(path: "main.go", line: 7, column: 2))
        XCTAssertEqual(TerminalPathParser.parse("src/x.rs:9."), Match(path: "src/x.rs", line: 9))
    }

    func testParenthesisedLineAndColumn() {
        // tsc: `src/a.ts(12,5): error TS2322`; MSBuild and csc print the same shape.
        XCTAssertEqual(TerminalPathParser.parse("src/a.ts(12,5):"), Match(path: "src/a.ts", line: 12, column: 5))
        XCTAssertEqual(TerminalPathParser.parse("Program.cs(7)"), Match(path: "Program.cs", line: 7))
        XCTAssertNil(TerminalPathParser.parse("foo(1)"), "no slash, no extension: not a path")
        XCTAssertNil(TerminalPathParser.parse("call(a,b)"))
        let line = "src/a.ts(12,5): error TS2322: Type 'x'"
        let onPath = line.distance(from: line.startIndex, to: line.range(of: "a.ts")!.lowerBound)
        XCTAssertEqual(TerminalPathParser.match(in: line, at: onPath), Match(path: "src/a.ts", line: 12, column: 5))
        let onDigits = line.distance(from: line.startIndex, to: line.range(of: "12")!.lowerBound)
        XCTAssertEqual(
            TerminalPathParser.match(in: line, at: onDigits), Match(path: "src/a.ts", line: 12, column: 5),
            "a click inside the parentheses still names the file before them")
    }

    func testRejectsNonPaths() {
        XCTAssertNil(TerminalPathParser.parse("hello"))  // no slash, no extension
        XCTAssertNil(TerminalPathParser.parse("42"))  // just a number
        XCTAssertNil(TerminalPathParser.parse(""))
        XCTAssertNil(TerminalPathParser.parse("::"))
    }

    func testRejectsURLs() {
        XCTAssertNil(TerminalPathParser.parse("https://example.com/a.js"))
        XCTAssertNil(TerminalPathParser.parse("file:///Users/x/y.txt"))
    }

    func testPathWithNoLineButColonInName() {
        // A trailing non-numeric segment isn't a line number.
        XCTAssertEqual(
            TerminalPathParser.parse("weird:name/file.txt"),
            Match(path: "weird:name/file.txt"))
    }

    // MARK: - match(in:at:)

    func testMatchAtColumnInMiddleOfToken() {
        let line = "  Modified src/Editor/View.swift:120:4 — done"
        // Click somewhere inside "src/Editor/View.swift:120:4"
        let col = line.distance(from: line.startIndex, to: line.range(of: "Editor")!.lowerBound)
        XCTAssertEqual(
            TerminalPathParser.match(in: line, at: col),
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

    // MARK: - The forms agents and tools print

    func testAPythonTracebackNamesItsLineAfterTheQuote() {
        let line = #"  File "app/main.py", line 12, in run"#
        XCTAssertEqual(TerminalPathParser.match(in: line, at: 12), .init(path: "app/main.py", line: 12))
        XCTAssertEqual(
            TerminalPathParser.match(in: #"error in "lib/a.rb", line 3, column 9: unexpected"#, at: 12),
            .init(path: "lib/a.rb", line: 3, column: 9))
        XCTAssertEqual(
            TerminalPathParser.match(in: "see src/a.swift, line breaks matter", at: 6), .init(path: "src/a.swift"),
            "prose after a path is not a position")
        XCTAssertEqual(TerminalPathParser.match(in: #"File "a.py", line 12"#, at: 7), .init(path: "a.py", line: 12))
    }

    func testALineAnchorAndARangeGiveTheirFirstLine() {
        XCTAssertEqual(TerminalPathParser.parse("src/Foo.swift#L42"), .init(path: "src/Foo.swift", line: 42))
        XCTAssertEqual(TerminalPathParser.parse("src/Foo.swift#L42C7"), .init(path: "src/Foo.swift", line: 42, column: 7))
        XCTAssertEqual(TerminalPathParser.parse("src/Foo.swift#L42-L50"), .init(path: "src/Foo.swift", line: 42))
        XCTAssertEqual(TerminalPathParser.parse("src/Foo.swift:10-14"), .init(path: "src/Foo.swift", line: 10))
        XCTAssertEqual(
            TerminalPathParser.parse("docs/guide.md#install"), .init(path: "docs/guide.md#install"), "a heading anchor is not a line")
        XCTAssertEqual(
            TerminalPathParser.parse("my-file.swift:7"), .init(path: "my-file.swift", line: 7), "a dash in a name is not a range")
        XCTAssertEqual(TerminalPathParser.parse("a-b/c-d.swift"), .init(path: "a-b/c-d.swift"))
    }

    func testAPrintedPathIsFoundUnderTheWorkingDirectoryThenTheRoots() {
        let cwd = URL(fileURLWithPath: "/repo/packages/app"), root = URL(fileURLWithPath: "/repo")
        let files: Set<String> = ["/repo/packages/app/main.swift", "/repo/src/x.swift", "/repo/a/literal.swift", "/abs/file.c"]
        let isFile: (URL) -> Bool = { files.contains($0.path) }
        func resolved(_ path: String) -> String? {
            TerminalPathParser.resolve(.init(path: path), bases: [cwd, root], isFile: isFile)?.path
        }
        XCTAssertEqual(resolved("main.swift"), "/repo/packages/app/main.swift", "under the working directory first")
        XCTAssertEqual(resolved("src/x.swift"), "/repo/src/x.swift", "an agent names files from the repository's root")
        XCTAssertEqual(resolved("b/src/x.swift"), "/repo/src/x.swift", "a diff header's b/ is not a folder")
        XCTAssertEqual(resolved("a/src/x.swift"), "/repo/src/x.swift")
        XCTAssertEqual(resolved("a/literal.swift"), "/repo/a/literal.swift", "a real folder called a wins over the diff reading")
        XCTAssertEqual(resolved("/abs/file.c"), "/abs/file.c")
        XCTAssertNil(resolved("nowhere.swift"))
        XCTAssertNil(resolved("/abs/missing.c"))
        XCTAssertEqual(TerminalPathParser.candidates(for: "a/"), ["a/"])
    }

    func testAPathCutByTheRightEdgeIsReadWhole() {
        // Width 20: the first two rows are full, so the three are one line.
        let rows = ["edited Sources/App/M", "ainWindowController.", "swift:42 ok", "next line"]
        let full: (String) -> Bool = { $0.count == 20 }
        let (line, column) = TerminalPathParser.logicalLine(rows: rows, row: 1, column: 3, isFull: full)
        XCTAssertEqual(line, "edited Sources/App/MainWindowController.swift:42 ok")
        XCTAssertEqual(column, 23)
        XCTAssertEqual(TerminalPathParser.match(in: line, at: column), .init(path: "Sources/App/MainWindowController.swift", line: 42))
        let alone = TerminalPathParser.logicalLine(rows: rows, row: 3, column: 2, isFull: full)
        XCTAssertEqual(alone.line, "next line")
        XCTAssertEqual(alone.column, 2)
        XCTAssertEqual(
            TerminalPathParser.logicalLine(rows: rows, row: 2, column: 0, isFull: full).line,
            "edited Sources/App/MainWindowController.swift:42 ok")
        XCTAssertEqual(TerminalPathParser.logicalLine(rows: [], row: 0, column: 0, isFull: full).line, "")
    }
}
