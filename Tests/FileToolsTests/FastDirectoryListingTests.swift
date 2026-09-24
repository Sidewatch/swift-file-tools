//
//  FastDirectoryListingTests.swift
//  FileToolsTests
//
//  The listing replaces a `FileManager` call that was 50× slower, so these pin the behaviour
//  that has to survive the swap — especially the `d_type` edge cases the fast path skips over.
//
//  Created by David Sherlock on 8/1/26.
//

import XCTest
@testable import FileTools

/// The listing replaces a `FileManager` call that was 50× slower, so these pin the
/// behaviour that has to survive the swap — especially the `d_type` edge cases the
/// fast path skips over.
final class FastDirectoryListingTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fdl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func file(_ name: String) throws {
        try Data("x".utf8).write(to: root.appendingPathComponent(name))
    }
    private func dir(_ name: String) throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent(name),
                                                withIntermediateDirectories: true)
    }
    private func names(_ entries: [FastDirectoryListing.Entry]) -> [String] {
        entries.map { $0.url.lastPathComponent }
    }

    // MARK: - contains(in:where:)

    func testContainsStopsAtTheFirstHitAndSeesTheType() throws {
        try file("a.txt"); try file("b.png"); try dir("pics")
        var seen: [String] = []
        let hit = FastDirectoryListing.contains(in: root) { name, isDir, _ in
            seen.append(name)
            return !isDir && name.hasSuffix(".png")
        }
        XCTAssertTrue(hit)
        XCTAssertTrue(seen.contains("b.png"))
        XCTAssertFalse(FastDirectoryListing.contains(in: root) { _, isDir, _ in isDir && false })
        XCTAssertTrue(FastDirectoryListing.contains(in: root) { name, isDir, _ in isDir && name == "pics" })
    }

    /// A symlink is reported as one, resolved or dangling, so a caller can agree with a listing
    /// that drops links (the gallery's does); a dangling link is neither a directory nor a file.
    func testContainsReportsSymbolicLinks() throws {
        try file("real.png")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.png"), withDestinationURL: root.appendingPathComponent("real.png"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("gone.jpg"), withDestinationURL: root.appendingPathComponent("missing.jpg"))
        var links: [String] = [], plain: [String] = []
        _ = FastDirectoryListing.contains(in: root) { name, isDir, isLink in
            if isLink { links.append(name) } else if !isDir { plain.append(name) }
            return false
        }
        XCTAssertEqual(Set(links), ["alias.png", "gone.jpg"])
        XCTAssertEqual(plain, ["real.png"])
        XCTAssertTrue(FastDirectoryListing.contains(in: root) { name, isDir, isLink in !isDir && !isLink && name.hasSuffix(".png") })
        XCTAssertFalse(FastDirectoryListing.contains(in: root) { name, isDir, isLink in !isDir && !isLink && name.hasSuffix(".jpg") })
    }

    func testContainsHonoursHiddenAndSkippedNamesAndAMissingFolder() throws {
        try file(".secret.png"); try file("node_modules")
        XCTAssertFalse(FastDirectoryListing.contains(in: root) { name, _, _ in name.hasSuffix(".png") })
        XCTAssertTrue(FastDirectoryListing.contains(in: root, includeHidden: true) { name, _, _ in name.hasSuffix(".png") })
        XCTAssertFalse(FastDirectoryListing.contains(in: root, skipping: ["node_modules"]) { name, _, _ in name == "node_modules" })
        XCTAssertFalse(FastDirectoryListing.contains(in: root.appendingPathComponent("nope")) { _, _, _ in true })
    }

    /// The reason the scan exists: `list` sorts, and on ten thousand entries that is the
    /// cost — a gate on a right-click cannot pay it. A no-hit scan (every entry visited)
    /// must stay under 50 ms; the sorted listing of the same folder measures over 100.
    func testContainsAnswersTenThousandEntriesInMilliseconds() throws {
        for i in 0..<10_000 { try file("f\(i).txt") }
        let t0 = Date()
        let any = FastDirectoryListing.contains(in: root) { name, _, _ in name.hasSuffix(".png") }
        let ms = Date().timeIntervalSince(t0) * 1000
        XCTAssertFalse(any)
        XCTAssertLessThan(ms, 50, "a no-hit scan of 10,000 entries took \(ms) ms")
    }

    func testDirectoriesSortBeforeFiles() throws {
        try file("a.txt"); try file("z.txt"); try dir("mid"); try dir("aaa")
        XCTAssertEqual(names(FastDirectoryListing.list(root)), ["aaa", "mid", "a.txt", "z.txt"])
    }

    /// Finder order: `file2` before `file10`. A plain `<` would invert these.
    func testNaturalNumericOrdering() throws {
        for n in ["file10.txt", "file2.txt", "file1.txt"] { try file(n) }
        XCTAssertEqual(names(FastDirectoryListing.list(root)), ["file1.txt", "file2.txt", "file10.txt"])
    }

    func testCaseInsensitiveOrdering() throws {
        try file("Banana.txt"); try file("apple.txt"); try file("Cherry.txt")
        XCTAssertEqual(names(FastDirectoryListing.list(root)), ["apple.txt", "Banana.txt", "Cherry.txt"])
    }

    func testHiddenFilesExcludedByDefaultAndIncludedOnRequest() throws {
        try file("visible.txt"); try file(".hidden")
        XCTAssertEqual(names(FastDirectoryListing.list(root)), ["visible.txt"])
        XCTAssertEqual(names(FastDirectoryListing.list(root, includeHidden: true)).sorted(),
                       [".hidden", "visible.txt"])
    }

    func testSkippedNamesDropped() throws {
        try dir("node_modules"); try dir("src"); try file("index.js")
        XCTAssertEqual(names(FastDirectoryListing.list(root, skipping: ["node_modules"])),
                       ["src", "index.js"])
    }

    /// `.` and `..` are real readdir entries and must never surface.
    func testDotEntriesNeverAppear() throws {
        try file("a.txt")
        XCTAssertFalse(names(FastDirectoryListing.list(root, includeHidden: true)).contains("."))
        XCTAssertFalse(names(FastDirectoryListing.list(root, includeHidden: true)).contains(".."))
    }

    /// The case the `d_type` fast path can't answer: a symlink reports `DT_LNK`, so
    /// it falls back to `stat`. A link to a directory must still be a directory, or
    /// it becomes un-expandable in the tree — and `node_modules/.bin` is all links.
    func testSymlinkToDirectoryReportsAsDirectory() throws {
        try dir("real"); try file("plain.txt")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link-to-dir"),
                                                   withDestinationURL: root.appendingPathComponent("real"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link-to-file"),
                                                   withDestinationURL: root.appendingPathComponent("plain.txt"))
        let entries = FastDirectoryListing.list(root)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.url.lastPathComponent, $0.isDirectory) })
        XCTAssertEqual(byName["link-to-dir"], true, "a symlinked folder must expand")
        XCTAssertEqual(byName["link-to-file"], false)
        // A recursive walker stops at the link: a symlinked directory can be a cycle or a
        // tree outside the root, so the entry says it is a link as well as what it points at.
        let links = Dictionary(uniqueKeysWithValues: entries.map { ($0.url.lastPathComponent, $0.isSymbolicLink) })
        XCTAssertEqual(links["link-to-dir"], true)
        XCTAssertEqual(links["link-to-file"], true)
        XCTAssertEqual(links["real"], false)
        XCTAssertEqual(links["plain.txt"], false)
    }

    /// A dangling link can't be stat'd; it must be reported as a file rather than
    /// throwing the whole listing away.
    func testBrokenSymlinkIsListedAsFile() throws {
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("dangling"),
                                                   withDestinationURL: root.appendingPathComponent("nope"))
        let entries = FastDirectoryListing.list(root)
        XCTAssertEqual(names(entries), ["dangling"])
        XCTAssertEqual(entries.first?.isDirectory, false)
    }

    func testUnreadableDirectoryReturnsEmptyRatherThanCrashing() {
        let missing = root.appendingPathComponent("does-not-exist")
        XCTAssertEqual(FastDirectoryListing.list(missing), [])
    }

    /// The output must match what the Foundation call it replaces produced, or the
    /// swap silently changes what the tree shows.
    func testMatchesFoundationListing() throws {
        for n in ["b.txt", "A.txt", "c2.txt", "c10.txt"] { try file(n) }
        try dir("zdir"); try dir("Adir")
        let fast = names(FastDirectoryListing.list(root))
        let foundation = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                 options: [.skipsHiddenFiles])
            .map { (url: $0, isDir: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted {
                if $0.isDir != $1.isDir { return $0.isDir }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            .map { $0.url.lastPathComponent }
        XCTAssertEqual(fast, foundation)
    }
}
