//
//  IgnoreNestedRepoTests.swift
//  FileToolsTests
//
//  Tests for the matcher over a checkout nested inside the opened folder: every entry is
//  judged by the deepest git root containing it, as `git check-ignore` in that repository.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for the matcher over a checkout nested inside the opened folder: every entry is
/// judged by the deepest git root containing it, as `git check-ignore` in that repository.
final class IgnoreNestedRepoTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        IgnoreRulesCache.invalidateAll()
        tmp =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("IgnoreNestedRepoTests-\(UUID().uuidString)", isDirectory: true)
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

    /// The outer checkout ignores `dist/` and `*.log`; `nested/` is its own checkout ignoring
    /// `build/` and `.env`; `vendor/` is ignored by the outer and holds a checkout of its own.
    private func makeRepos() throws {
        try git(["init", "-q"], in: tmp)
        try write("dist/\n*.log\nvendor/\n", to: ".gitignore")
        try write("*.tmp\n", to: ".ignore")
        try write("x", to: "outer/dist/y")
        try write("x", to: "outer/src/a")
        try write("x", to: "outer/a.log")
        try write("x", to: "outer/a.tmp")

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try git(["init", "-q"], in: tmp.appendingPathComponent("nested"))
        try write("build/\n.env\n", to: "nested/.gitignore")
        try write("x", to: "nested/build/x")
        try write("x", to: "nested/src/z")
        try write("x", to: "nested/x.log")
        try write("x", to: "nested/.env")
        try write("x", to: "nested/a.tmp")

        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("vendor/lib"), withIntermediateDirectories: true)
        try git(["init", "-q"], in: tmp.appendingPathComponent("vendor/lib"))
        try write("x", to: "vendor/lib/src/q")
    }

    private var nestedRoots: [URL] {
        [tmp.appendingPathComponent("nested"), tmp.appendingPathComponent("vendor/lib")]
    }

    private func isIgnored(_ matcher: IgnoreMatcher, _ relativePath: String, isDirectory: Bool = false) -> Bool {
        matcher.isIgnored(url: tmp.appendingPathComponent(relativePath), isDirectory: isDirectory)
    }

    func testEachEntryIsJudgedByTheDeepestCheckoutContainingIt() throws {
        try makeRepos()
        let matcher = IgnoreMatcher(root: tmp, nestedRoots: nestedRoots)

        // The outer root's own rules, as before.
        XCTAssertTrue(isIgnored(matcher, "outer/dist/y"))
        XCTAssertTrue(isIgnored(matcher, "outer/dist", isDirectory: true))
        XCTAssertTrue(isIgnored(matcher, "outer/a.log"))
        XCTAssertFalse(isIgnored(matcher, "outer/src/a"))

        // The nested checkout answers for everything beneath it.
        XCTAssertTrue(isIgnored(matcher, "nested/build/x"), "the nested .gitignore's build/")
        XCTAssertTrue(isIgnored(matcher, "nested/build", isDirectory: true))
        XCTAssertTrue(isIgnored(matcher, "nested/.env"))
        XCTAssertFalse(isIgnored(matcher, "nested/src/z"))
        XCTAssertFalse(isIgnored(matcher, "nested", isDirectory: true))
        // Git never reads the outer .gitignore inside a nested repository: *.log stops at its door.
        XCTAssertFalse(isIgnored(matcher, "nested/x.log"))

        // A checkout under a directory the outer root ignores is ignored whole.
        XCTAssertTrue(isIgnored(matcher, "vendor/lib/src/q"))
        XCTAssertTrue(isIgnored(matcher, "vendor/lib", isDirectory: true))

        // The .ignore stack flows down through a nested checkout, as ripgrep's does.
        XCTAssertTrue(isIgnored(matcher, "outer/a.tmp"))
        XCTAssertTrue(isIgnored(matcher, "nested/a.tmp"))
    }

    func testNestedRootsCanBeSuppliedAfterConstruction() throws {
        try makeRepos()
        let matcher = IgnoreMatcher(root: tmp)
        XCTAssertEqual(matcher.nestedRoots, [])
        XCTAssertFalse(isIgnored(matcher, "nested/build/x"), "without the list, git reports nested/ as one untracked directory")

        matcher.setNestedRoots(nestedRoots + [tmp, tmp.deletingLastPathComponent(), URL(fileURLWithPath: "/elsewhere")])
        XCTAssertEqual(
            matcher.nestedRoots.map(\.path), [tmp.appendingPathComponent("nested").path, tmp.appendingPathComponent("vendor/lib").path],
            "the root itself and URLs outside it are dropped")
        XCTAssertTrue(isIgnored(matcher, "nested/build/x"))
        XCTAssertFalse(isIgnored(matcher, "nested/src/z"))

        matcher.setNestedRoots([])
        XCTAssertFalse(isIgnored(matcher, "nested/build/x"), "the list is replaced, not merged")
    }

    /// Git as the oracle: an entry is ignored when `git check-ignore`, run in the deepest
    /// repository containing it, says so for it or for any ancestor directory (an ancestor
    /// being judged by its own deepest repository, so a nested root directory is judged by the
    /// outer). `.ignore` files are left out, git does not read them.
    func testParityWithGitCheckIgnoreRunInEachRepository() throws {
        try makeRepos()
        try FileManager.default.removeItem(at: tmp.appendingPathComponent(".ignore"))
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("outer/a.tmp"))
        try FileManager.default.removeItem(at: tmp.appendingPathComponent("nested/a.tmp"))
        let matcher = IgnoreMatcher(root: tmp, nestedRoots: nestedRoots)
        let repos = ["nested", "vendor/lib"]

        func repo(strictlyAbove path: String) -> String {
            repos.filter { path.hasPrefix($0 + "/") }.max { $0.count < $1.count } ?? ""
        }
        func gitIgnored(_ path: String) throws -> Bool {
            let repo = repo(strictlyAbove: path)
            let local = repo.isEmpty ? path : String(path.dropFirst(repo.count + 1))
            let dir = repo.isEmpty ? tmp! : tmp.appendingPathComponent(repo)
            let status = try git(["check-ignore", "-q", "--", local], in: dir)
            XCTAssertTrue(status == 0 || status == 1, "check-ignore \(path) exited \(status)")
            return status == 0
        }
        func oracle(_ path: String) throws -> Bool {
            var ancestor = ""
            for component in path.split(separator: "/") {
                ancestor = ancestor.isEmpty ? String(component) : ancestor + "/" + component
                if try gitIgnored(ancestor) { return true }
            }
            return false
        }

        let entries: [(path: String, isDirectory: Bool)] = [
            ("outer", true), ("outer/dist", true), ("outer/dist/y", false), ("outer/src", true), ("outer/src/a", false),
            ("outer/a.log", false), ("nested", true), ("nested/build", true), ("nested/build/x", false),
            ("nested/src", true), ("nested/src/z", false), ("nested/x.log", false), ("nested/.env", false),
            ("nested/.gitignore", false), ("vendor", true), ("vendor/lib", true), ("vendor/lib/src", true),
            ("vendor/lib/src/q", false), (".gitignore", false),
        ]
        var ignored = 0
        for entry in entries {
            let expected = try oracle(entry.path)
            if expected { ignored += 1 }
            XCTAssertEqual(isIgnored(matcher, entry.path, isDirectory: entry.isDirectory), expected, entry.path)
        }
        XCTAssertEqual(ignored, 10, "the oracle itself sees both repositories' rules")
    }
}
