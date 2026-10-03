//
//  SearchStreamingAndTargetedTests.swift
//  FileToolsTests
//
//  Streaming search results, replacing exactly the shown matches, and include globs.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Streaming search results, replacing exactly the shown matches, and include globs.
final class SearchStreamingAndTargetedTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SearchStreaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func write(_ text: String, _ path: String) throws -> URL {
        let url = tmp.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testEachMatchingFileIsReportedAsItIsFound() throws {
        _ = try write("needle one\n", "a.txt")
        _ = try write("nothing\n", "b.txt")
        _ = try write("needle two\nneedle three\n", "c/d.txt")
        var streamed: [String] = []
        let all = ProjectSearch.search(
            query: "needle", in: tmp, caseSensitive: false, regex: false, isCancelled: { false },
            onFile: { streamed.append($0.url.lastPathComponent) })
        XCTAssertEqual(Set(streamed), ["a.txt", "d.txt"], "every matching file, and only those")
        XCTAssertEqual(all.count, 2)
        var listed: [String] = []
        _ = ProjectSearch.search(
            query: "needle", files: [tmp.appendingPathComponent("a.txt")], caseSensitive: false, regex: false,
            isCancelled: { false }, onFile: { listed.append($0.url.lastPathComponent) })
        XCTAssertEqual(listed, ["a.txt"])
    }

    func testReplaceMatchesRewritesOnlyTheShownMatches() throws {
        let url = try write("let a = 1\nlet a = 2\nlet a = 3\n", "x.swift")
        let found = ProjectSearch.search(query: "a", files: [url], caseSensitive: true, regex: false, isCancelled: { false })
        // Keep only the second line's match: the person dismissed the other two.
        let shown = [SearchFileResult(url: url, matches: found[0].matches.filter { $0.line == 2 })]
        let dry = ProjectSearch.replaceMatches(shown, query: "a", caseSensitive: true, regex: false, replacement: "b", commit: false)
        XCTAssertEqual(dry.replacements, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "let a = 1\nlet a = 2\nlet a = 3\n", "a dry run writes nothing")
        let done = ProjectSearch.replaceMatches(shown, query: "a", caseSensitive: true, regex: false, replacement: "b", commit: true)
        XCTAssertEqual(done.replacements, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "let a = 1\nlet b = 2\nlet a = 3\n")
    }

    func testReplaceMatchesSkipsALineThatChangedSinceTheSearch() throws {
        let url = try write("value\n", "y.txt")
        let found = ProjectSearch.search(query: "value", files: [url], caseSensitive: true, regex: false, isCancelled: { false })
        try "changed value\n".write(to: url, atomically: true, encoding: .utf8)
        let s = ProjectSearch.replaceMatches(found, query: "value", caseSensitive: true, regex: false, replacement: "x", commit: true)
        XCTAssertEqual(s.replacements, 0)
        XCTAssertEqual(s.filesFailed, 1)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "changed value\n")
    }

    func testIncludeGlobsMatchNamesAnywhereAndPathsFromTheRoot() {
        let pred = IncludeGlobs.predicate("*.php, src/**/*.ts", roots: [tmp])
        XCTAssertNotNil(pred)
        guard let pred else { return }
        XCTAssertTrue(pred(tmp.appendingPathComponent("deep/down/index.PHP")), "a name pattern matches at any depth, any case")
        XCTAssertTrue(pred(tmp.appendingPathComponent("src/app/main.ts")))
        XCTAssertTrue(pred(tmp.appendingPathComponent("src/main.ts")), "**/ includes no folder at all")
        XCTAssertFalse(pred(tmp.appendingPathComponent("lib/main.ts")))
        XCTAssertNil(IncludeGlobs.predicate("  ,  ", roots: [tmp]), "an empty field filters nothing")
    }

    func testOldIgnoreRulesAreServedAtOnceWhileTheyRefresh() throws {
        _ = try write("needle\n", "a.txt")
        let before = IgnoreRulesCache.lifetime
        defer { IgnoreRulesCache.lifetime = before }
        IgnoreRulesCache.invalidate(root: tmp)
        _ = IgnoreRulesCache.rules(for: tmp)  // the first load runs now
        IgnoreRulesCache.lifetime = 0  // every entry is old from here on
        let generation = IgnoreRulesCache.generation
        let t0 = ProcessInfo.processInfo.systemUptime
        _ = IgnoreRulesCache.rules(for: tmp)
        let elapsed = ProcessInfo.processInfo.systemUptime - t0
        XCTAssertLessThan(elapsed, 0.02, "an old set is returned without waiting for the reload")
        let deadline = Date(timeIntervalSinceNow: 5)
        while IgnoreRulesCache.generation == generation, Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertNotEqual(IgnoreRulesCache.generation, generation, "and a fresh set lands in the background")
    }

    func testAnInvalidatedRootStillLoadsItsNewRulesBeforeTheWalk() throws {
        _ = try write("needle\n", "keep.txt")
        _ = try write("needle\n", "drop.log")
        IgnoreRulesCache.invalidate(root: tmp)
        XCTAssertEqual(ProjectSearch.search(query: "needle", in: tmp, caseSensitive: false, regex: false, isCancelled: { false }).count, 2)
        _ = try write("*.log\n", ".gitignore")
        IgnoreRulesCache.invalidate(root: tmp)
        let names = ProjectSearch.search(query: "needle", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
            .map { $0.url.lastPathComponent }
        XCTAssertEqual(names, ["keep.txt"])
    }
}
