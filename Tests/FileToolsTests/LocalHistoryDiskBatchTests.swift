//
//  LocalHistoryDiskBatchTests.swift
//  FileToolsTests
//
//  A disk batch: merging, what is skipped (.git, ignored), each file's "before", roots through links.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import GitKit
@testable import FileTools

/// `LocalHistory.recordDiskBatch(_:limit:)` and `LocalHistoryDiskBatch.merge`.
final class LocalHistoryDiskBatchTests: XCTestCase {
    private var base: URL!
    private var repo: URL!
    private var history: LocalHistory!

    override func setUpWithError() throws {
        // The real path, so the "through a link" case below is the only one that involves a link.
        let temporary = URL(fileURLWithPath: FileManager.default.temporaryDirectory.realPath ?? NSTemporaryDirectory())
        base = temporary.appendingPathComponent("disk-batch-\(UUID().uuidString)", isDirectory: true)
        repo = base.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        history = LocalHistory(root: base.appendingPathComponent("history"), maxEntries: 10, mergeWindow: 10, maxFileSize: 1_000)
        git("init", "-q")
        try write(".gitignore", "build/\n")
        try write("a.txt", "committed\n")
        git("add", "-A")
        git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "first")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: base) }

    private func git(_ arguments: String...) { _ = Git.run(arguments, in: repo) }

    @discardableResult
    private func write(_ name: String, _ text: String) throws -> URL {
        let url = repo.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func batch(_ names: [String], under root: URL? = nil, previous: [String: Data] = [:]) -> LocalHistoryDiskBatch {
        let folder = root ?? repo!
        return LocalHistoryDiskBatch(
            paths: Set(names.map { folder.appendingPathComponent($0).path }), source: .agent, previous: previous,
            ignoreRoots: [folder], repoRoots: [folder])
    }

    private func texts(_ url: URL) -> [String] {
        history.entries(for: url).map { String(decoding: history.data(of: $0, for: url)!, as: UTF8.self) }
    }

    func testAFirstSeenFileKeepsItsCommittedVersionAsTheBefore() throws {
        let file = try write("a.txt", "changed by the agent\n")
        let outcome = history.recordDiskBatch(batch(["a.txt"]))
        XCTAssertEqual(outcome.recorded.map(\.lastPathComponent), ["a.txt"])
        XCTAssertEqual(outcome.previousKept.map(\.lastPathComponent), ["a.txt"])
        XCTAssertEqual(Set(texts(file)), ["committed\n", "changed by the agent\n"])
    }

    func testACapturedBufferBeatsHEAD() throws {
        let file = try write("a.txt", "new\n")
        _ = history.recordDiskBatch(batch(["a.txt"], previous: [file.path: Data("what the tab held\n".utf8)]))
        XCTAssertEqual(Set(texts(file)), ["what the tab held\n", "new\n"])
    }

    func testGitDirectoriesAndRuleIgnoredFilesAreLeftOut() throws {
        let built = try write("build/out.js", "generated\n")
        try write(".git/config.lock", "x\n")
        let kept = try write("src/new.swift", "let x = 1\n")
        let outcome = history.recordDiskBatch(batch(["build/out.js", ".git/config.lock", "src/new.swift"]))
        XCTAssertEqual(outcome.recorded, [kept])
        XCTAssertTrue(history.entries(for: built).isEmpty, "ignored by the .gitignore the cached rules read")
    }

    /// A file git ignores by a rule the cached matcher cannot see, created after the cache was built —
    /// an agent's brand-new output — is caught by asking git now, and counted as skipped.
    func testAFileOnlyGitKnowsIsIgnoredIsAskedOfGitNow() throws {
        try write(".git/info/exclude", "*.log\n")
        _ = IgnoreMatcherCache.shared.matcher(for: repo)  // the cache, built before the file exists
        let log = try write("agent.log", "noise\n")
        let outcome = history.recordDiskBatch(batch(["agent.log"]))
        XCTAssertTrue(history.entries(for: log).isEmpty)
        XCTAssertEqual(outcome.skipped, 1)
    }

    func testARootOpenedThroughALinkStillFindsItsRepository() throws {
        let link = base.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        let file = try write("a.txt", "edited\n")
        // The window names the link; FSEvents name the real path.
        let changes = LocalHistoryDiskBatch(paths: [file.path], source: .agent, previous: [:], ignoreRoots: [link], repoRoots: [link])
        let outcome = history.recordDiskBatch(changes)
        XCTAssertEqual(outcome.previousKept.count, 1, "HEAD found through the link's real path")
    }

    func testAFileNamedThroughALinkStillFindsItsRepository() throws {
        let link = base.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)
        try write("a.txt", "edited\n")
        // The roots are real; the changed path arrives through the link.
        let changes = LocalHistoryDiskBatch(
            paths: [link.appendingPathComponent("a.txt").path], source: .agent, previous: [:], ignoreRoots: [repo], repoRoots: [repo])
        XCTAssertEqual(history.recordDiskBatch(changes).previousKept.count, 1, "matched by the file's real path")
    }

    func testOnlyTheLimitIsExaminedInPathOrder() throws {
        for name in ["c.txt", "a2.txt", "b.txt"] { try write(name, name) }
        let outcome = history.recordDiskBatch(batch(["c.txt", "a2.txt", "b.txt"]), limit: 2)
        XCTAssertEqual(outcome.recorded.map(\.lastPathComponent), ["a2.txt", "b.txt"])
        XCTAssertEqual(outcome.unexamined, 1)
    }

    func testMergingKeepsTheEarlierBeforeAndTheLaterRoots() {
        var waiting = LocalHistoryDiskBatch(
            paths: ["/p/a"], source: .changedOnDisk, previous: ["/p/a": Data("old".utf8)], ignoreRoots: [], repoRoots: [])
        let later = LocalHistoryDiskBatch(
            paths: ["/p/a", "/p/b"], source: .agent, previous: ["/p/a": Data("newer".utf8)], ignoreRoots: [URL(fileURLWithPath: "/p")],
            repoRoots: [URL(fileURLWithPath: "/p")])
        waiting.merge(later)
        XCTAssertEqual(waiting.paths, ["/p/a", "/p/b"])
        XCTAssertEqual(waiting.previous["/p/a"], Data("old".utf8), "the older content is the before")
        XCTAssertEqual(waiting.source, .agent)
        XCTAssertEqual(waiting.repoRoots, [URL(fileURLWithPath: "/p")])
    }

    func testAWaitingBatchStopsGrowingAtItsLimit() {
        var waiting = LocalHistoryDiskBatch(paths: [], source: .agent, previous: [:], ignoreRoots: [], repoRoots: [])
        waiting.merge(
            LocalHistoryDiskBatch(paths: Set((0..<1_500).map { "/p/\($0)" }), source: .agent, previous: [:], ignoreRoots: [], repoRoots: [])
        )
        XCTAssertEqual(waiting.paths.count, LocalHistoryDiskBatch.pendingLimit)
    }
}
