//
//  IgnoreSearchTests.swift
//  ProjectSearch honours .gitignore (via git) and .ignore (parsed), per directory, and
//  the toggle turns it off. Uses real temp git repos, like IgnoreGitTests.
//

import XCTest
@testable import FileTools

final class IgnoreSearchTests: XCTestCase {

    private func makeRepo(git: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ignore-search-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("src/gen"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        try "needle in main".write(to: root.appendingPathComponent("src/main.swift"), atomically: true, encoding: .utf8)
        try "needle in generated".write(to: root.appendingPathComponent("src/gen/out.swift"), atomically: true, encoding: .utf8)
        try "needle in log".write(to: root.appendingPathComponent("logs/app.log"), atomically: true, encoding: .utf8)
        try "needle in docs".write(to: root.appendingPathComponent("docs/guide.md"), atomically: true, encoding: .utf8)
        try "needle in secret".write(to: root.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try "logs/\n*.txt\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "gen/\n".write(to: root.appendingPathComponent("src/.ignore"), atomically: true, encoding: .utf8)   // ripgrep-only file
        if git {
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = ["git", "-C", root.path, "init", "-q"]; try p.run(); p.waitUntilExit()
        }
        return root
    }

    private func hits(in root: URL) -> Set<String> {
        var out = Set<String>()
        let results = ProjectSearch.search(query: "needle", in: root, caseSensitive: false, regex: false, isCancelled: { false })
        for r in results { out.insert(r.url.path.replacingOccurrences(of: root.path + "/", with: "")) }
        return out
    }

    override func setUp() { IgnoreRulesCache.invalidateAll(); ProjectSearch.respectIgnoreFiles = true }
    override func tearDown() { ProjectSearch.respectIgnoreFiles = true }

    func testGitRepoHonoursGitignoreAndDotIgnore() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(hits(in: root), ["src/main.swift", "docs/guide.md"])
        XCTAssertEqual(ProjectSearch.countCandidateFiles(in: root), 2)   // main + guide; hidden ignore files are never candidates
    }

    func testPlainFolderParsesGitignoreItself() throws {
        let root = try makeRepo(git: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(hits(in: root), ["src/main.swift", "docs/guide.md"])
    }

    func testToggleOffSearchesEverything() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        ProjectSearch.respectIgnoreFiles = false
        XCTAssertEqual(hits(in: root), ["src/main.swift", "src/gen/out.swift", "logs/app.log", "docs/guide.md", "secret.txt"])
    }

    func testMatcherAnswersForAbsoluteURLsWithNestedIgnoreFiles() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let m = IgnoreMatcher(root: root)
        XCTAssertTrue(m.isIgnored(url: root.appendingPathComponent("logs"), isDirectory: true))
        XCTAssertTrue(m.isIgnored(url: root.appendingPathComponent("logs/app.log"), isDirectory: false), "inside an ignored directory")
        XCTAssertTrue(m.isIgnored(url: root.appendingPathComponent("secret.txt"), isDirectory: false))
        XCTAssertTrue(m.isIgnored(url: root.appendingPathComponent("src/gen/out.swift"), isDirectory: false), "nested .ignore applies")
        XCTAssertFalse(m.isIgnored(url: root.appendingPathComponent("src/main.swift"), isDirectory: false))
        XCTAssertFalse(m.isIgnored(url: root.appendingPathComponent("docs"), isDirectory: true))
        XCTAssertFalse(m.isIgnored(url: root, isDirectory: true), "the root itself is never ignored")
        XCTAssertFalse(m.isIgnored(url: URL(fileURLWithPath: "/elsewhere/x"), isDirectory: false))
        // Rules change → the matcher follows the cache's generation.
        try "".write(to: root.appendingPathComponent("src/.ignore"), atomically: true, encoding: .utf8)
        IgnoreRulesCache.invalidate(root: root)
        XCTAssertFalse(m.isIgnored(url: root.appendingPathComponent("src/gen/out.swift"), isDirectory: false))
    }

    func testCacheNoticesInvalidation() throws {
        let root = try makeRepo(git: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(hits(in: root).count, 2)
        try "".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        XCTAssertEqual(hits(in: root).count, 2, "cached rules still in force before invalidation")
        IgnoreRulesCache.invalidate(root: root)
        XCTAssertEqual(hits(in: root), ["src/main.swift", "logs/app.log", "docs/guide.md", "secret.txt"], ".ignore still hides src/gen")
    }
}
