//
//  IgnoreReasonTests.swift
//  FileToolsTests
//
//  Tests for naming the rule that ignores a path: git's own answer in a checkout, the `.ignore`
//  stack's last matching pattern elsewhere.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for naming the rule that ignores a path: git's own answer in a checkout, the `.ignore`
/// stack's last matching pattern elsewhere.
final class IgnoreReasonTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        IgnoreRulesCache.invalidateAll()
        tmp =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("IgnoreReasonTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        IgnoreRulesCache.invalidateAll()
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tmp.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func git(_ arguments: [String], in directory: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func url(_ relativePath: String) -> URL { tmp.appendingPathComponent(relativePath) }

    // MARK: - git check-ignore output

    func testOutputGivesTheSourceLineAndPattern() {
        XCTAssertEqual(
            GitCheckIgnoreOutput.reason(from: ".gitignore\u{0}2\u{0}build/\u{0}build/a.o\u{0}"),
            IgnoreReason(source: ".gitignore", line: 2, pattern: "build/"))
    }

    func testOutputFromANestedCheckoutReadsFromTheScanRoot() {
        XCTAssertEqual(
            GitCheckIgnoreOutput.reason(from: ".gitignore\u{0}1\u{0}*.log\u{0}x.log\u{0}", prefix: "nested")?.source,
            "nested/.gitignore")
        XCTAssertEqual(
            GitCheckIgnoreOutput.reason(from: "/Users/someone/.gitignore_global\u{0}4\u{0}.DS_Store\u{0}.DS_Store\u{0}", prefix: "nested")?
                .source,
            "/Users/someone/.gitignore_global", "an absolute source is left alone")
    }

    func testOutputThatPutsThePathBackOrSaysNothingIsNoReason() {
        XCTAssertNil(GitCheckIgnoreOutput.reason(from: ".gitignore\u{0}4\u{0}!keep.log\u{0}keep.log\u{0}"))
        XCTAssertNil(GitCheckIgnoreOutput.reason(from: ""))
        XCTAssertNil(GitCheckIgnoreOutput.reason(from: ".gitignore\u{0}x\u{0}build/\u{0}build\u{0}"))
        XCTAssertNil(GitCheckIgnoreOutput.reason(from: "\u{0}\u{0}\u{0}path\u{0}"), "git -n's no-match record")
    }

    // MARK: - The .ignore stack

    func testTheStackNamesTheLastMatchWithItsFileAndRealLine() {
        let root = IgnoreFile(text: "# generated\n\n*.gen\n", directory: "", name: ".ignore")
        let deeper = IgnoreFile(text: "tmp/\n\n# again\nschema.gen\n", directory: "src", name: ".rgignore")
        let stack = IgnoreStack(files: [root, deeper])
        XCTAssertEqual(
            stack.reason(relativePath: "src/schema.gen", isDirectory: false),
            IgnoreReason(source: "src/.rgignore", line: 4, pattern: "schema.gen"))
        XCTAssertEqual(
            stack.reason(relativePath: "other.gen", isDirectory: false), IgnoreReason(source: ".ignore", line: 3, pattern: "*.gen"))
        XCTAssertNil(stack.reason(relativePath: "src/main.swift", isDirectory: false))
    }

    func testAPutBackRuleIsNoReason() {
        let stack = IgnoreStack(files: [IgnoreFile(text: "*.log\n!keep.log\n", directory: "", name: ".ignore")])
        XCTAssertNil(stack.reason(relativePath: "keep.log", isDirectory: false))
        XCTAssertEqual(stack.reason(relativePath: "x.log", isDirectory: false)?.line, 1)
    }

    // MARK: - The matcher

    func testInACheckoutGitNamesTheRuleForAFileInsideAnIgnoredFolder() throws {
        try git(["init", "-q"], in: tmp)
        try write("# build output\nnode_modules/\nbuild/\n*.log\n!keep.log\n", to: ".gitignore")
        try write("x", to: "build/sub/a.o")
        try write("x", to: "logs/x.log")
        try write("x", to: "logs/keep.log")
        try write("x", to: "src/main.swift")
        try write("x", to: "app/[id]/page.log")
        let matcher = IgnoreMatcher(root: tmp)
        XCTAssertEqual(
            matcher.reason(url: url("app/[id]/page.log"), isDirectory: false),
            IgnoreReason(source: ".gitignore", line: 4, pattern: "*.log"),
            "a name with glob characters is answered for itself")
        XCTAssertTrue(matcher.isIgnored(url: url("app"), isDirectory: true), "git calls a folder of nothing but ignored files ignored")
        XCTAssertNil(matcher.reason(url: url("app"), isDirectory: true), "and no rule names it")
        XCTAssertEqual(
            matcher.reason(url: url("build/sub/a.o"), isDirectory: false), IgnoreReason(source: ".gitignore", line: 3, pattern: "build/"))
        XCTAssertEqual(matcher.reason(url: url("build"), isDirectory: true), IgnoreReason(source: ".gitignore", line: 3, pattern: "build/"))
        XCTAssertEqual(matcher.reason(url: url("logs/x.log"), isDirectory: false)?.pattern, "*.log")
        XCTAssertNil(matcher.reason(url: url("logs/keep.log"), isDirectory: false))
        XCTAssertNil(matcher.reason(url: url("src/main.swift"), isDirectory: false))
    }

    func testInfoExcludeIsNamedAndATrackedFileIsNotIgnored() throws {
        try git(["init", "-q"], in: tmp)
        try write("*.zqx\n", to: ".gitignore")
        try write("\n# local\nscratch-zqv.txt\n", to: ".git/info/exclude")
        try write("x", to: "scratch-zqv.txt")
        try write("x", to: "kept.zqx")
        try git(["add", "-f", "kept.zqx"], in: tmp)
        let matcher = IgnoreMatcher(root: tmp)
        XCTAssertEqual(
            matcher.reason(url: url("scratch-zqv.txt"), isDirectory: false),
            IgnoreReason(source: ".git/info/exclude", line: 3, pattern: "scratch-zqv.txt"))
        XCTAssertNil(matcher.reason(url: url("kept.zqx"), isDirectory: false), "git ignores no tracked file, so the tree does not dim it")
    }

    func testANestedCheckoutsRuleReadsFromTheScanRoot() throws {
        try git(["init", "-q"], in: tmp)
        try write("dist/\n", to: ".gitignore")
        try FileManager.default.createDirectory(at: url("nested"), withIntermediateDirectories: true)
        try git(["init", "-q"], in: url("nested"))
        try write("\ncoverage/\n", to: "nested/.gitignore")
        try write("x", to: "nested/coverage/lcov.info")
        let matcher = IgnoreMatcher(root: tmp, nestedRoots: [url("nested")])
        XCTAssertEqual(
            matcher.reason(url: url("nested/coverage/lcov.info"), isDirectory: false),
            IgnoreReason(source: "nested/.gitignore", line: 2, pattern: "coverage/"))
    }

    func testInACheckoutAnIgnoreFileRuleIsNamedFromTheStack() throws {
        try git(["init", "-q"], in: tmp)
        try write("dist/\n", to: ".gitignore")
        try write("x", to: "src/.ignore")
        try write("fixtures/\n*.snap\n", to: "src/.ignore")
        try write("x", to: "src/view.snap")
        let matcher = IgnoreMatcher(root: tmp)
        XCTAssertEqual(
            matcher.reason(url: url("src/view.snap"), isDirectory: false), IgnoreReason(source: "src/.ignore", line: 2, pattern: "*.snap"))
    }

    func testInAPlainFolderTheGitignoreIsReadByTheStack() throws {
        try write("\n\n*.cache\n", to: ".gitignore")
        try write("x", to: "a/b.cache")
        let matcher = IgnoreMatcher(root: tmp)
        XCTAssertEqual(
            matcher.reason(url: url("a/b.cache"), isDirectory: false), IgnoreReason(source: ".gitignore", line: 3, pattern: "*.cache"))
        XCTAssertTrue(matcher.isIgnored(url: url("a/b.cache"), isDirectory: false))
        XCTAssertFalse(matcher.isIgnored(url: url("a"), isDirectory: true))
    }
}
