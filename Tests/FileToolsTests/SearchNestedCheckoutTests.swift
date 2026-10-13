//
//  SearchNestedCheckoutTests.swift
//  FileToolsTests
//
//  The search walk switches ignore rules at a nested checkout, as git does: the outer project's
//  rules stop at the nested repository, whose own rules (its .gitignore, its info/exclude) take over.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class SearchNestedCheckoutTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        IgnoreRulesCache.invalidateAll()
        tmp =
            FileManager.default.temporaryDirectory.appendingPathComponent("SearchNested-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        IgnoreRulesCache.invalidateAll()
    }

    private func write(_ text: String, _ path: String) throws {
        let url = tmp.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ args: [String], in dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func walked() -> Set<String> {
        var out: Set<String> = []
        ProjectSearch.walkCandidates(in: tmp, isCancelled: { false }, include: nil) { url, _ in
            out.insert(String(url.standardizedFileURL.path.dropFirst(tmp.path.count + 1)))
            return true
        }
        return out
    }

    func testANestedCheckoutIsJudgedByItsOwnRulesNotTheOuterOnes() throws {
        git(["init", "-q"], in: tmp)
        try write("*.log\n", ".gitignore")
        try write("x", "outer.log")
        try write("x", "outer.txt")
        let nested = tmp.appendingPathComponent("packages/lib", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        git(["init", "-q"], in: nested)
        try write("generated/\n", "packages/lib/.gitignore")
        try write("secret.txt\n", "packages/lib/.git/info/exclude")
        try write("x", "packages/lib/build.log")
        try write("x", "packages/lib/generated/bundle.js")
        try write("x", "packages/lib/secret.txt")
        try write("x", "packages/lib/src/main.c")
        let files = walked()
        XCTAssertFalse(files.contains("outer.log"), "the outer project's rule applies to the outer project")
        XCTAssertTrue(files.contains("outer.txt"))
        XCTAssertTrue(files.contains("packages/lib/build.log"), "the outer *.log stops at the nested checkout, as in git")
        XCTAssertFalse(files.contains("packages/lib/generated/bundle.js"), "the nested checkout's .gitignore applies")
        XCTAssertFalse(files.contains("packages/lib/secret.txt"), "and its own info/exclude, which only its git knows")
        XCTAssertTrue(files.contains("packages/lib/src/main.c"))
    }
}
