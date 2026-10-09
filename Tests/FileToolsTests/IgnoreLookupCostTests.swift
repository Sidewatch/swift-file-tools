//
//  IgnoreLookupCostTests.swift
//  FileToolsTests
//
//  Tests for the cost of one ignore lookup: the path's own ancestors are looked up, the list
//  of ignored directories is never scanned, so thousands of ignored directories cost nothing
//  per row.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for the cost of one ignore lookup: the path's own ancestors are looked up, the list
/// of ignored directories is never scanned, so thousands of ignored directories cost nothing
/// per row.
final class IgnoreLookupCostTests: XCTestCase {

    private static let ignoredDirectoryCount = 5_000
    private static let lookupCount = 1_000
    private static let budget: TimeInterval = 0.05

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    func testGitIgnoredSetAnswersByAncestorNotByScanningTheListing() {
        let directories = Set((0..<Self.ignoredDirectoryCount).map { "ignored\($0)" })
        let set = GitIgnoredSet(files: ["top.log", "src/gen/out.swift"], directories: directories)

        XCTAssertTrue(set.isIgnored(relativePath: "ignored42", isDirectory: true))
        XCTAssertTrue(set.isIgnored(relativePath: "ignored42/sub/deep/file.txt", isDirectory: false))
        XCTAssertTrue(set.isIgnored(relativePath: "top.log", isDirectory: false))
        XCTAssertTrue(set.isIgnored(relativePath: "src/gen/out.swift", isDirectory: false))
        XCTAssertFalse(set.isIgnored(relativePath: "ignored42x/file.txt", isDirectory: false), "a prefix is not an ancestor")
        XCTAssertFalse(
            set.isIgnored(relativePath: "src/ignored42/file.txt", isDirectory: false),
            "a listed name deeper down is not the listed directory")
        XCTAssertFalse(set.isIgnored(relativePath: "src/gen", isDirectory: true))
        XCTAssertFalse(set.isIgnored(relativePath: "src/a/b/c/d/e.swift", isDirectory: false))

        // Misses are the worst case: every ancestor is looked up and none is listed.
        let paths = (0..<Self.lookupCount).map { "src/module\($0 % 7)/sub/deep/file\($0).swift" }
        var hits = 0
        let elapsed = milliseconds {
            for path in paths where set.isIgnored(relativePath: path, isDirectory: false) { hits += 1 }
        }
        XCTAssertEqual(hits, 0)
        print("GitIgnoredSet: \(Self.ignoredDirectoryCount) ignored directories, \(Self.lookupCount) lookups: \(elapsed) ms")
        XCTAssertLessThan(elapsed, Self.budget * 1000, "a lookup must not scan the ignored directories")
    }

    func testMatcherLookupCostOverARealCheckoutWithThousandsOfIgnoredDirectories() throws {
        IgnoreRulesCache.invalidateAll()
        defer { IgnoreRulesCache.invalidateAll() }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IgnoreLookupCostTests-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        try "ignored*/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        for i in 0..<Self.ignoredDirectoryCount {
            let dir = root.appendingPathComponent("ignored\(i)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: dir.appendingPathComponent("f"))
        }
        try fm.createDirectory(at: root.appendingPathComponent("src/module/sub/deep"), withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", root.path, "init", "-q"]
        try process.run()
        process.waitUntilExit()

        let matcher = IgnoreMatcher(root: root)
        XCTAssertTrue(matcher.isIgnored(url: root.appendingPathComponent("ignored4999/f"), isDirectory: false))
        XCTAssertFalse(matcher.isIgnored(url: root.appendingPathComponent("src/module/sub/deep/a.swift"), isDirectory: false))

        let urls = (0..<Self.lookupCount).map { root.appendingPathComponent("src/module/sub/deep/file\($0).swift") }
        var hits = 0
        let elapsed = milliseconds {
            for url in urls where matcher.isIgnored(url: url, isDirectory: false) { hits += 1 }
        }
        XCTAssertEqual(hits, 0)
        print("IgnoreMatcher: \(Self.ignoredDirectoryCount) ignored directories, \(Self.lookupCount) lookups: \(elapsed) ms")
        XCTAssertLessThan(elapsed, Self.budget * 1000, "a row must not scan the ignored directories")
    }
}
