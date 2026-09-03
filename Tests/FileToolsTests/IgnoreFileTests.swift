//
//  IgnoreFileTests.swift
//  Table-driven coverage of gitignore pattern semantics (IgnorePattern/IgnoreFile)
//  and cross-file precedence (IgnoreStack), following
//  https://git-scm.com/docs/gitignore's PATTERN FORMAT section case by case,
//  plus a few direct API-shape checks.
//

import XCTest
@testable import FileTools

final class IgnoreFileTests: XCTestCase {

    /// One matching scenario: either a single root-level ignore file (`gitignore`)
    /// or an explicit list of `(directory, text)` files pushed onto an
    /// ``IgnoreStack`` in order (root to leaf).
    private struct Case {
        let name: String
        let files: [(directory: String, text: String)]
        let path: String
        let isDirectory: Bool
        let expected: Bool
        let file: StaticString
        let line: UInt

        init(_ name: String, gitignore: String, path: String, isDirectory: Bool = false,
             expected: Bool, file: StaticString = #filePath, line: UInt = #line) {
            self.init(name, files: [("", gitignore)], path: path, isDirectory: isDirectory,
                      expected: expected, file: file, line: line)
        }

        init(_ name: String, files: [(directory: String, text: String)], path: String,
             isDirectory: Bool = false, expected: Bool,
             file: StaticString = #filePath, line: UInt = #line) {
            self.name = name
            self.files = files
            self.path = path
            self.isDirectory = isDirectory
            self.expected = expected
            self.file = file
            self.line = line
        }
    }

    private static let cases: [Case] = [

        // MARK: Comments & blank lines

        Case("comment line contributes no rule",
             gitignore: "#foo\n", path: "foo", expected: false),
        Case("escaped hash matches a literal #-prefixed name",
             gitignore: "\\#name\n", path: "#name", expected: true),
        Case("blank line is just a separator, not a pattern",
             gitignore: "\n\nfoo.log\n\n", path: "foo.log", expected: true),
        Case("whitespace-only line contributes no rule",
             gitignore: "   \nfoo\n", path: "foo", expected: true),

        // MARK: Trailing spaces

        Case("unescaped trailing spaces are trimmed",
             gitignore: "foo   \n", path: "foo", expected: true),
        Case("trimmed pattern does not match the untrimmed literal name",
             gitignore: "foo   \n", path: "foo   ", expected: false),
        Case("escaped trailing space is kept literally",
             gitignore: "foo\\ \n", path: "foo ", expected: true),
        Case("escaped-trailing-space pattern does not match the bare name",
             gitignore: "foo\\ \n", path: "foo", expected: false),

        // MARK: Negation

        Case("negation re-includes a previously excluded file",
             gitignore: "*.log\n!important.log\n", path: "important.log", expected: false),
        Case("negation does not affect non-matching files",
             gitignore: "*.log\n!important.log\n", path: "other.log", expected: true),
        Case("escaped leading ! is a literal character",
             gitignore: "\\!important!.txt\n", path: "!important!.txt", expected: true),
        Case("escaped-! pattern does not match without the literal !",
             gitignore: "\\!important!.txt\n", path: "important!.txt", expected: false),

        // MARK: Anchoring — leading slash

        Case("leading slash anchors to the ignore file's directory",
             gitignore: "/foo\n", path: "foo", expected: true),
        Case("leading-slash pattern does not match a nested file of the same name",
             gitignore: "/foo\n", path: "sub/foo", expected: false),
        Case("no leading slash matches at any depth",
             gitignore: "foo\n", path: "sub/foo", expected: true),

        // MARK: Anchoring — interior slash

        Case("interior slash anchors the whole pattern",
             gitignore: "foo/bar\n", path: "foo/bar", expected: true),
        Case("anchored interior-slash pattern does not match nested under another dir",
             gitignore: "foo/bar\n", path: "x/foo/bar", expected: false),

        // MARK: Directory-only trailing slash — the doc/frotz example

        Case("doc/frotz/ matches the directory directly under doc",
             gitignore: "doc/frotz/\n", path: "doc/frotz", isDirectory: true, expected: true),
        Case("doc/frotz/ does not match frotz nested one level deeper",
             gitignore: "doc/frotz/\n", path: "a/doc/frotz", isDirectory: true, expected: false),
        Case("frotz/ matches frotz at the top",
             gitignore: "frotz/\n", path: "frotz", isDirectory: true, expected: true),
        Case("frotz/ matches frotz at any depth",
             gitignore: "frotz/\n", path: "a/frotz", isDirectory: true, expected: true),
        Case("a trailing-slash pattern never matches a file",
             gitignore: "frotz/\n", path: "frotz", isDirectory: false, expected: false),

        // MARK: `*` wildcard

        Case("* matches within one path segment",
             gitignore: "/a*z\n", path: "abz", expected: true),
        Case("* does not cross a slash",
             gitignore: "/a*z\n", path: "a/z", expected: false),
        Case("unanchored * matches at any depth",
             gitignore: "*.log\n", path: "build/output.log", expected: true),

        // MARK: `?` wildcard

        Case("? matches exactly one character",
             gitignore: "?ile.txt\n", path: "file.txt", expected: true),
        Case("? does not match two characters",
             gitignore: "?ile.txt\n", path: "fiile.txt", expected: false),
        Case("? does not match zero characters",
             gitignore: "?ile.txt\n", path: "ile.txt", expected: false),

        // MARK: `[...]` character classes

        Case("character range class matches",
             gitignore: "[a-z]*.txt\n", path: "abc.txt", expected: true),
        Case("character range class is case-sensitive",
             gitignore: "[a-z]*.txt\n", path: "ABC.txt", expected: false),
        Case("character range class rejects an out-of-range leading character",
             gitignore: "[a-z]*.txt\n", path: "1bc.txt", expected: false),
        Case("negated class matches outside the range",
             gitignore: "[!a-z]*.txt\n", path: "1bc.txt", expected: true),
        Case("negated class rejects inside the range",
             gitignore: "[!a-z]*.txt\n", path: "abc.txt", expected: false),

        // MARK: Leading `**/`

        Case("leading **/ matches at the top",
             gitignore: "**/foo\n", path: "foo", expected: true),
        Case("leading **/ matches one level down",
             gitignore: "**/foo\n", path: "a/foo", expected: true),
        Case("leading **/ matches many levels down",
             gitignore: "**/foo\n", path: "a/b/foo", expected: true),
        Case("leading **/ requires foo to be the last component",
             gitignore: "**/foo\n", path: "a/foo/b", expected: false),
        Case("**/foo/bar matches bar directly under any foo",
             gitignore: "**/foo/bar\n", path: "x/foo/bar", expected: true),
        Case("**/foo/bar does not match a differently nested bar",
             gitignore: "**/foo/bar\n", path: "foo/x/bar", expected: false),

        // MARK: Trailing `/**`

        Case("trailing /** does not match the directory itself",
             gitignore: "abc/**\n", path: "abc", isDirectory: true, expected: false),
        Case("trailing /** matches a direct child",
             gitignore: "abc/**\n", path: "abc/x", expected: true),
        Case("trailing /** matches at infinite depth",
             gitignore: "abc/**\n", path: "abc/x/y", expected: true),
        Case("trailing /** does not match outside abc",
             gitignore: "abc/**\n", path: "other/x", expected: false),

        // MARK: Middle `/**/`

        Case("a/**/b matches with zero directories between",
             gitignore: "a/**/b\n", path: "a/b", expected: true),
        Case("a/**/b matches with one directory between",
             gitignore: "a/**/b\n", path: "a/x/b", expected: true),
        Case("a/**/b matches with several directories between",
             gitignore: "a/**/b\n", path: "a/x/y/b", expected: true),
        Case("a/**/b does not match without a trailing b",
             gitignore: "a/**/b\n", path: "a/c", expected: false),

        // MARK: Consecutive-asterisk fallback

        Case("consecutive asterisks not next to a slash act as a single *",
             gitignore: "a**b\n", path: "aXYb", expected: true),
        Case("bare ** with no adjacent slash matches like a single *",
             gitignore: "**\n", path: "anything.txt", expected: true),
        Case("bare ** still only matches the last path component",
             gitignore: "**\n", path: "deep/nested/thing.txt", expected: true),

        // MARK: Cross-file precedence (IgnoreStack)

        Case("a deeper file's negation overrides a shallower exclude",
             files: [("", "*.log\n"), ("sub", "!keep.log\n")],
             path: "sub/keep.log", expected: false),
        Case("a deeper file with no opinion leaves the shallower verdict standing",
             files: [("", "*.log\n"), ("sub", "!keep.log\n")],
             path: "sub/other.log", expected: true),
        Case("a deeper file's exclude overrides a shallower negation outright",
             files: [("", "!important.log\n"), ("sub", "*.log\n")],
             path: "sub/important.log", expected: true),
        Case("a later file at the same directory level wins over an earlier one",
             files: [("", "*.log\n"), ("", "!keep.log\n")],
             path: "keep.log", expected: false),

        // MARK: Excluded directory (contract building block — the full
        // "negation can't reach inside" proof is IgnoreWalkTests, since that
        // needs an actual pruning walk, not a single isIgnored call).

        Case("an excluded directory is itself flagged ignored, which is what a walker prunes on",
             files: [("", "build/\n!build/keep.txt\n")],
             path: "build", isDirectory: true, expected: true),
    ]

    func testGitignoreSemantics() {
        XCTAssertGreaterThanOrEqual(Self.cases.count, 40, "expected at least 40 table cases")
        for c in Self.cases {
            var stack = IgnoreStack()
            for (directory, text) in c.files {
                stack.push(IgnoreFile(text: text, directory: directory))
            }
            let result = stack.isIgnored(relativePath: c.path, isDirectory: c.isDirectory)
            XCTAssertEqual(result, c.expected, c.name, file: c.file, line: c.line)
        }
    }

    // MARK: - Direct API-shape checks (not part of the case table)

    func testIgnorePatternFlags() {
        XCTAssertEqual(IgnorePattern(line: "*.log")?.negated, false)
        XCTAssertEqual(IgnorePattern(line: "!*.log")?.negated, true)
        XCTAssertEqual(IgnorePattern(line: "build/")?.directoryOnly, true)
        XCTAssertEqual(IgnorePattern(line: "build")?.directoryOnly, false)
        XCTAssertEqual(IgnorePattern(line: "/root")?.anchored, true)
        XCTAssertEqual(IgnorePattern(line: "foo/bar")?.anchored, true)
        XCTAssertEqual(IgnorePattern(line: "*.log")?.anchored, false)
        XCTAssertEqual(IgnorePattern(line: "#comment"), nil)
        XCTAssertEqual(IgnorePattern(line: ""), nil)
        XCTAssertEqual(IgnorePattern(line: "abc\\")?.matches(path: "abc\\", isDirectory: false), false,
                        "a trailing unescaped backslash is an invalid pattern that never matches")
    }

    func testIgnoreFileNormalizesDirectorySlashes() {
        XCTAssertEqual(IgnoreFile(text: "", directory: "").directory, "")
        XCTAssertEqual(IgnoreFile(text: "", directory: "/sub/").directory, "sub")
        XCTAssertEqual(IgnoreFile(text: "", directory: "sub/dir").directory, "sub/dir")
    }

    func testIgnoreFileNamesPrecedenceOrder() {
        XCTAssertEqual(IgnoreFileNames.orderedNames, [".gitignore", ".ignore", ".rgignore", ".fdignore"])
    }

    func testIgnoreStackAppendingIsValueSemantics() {
        let base = IgnoreStack()
        let extended = base.appending(IgnoreFile(text: "*.log\n", directory: ""))
        XCTAssertTrue(base.isEmpty)
        XCTAssertFalse(extended.isEmpty)
        XCTAssertFalse(base.isIgnored(relativePath: "a.log", isDirectory: false))
        XCTAssertTrue(extended.isIgnored(relativePath: "a.log", isDirectory: false))
    }

    func testIgnoreStackPushPop() {
        var stack = IgnoreStack()
        stack.push(IgnoreFile(text: "*.log\n", directory: ""))
        XCTAssertTrue(stack.isIgnored(relativePath: "a.log", isDirectory: false))
        let popped = stack.pop()
        XCTAssertNotNil(popped)
        XCTAssertFalse(stack.isIgnored(relativePath: "a.log", isDirectory: false))
        XCTAssertNil(stack.pop())
    }
}
