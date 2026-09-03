//
//  IgnoreGitTests.swift
//  Tests for GitIgnoredSet: the git-backed exact ignored set, exercised against
//  a real, throwaway git repository created in a temp directory.
//

import XCTest
@testable import FileTools

final class IgnoreGitTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("IgnoreGitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tmp.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
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

    func testGitIgnoredSetReportsExactlyWhatGitReports() throws {
        try git(["init"], in: tmp)
        try write("*.log\nbuild/\n", to: ".gitignore")
        try write("hello", to: "a.txt")
        try write("noisy", to: "a.log")
        try write("output", to: "build/output.log")
        try write("keep", to: "build/keep.txt")
        try write("hello2", to: "sub/b.txt")
        try write("noisy2", to: "sub/b.log")

        guard let ignored = GitIgnoredSet.load(root: tmp) else {
            return XCTFail("expected a GitIgnoredSet for a real git work tree")
        }

        // Ignored: a plain ignored file, anything under an ignored directory
        // (including one that doesn't itself match *.log), and a nested ignored file.
        XCTAssertTrue(ignored.isIgnored(relativePath: "a.log", isDirectory: false))
        XCTAssertTrue(ignored.isIgnored(relativePath: "build", isDirectory: true))
        XCTAssertTrue(ignored.isIgnored(relativePath: "build/output.log", isDirectory: false))
        XCTAssertTrue(ignored.isIgnored(relativePath: "build/keep.txt", isDirectory: false))
        XCTAssertTrue(ignored.isIgnored(relativePath: "sub/b.log", isDirectory: false))

        // Not ignored: everything else.
        XCTAssertFalse(ignored.isIgnored(relativePath: "a.txt", isDirectory: false))
        XCTAssertFalse(ignored.isIgnored(relativePath: "sub/b.txt", isDirectory: false))
        XCTAssertFalse(ignored.isIgnored(relativePath: ".gitignore", isDirectory: false))
    }

    func testGitIgnoredSetHonorsNegation() throws {
        try git(["init"], in: tmp)
        try write("*.log\n!important.log\n", to: ".gitignore")
        try write("noisy", to: "a.log")
        try write("keep me", to: "important.log")

        guard let ignored = GitIgnoredSet.load(root: tmp) else {
            return XCTFail("expected a GitIgnoredSet for a real git work tree")
        }
        XCTAssertTrue(ignored.isIgnored(relativePath: "a.log", isDirectory: false))
        XCTAssertFalse(ignored.isIgnored(relativePath: "important.log", isDirectory: false))
    }

    func testGitIgnoredSetReturnsNilOutsideAWorkTree() throws {
        // `tmp` deliberately has no `git init` — not a work tree at all.
        try write("hello", to: "a.txt")
        XCTAssertNil(GitIgnoredSet.load(root: tmp))
    }

    func testGitIgnoredSetReturnsNilForANonexistentRoot() {
        let missing = tmp.appendingPathComponent("does-not-exist")
        XCTAssertNil(GitIgnoredSet.load(root: missing))
    }
}
