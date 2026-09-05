//
//  FileToolsTests.swift
//  Tests for SwiftFileTools
//
//  Tests for the FileTools helpers over a temporary directory fixture.
//
//  Created by David Sherlock on 7/9/26.
//

import XCTest
@testable import FileTools

/// Tests for the FileTools helpers over a temporary directory fixture.
final class FileToolsTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileToolsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    // MARK: - Helpers

    private func write(_ contents: String, to relativePath: String) throws {
        let url = tmp.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func mkdir(_ relativePath: String) throws {
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(relativePath), withIntermediateDirectories: true)
    }

    // MARK: - FileTree

    func testFileTreeAsciiRendersStructure() throws {
        try write("print(1)\n", to: "Sources/main.swift")
        try write("# hi\n", to: "README.md")
        try mkdir("Sources/Empty")

        let tree = FileTree.ascii(of: tmp)
        let lines = tree.split(separator: "\n").map(String.init)

        // Root header ends in a slash.
        XCTAssertEqual(lines.first, tmp.lastPathComponent + "/")
        // Directories are rendered with a trailing slash, files without.
        XCTAssertTrue(tree.contains("Sources/"))
        XCTAssertTrue(tree.contains("main.swift"))
        XCTAssertTrue(tree.contains("README.md"))
        XCTAssertTrue(tree.contains("Empty/"))
        // Branch glyphs are present.
        XCTAssertTrue(tree.contains("├──") || tree.contains("└──"))
    }

    func testFileTreeSkipsNoiseDirectories() throws {
        try write("code\n", to: "keep.txt")
        try write("junk\n", to: ".git/config")
        try write("dep\n", to: "node_modules/pkg/index.js")

        let tree = FileTree.ascii(of: tmp)
        XCTAssertTrue(tree.contains("keep.txt"))
        XCTAssertFalse(tree.contains(".git"))
        XCTAssertFalse(tree.contains("node_modules"))
    }

    func testFileTreeDirectoriesListedBeforeFiles() throws {
        try write("a\n", to: "afile.txt")
        try mkdir("zdir")

        let tree = FileTree.ascii(of: tmp)
        let dirIndex = tree.range(of: "zdir/")!.lowerBound
        let fileIndex = tree.range(of: "afile.txt")!.lowerBound
        XCTAssertLessThan(dirIndex, fileIndex, "directories should be listed before files")
    }

    func testFileTreeRespectsMaxDepth() throws {
        try write("deep\n", to: "a/b/c/deep.txt")
        let shallow = FileTree.ascii(of: tmp, maxDepth: 1)
        XCTAssertFalse(shallow.contains("deep.txt"))
        let deep = FileTree.ascii(of: tmp, maxDepth: 8)
        XCTAssertTrue(deep.contains("deep.txt"))
    }

    // MARK: - ProjectSearch

    func testSearchExplicitFileListScopesExactly() throws {
        try write("target here\n", to: "in.swift")
        try write("target here too\n", to: "out.swift")
        let results = ProjectSearch.search(
            query: "target", files: [tmp.appendingPathComponent("in.swift")],
            caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(results.count, 1, "only the listed file may be searched")
        XCTAssertEqual(results.first?.url.lastPathComponent, "in.swift")
    }

    func testCountCandidateFilesMatchesWhatTheSearchScans() throws {
        try write("needle\n", to: "a.php")
        try write("hay\n", to: "b.js")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
        try write("needle\n", to: "node_modules/skipped.js")   // on the skip list
        try write("hidden\n", to: ".secret")                    // hidden
        XCTAssertEqual(ProjectSearch.countCandidateFiles(in: tmp), 2)
        XCTAssertEqual(ProjectSearch.countCandidateFiles(in: tmp, include: { $0.pathExtension == "php" }), 1)
        var reported: [Int] = []
        let results = ProjectSearch.search(query: "needle", in: tmp, caseSensitive: false, regex: false,
                                           isCancelled: { false }, onProgress: { reported.append($0) })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(reported, [1, 2], "progress climbs once per file considered, to the candidate total")
    }

    func testSearchDoesNotFollowSymlinkedDirectoriesOrFiles() throws {
        try write("needle\n", to: "real.txt")
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: tmp.appendingPathComponent("sub/loop"), withDestinationURL: tmp)
        try FileManager.default.createSymbolicLink(at: tmp.appendingPathComponent("alias.txt"),
                                                   withDestinationURL: tmp.appendingPathComponent("real.txt"))
        let results = ProjectSearch.search(query: "needle", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(results.map(\.url.lastPathComponent), ["real.txt"],
                       "a symlinked file is not a second hit; a symlinked directory is not entered")
        XCTAssertEqual(ProjectSearch.countCandidateFiles(in: tmp), 1)
    }

    func testSearchIncludeFilterPrunesTheWalk() throws {
        try write("needle\n", to: "a.php")
        try write("needle\n", to: "b.js")
        let results = ProjectSearch.search(
            query: "needle", in: tmp, caseSensitive: false, regex: false,
            isCancelled: { false }, include: { $0.pathExtension == "php" })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "a.php")
    }

    func testReplaceAllHonorsIncludeFilter() throws {
        try write("needle\n", to: "a.php")
        try write("needle\n", to: "b.js")
        let summary = ProjectSearch.replaceAll(
            query: "needle", in: tmp, caseSensitive: false, regex: false,
            replacement: "thread", commit: true, isCancelled: { false },
            include: { $0.pathExtension == "php" })
        XCTAssertEqual(summary.filesChanged, 1)
        XCTAssertEqual(try String(contentsOf: tmp.appendingPathComponent("a.php"), encoding: .utf8), "thread\n")
        XCTAssertEqual(try String(contentsOf: tmp.appendingPathComponent("b.js"), encoding: .utf8), "needle\n",
                       "a file outside the include filter must never be rewritten")
    }

    func testProjectSearchFindsMatch() throws {
        try write("let x = 1\nhello world\nlet y = 2\n", to: "a.swift")
        try write("nothing here\n", to: "b.swift")

        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })

        XCTAssertEqual(results.count, 1)
        let file = try XCTUnwrap(results.first)
        XCTAssertEqual(file.url.lastPathComponent, "a.swift")
        XCTAssertEqual(file.matches.count, 1)
        let match = try XCTUnwrap(file.matches.first)
        XCTAssertEqual(match.line, 2)
        XCTAssertEqual(match.lineText, "hello world")
        XCTAssertEqual(match.range.location, 0)
        XCTAssertEqual(match.range.length, 5)
    }

    func testProjectSearchIsCaseInsensitiveByDefault() throws {
        try write("HELLO there\n", to: "a.txt")
        let insensitive = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(insensitive.count, 1)

        let sensitive = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: true, regex: false, isCancelled: { false })
        XCTAssertTrue(sensitive.isEmpty)
    }

    func testProjectSearchRegex() throws {
        try write("id = 42\nid = abc\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: #"id = \d+"#, in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.matches.count, 1)
        XCTAssertEqual(results.first?.matches.first?.line, 1)
    }

    func testProjectSearchInvalidRegexReturnsNothing() throws {
        try write("anything\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "([", in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertTrue(results.isEmpty)
    }

    func testProjectSearchEmptyQueryReturnsNothing() throws {
        try write("hello\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertTrue(results.isEmpty)
    }

    func testProjectSearchSkipsNoiseDirectories() throws {
        try write("hello here\n", to: "keep.txt")
        try write("hello inside\n", to: "node_modules/dep.txt")

        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.url.lastPathComponent, "keep.txt")
    }

    func testProjectSearchSkipsSymlinks() throws {
        // A symlink's own size (a few bytes) used to pass the 2MB guard while
        // Data(contentsOf:) followed the link and read the whole target.
        // Non-regular files must be skipped outright.
        let targetDir = tmp.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        let target = targetDir.appendingPathComponent("big.txt")
        // A >2MB target that contains the query — over the per-file size cap.
        var contents = String(repeating: "x", count: 2_100_000)
        contents += "\nhello target\n"
        try contents.write(to: target, atomically: true, encoding: .utf8)

        let root = tmp.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "no match\n".write(to: root.appendingPathComponent("plain.txt"),
                               atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"), withDestinationURL: target)

        let results = ProjectSearch.search(
            query: "hello", in: root, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertTrue(results.isEmpty, "symlinked oversized target must not be read or matched")
    }

    func testProjectSearchCapsMatchesPerFile() throws {
        // The per-file cap used to only break the per-line loop; a file where
        // every line matches kept accumulating one match per line.
        let lines = Array(repeating: "error hello error", count: 1_000).joined(separator: "\n")
        try write(lines, to: "noisy.log")

        let plain = ProjectSearch.search(
            query: "error", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(plain.first?.matches.count, 200, "per-file cap should hold at 200")

        let regex = ProjectSearch.search(
            query: "err\\w+", in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertEqual(regex.first?.matches.count, 200, "per-file cap should hold at 200 for regex")
    }

    func testProjectSearchRespectsCancellation() throws {
        try write("hello\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { true })
        XCTAssertTrue(results.isEmpty)
    }

    func testProjectSearchAnchoredRegexFindsMidFileLines() throws {
        // The whole-file pre-check compiles the pattern with .anchorsMatchLines
        // so ^/$ keep their per-line meaning — a mid-file anchored hit must
        // survive the pre-check, not be filtered as "no whole-text match".
        try write("first\nTODO: fix\nlast\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "^TODO:.*$", in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
        XCTAssertEqual(results.first?.matches.first?.line, 2)
    }

    func testProjectSearchTextBoundaryAndLookaroundPatternsBypassPrefilter() throws {
        // \A/\z/\Z and negative lookaround mean different things per-line vs
        // whole-text — those patterns must skip the whole-file pre-check so the
        // per-line walk still finds their mid-file hits.
        try write("alpha\nomega\nlast\n", to: "a.txt")
        for pattern in [#"\Aomega"#, #"omega\z"#, #"omega\Z"#, #"omega(?!\n)"#, #"(?<!\n)omega"#] {
            let results = ProjectSearch.search(
                query: pattern, in: tmp, caseSensitive: false, regex: true, isCancelled: { false })
            XCTAssertEqual(results.first?.matches.first?.line, 2, pattern)
        }
    }

    func testProjectSearchLiteralQueryContainingNewlineFindsNothing() throws {
        // The literal pre-check runs over the whole text, so a query spanning a
        // newline passes it — the per-line walk must still (correctly) find nothing.
        try write("hello\nworld\n", to: "a.txt")
        let results = ProjectSearch.search(
            query: "hello\nworld", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertTrue(results.isEmpty)
    }

    // MARK: - ProjectSearch replaceAll

    private func read(_ relativePath: String) throws -> String {
        try String(contentsOf: tmp.appendingPathComponent(relativePath), encoding: .utf8)
    }

    func testReplaceAllLiteralAcrossFiles() throws {
        try write("foo bar foo\n", to: "a.txt")
        try write("no match here\n", to: "b.txt")
        try write("a foo line\n", to: "sub/c.txt")

        let summary = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: false, regex: false,
            replacement: "baz", commit: true, isCancelled: { false })

        XCTAssertEqual(summary.filesChanged, 2)
        XCTAssertEqual(summary.replacements, 3)   // two in a.txt, one in c.txt
        XCTAssertEqual(summary.filesFailed, 0)
        XCTAssertEqual(try read("a.txt"), "baz bar baz\n")
        XCTAssertEqual(try read("b.txt"), "no match here\n")   // untouched, not rewritten
        XCTAssertEqual(try read("sub/c.txt"), "a baz line\n")
    }

    func testReplaceAllCaseSensitivity() throws {
        try write("Foo foo FOO\n", to: "a.txt")

        let sensitive = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: true, regex: false,
            replacement: "x", commit: true, isCancelled: { false })
        XCTAssertEqual(sensitive.replacements, 1)
        XCTAssertEqual(try read("a.txt"), "Foo x FOO\n")
    }

    func testReplaceAllRegexTemplateBackreferences() throws {
        try write("name: alice\nname: bob\n", to: "a.txt")

        let summary = ProjectSearch.replaceAll(
            query: #"name: (\w+)"#, in: tmp, caseSensitive: false, regex: true,
            replacement: "user=$1", commit: true, isCancelled: { false })

        XCTAssertEqual(summary.filesChanged, 1)
        XCTAssertEqual(summary.replacements, 2)
        XCTAssertEqual(try read("a.txt"), "user=alice\nuser=bob\n")
    }

    func testReplaceAllPreservesLineEndingsAndTrailingNewline() throws {
        // CRLF endings and a final line without a newline must survive untouched
        // except at the replaced sites.
        try write("foo\r\nbar\r\nfoo", to: "a.txt")
        _ = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: false, regex: false,
            replacement: "X", commit: true, isCancelled: { false })
        XCTAssertEqual(try read("a.txt"), "X\r\nbar\r\nX")
    }

    func testReplaceAllNoMatchesChangesNothing() throws {
        try write("hello\n", to: "a.txt")
        let summary = ProjectSearch.replaceAll(
            query: "zzz", in: tmp, caseSensitive: false, regex: false,
            replacement: "q", commit: true, isCancelled: { false })
        XCTAssertEqual(summary, .empty)
        XCTAssertEqual(try read("a.txt"), "hello\n")
    }

    func testReplaceAllInvalidRegexIsNoOp() throws {
        try write("anything\n", to: "a.txt")
        let summary = ProjectSearch.replaceAll(
            query: "([", in: tmp, caseSensitive: false, regex: true,
            replacement: "x", commit: true, isCancelled: { false })
        XCTAssertEqual(summary, .empty)
        XCTAssertEqual(try read("a.txt"), "anything\n")
    }

    func testReplaceAllSkipsNoiseDirectories() throws {
        try write("foo\n", to: "node_modules/pkg/index.js")
        try write("foo\n", to: "src/main.swift")

        let summary = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: false, regex: false,
            replacement: "bar", commit: true, isCancelled: { false })

        XCTAssertEqual(summary.filesChanged, 1)
        XCTAssertEqual(try read("node_modules/pkg/index.js"), "foo\n")   // untouched
        XCTAssertEqual(try read("src/main.swift"), "bar\n")
    }

    func testReplaceAllDryRunCountsButWritesNothing() throws {
        try write("foo foo\n", to: "a.txt")
        try write("foo\n", to: "b.txt")

        let dry = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: false, regex: false,
            replacement: "bar", commit: false, isCancelled: { false })

        XCTAssertEqual(dry.filesChanged, 2)   // files that WOULD change
        XCTAssertEqual(dry.replacements, 3)
        XCTAssertEqual(try read("a.txt"), "foo foo\n")   // nothing written
        XCTAssertEqual(try read("b.txt"), "foo\n")
    }

    func testReplaceAllRegexDoesNotMatchAcrossLines() throws {
        // Per-line matching, mirroring search: `\s+` must NOT consume the newline and
        // collapse lines — only intra-line whitespace runs are replaced.
        try write("a  b\nc  d\ne", to: "a.txt")
        let summary = ProjectSearch.replaceAll(
            query: #"\s+"#, in: tmp, caseSensitive: false, regex: true,
            replacement: "_", commit: true, isCancelled: { false })

        XCTAssertEqual(summary.replacements, 2)          // the two intra-line "  " runs
        XCTAssertEqual(try read("a.txt"), "a_b\nc_d\ne")  // newlines intact, no line join
    }

    func testReplaceAllAnchoredRegexRewritesMidFileLines() throws {
        // Same pre-check as search: ^ must keep its per-line meaning, so an
        // anchored match on line 2 still gets replaced.
        try write("keep\nfoo end\n", to: "a.txt")
        let summary = ProjectSearch.replaceAll(
            query: "^foo", in: tmp, caseSensitive: false, regex: true,
            replacement: "bar", commit: true, isCancelled: { false })
        XCTAssertEqual(summary.replacements, 1)
        XCTAssertEqual(try read("a.txt"), "keep\nbar end\n")
    }

    func testReplaceAllDryRunAndCommitCountsMatch() throws {
        try write("x x\nx\n", to: "a.txt")
        let dry = ProjectSearch.replaceAll(
            query: "x", in: tmp, caseSensitive: false, regex: false,
            replacement: "yy", commit: false, isCancelled: { false })
        let done = ProjectSearch.replaceAll(
            query: "x", in: tmp, caseSensitive: false, regex: false,
            replacement: "yy", commit: true, isCancelled: { false })
        XCTAssertEqual(dry.replacements, done.replacements)   // confirm count == real count
        XCTAssertEqual(dry.filesChanged, done.filesChanged)
    }

    func testReplaceAllNonEncodableReplacementFailsInBothDryAndCommit() throws {
        // A Latin-1 file whose replacement introduces a char it can't encode (€) must
        // be reported as FAILED (not changed) — and the dry run must agree with commit
        // so the confirmation count never overstates what gets written.
        let url = tmp.appendingPathComponent("a.txt")
        var bytes = Data("caf".utf8); bytes.append(0xE9); bytes.append(contentsOf: " cafe\n".utf8)  // Latin-1
        try bytes.write(to: url)

        let dry = ProjectSearch.replaceAll(
            query: "cafe", in: tmp, caseSensitive: false, regex: false,
            replacement: "€", commit: false, isCancelled: { false })
        let done = ProjectSearch.replaceAll(
            query: "cafe", in: tmp, caseSensitive: false, regex: false,
            replacement: "€", commit: true, isCancelled: { false })

        XCTAssertEqual(dry.filesChanged, 0)
        XCTAssertEqual(dry.replacements, 0)
        XCTAssertEqual(dry.filesFailed, 1)
        XCTAssertEqual(dry, done)                       // dry run agrees with commit
        XCTAssertEqual(try Data(contentsOf: url), bytes) // file left untouched
    }

    func testReplaceAllPreservesLatin1Encoding() throws {
        // A Latin-1 file (byte 0xE9 = é) with an ASCII match must round-trip in
        // Latin-1, not be silently re-encoded to UTF-8 (which would change 0xE9).
        let url = tmp.appendingPathComponent("a.txt")
        var bytes = Data("caf".utf8); bytes.append(0xE9); bytes.append(contentsOf: " foo\n".utf8)  // "café foo\n" in Latin-1
        try bytes.write(to: url)

        let summary = ProjectSearch.replaceAll(
            query: "foo", in: tmp, caseSensitive: false, regex: false,
            replacement: "bar", commit: true, isCancelled: { false })
        XCTAssertEqual(summary.replacements, 1)

        let after = try Data(contentsOf: url)
        var expected = Data("caf".utf8); expected.append(0xE9); expected.append(contentsOf: " bar\n".utf8)
        XCTAssertEqual(after, expected)   // 0xE9 preserved as one byte, not UTF-8 0xC3 0xA9
    }

    // MARK: - SkippedDirs

    func testSkippedDirsContainsCommonNoise() {
        for name in [".git", "node_modules", ".build", "DerivedData", "Pods"] {
            XCTAssertTrue(SkippedDirs.names.contains(name), "expected \(name) to be skipped")
        }
    }

    func testSkippedDirsOverrideAndReset() {
        defer { SkippedDirs.resetToDefault() }

        XCTAssertEqual(SkippedDirs.names, SkippedDirs.defaultNames, "starts at the defaults")

        SkippedDirs.names = SkippedDirs.defaultNames.subtracting(["dist"])
        XCTAssertFalse(SkippedDirs.names.contains("dist"))
        XCTAssertTrue(SkippedDirs.names.contains(".git"), "the rest of the list survives")

        SkippedDirs.resetToDefault()
        XCTAssertEqual(SkippedDirs.names, SkippedDirs.defaultNames)
        XCTAssertTrue(SkippedDirs.names.contains("dist"))
    }

    /// The whole point of the override: a project with a real `dist/` source
    /// directory must get it back in every scanner that reads the list.
    func testRemovingDistFromSkipListRevealsItToTreeAndSearch() throws {
        defer { SkippedDirs.resetToDefault() }
        try write("hello from dist\n", to: "dist/app.js")

        // Default list: dist is noise — invisible to both scanners.
        XCTAssertFalse(FileTree.ascii(of: tmp).contains("dist"))
        XCTAssertTrue(ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false,
            isCancelled: { false }).isEmpty)

        // Override: dist is real source — both scanners must see it.
        SkippedDirs.names = SkippedDirs.defaultNames.subtracting(["dist"])
        let tree = FileTree.ascii(of: tmp)
        XCTAssertTrue(tree.contains("dist/"), "file tree must show dist once it's off the list")
        XCTAssertTrue(tree.contains("app.js"))
        let hits = ProjectSearch.search(
            query: "hello", in: tmp, caseSensitive: false, regex: false, isCancelled: { false })
        XCTAssertEqual(hits.first?.url.lastPathComponent, "app.js",
                       "project search must descend into dist once it's off the list")
    }

    // MARK: - RecentItems

    func testRecentItemsAddAndList() throws {
        RecentItems.clearAll()
        defer { RecentItems.clearAll() }

        let fileA = tmp.appendingPathComponent("a.txt")
        let fileB = tmp.appendingPathComponent("b.txt")
        try "a".write(to: fileA, atomically: true, encoding: .utf8)
        try "b".write(to: fileB, atomically: true, encoding: .utf8)

        RecentItems.addFile(fileA)
        RecentItems.addFile(fileB)

        // Most-recent-first ordering.
        XCTAssertEqual(RecentItems.files.map(\.lastPathComponent), ["b.txt", "a.txt"])

        // Re-adding moves it to the front without duplicating.
        RecentItems.addFile(fileA)
        XCTAssertEqual(RecentItems.files.map(\.lastPathComponent), ["a.txt", "b.txt"])

        // Folders are tracked separately.
        RecentItems.addFolder(tmp)
        XCTAssertEqual(RecentItems.folders.map(\.lastPathComponent), [tmp.lastPathComponent])

        RecentItems.clearAll()
        XCTAssertTrue(RecentItems.files.isEmpty)
        XCTAssertTrue(RecentItems.folders.isEmpty)
    }

    func testRecentItemsFiltersMissingPaths() throws {
        RecentItems.clearAll()
        defer { RecentItems.clearAll() }

        let file = tmp.appendingPathComponent("gone.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        RecentItems.addFile(file)
        XCTAssertEqual(RecentItems.files.count, 1)

        try FileManager.default.removeItem(at: file)
        XCTAssertTrue(RecentItems.files.isEmpty, "missing paths should be filtered out on read")
    }

    // MARK: - DirectoryEventStream (compile / smoke only)

    func testDirectoryEventStreamInitAndCancel() {
        // FSEvents is async; we only verify the type builds, initializes and
        // cancels cleanly on a real directory.
        let stream = DirectoryEventStream(directory: tmp.path) { _ in }
        stream.cancel()

        // Event / FSEvent are part of the public surface.
        let event = DirectoryEventStream.Event(path: "/tmp/x", eventType: .itemModified)
        XCTAssertEqual(event.path, "/tmp/x")
        XCTAssertEqual(event.eventType, .itemModified)
        XCTAssertEqual(FSEvent.itemCreated.rawValue, "itemCreated")
    }

    func testDirectoryEventStreamCancelIsIdempotent() {
        // cancel() used to be able to double-release the stream when raced;
        // it is now serialized and must be safe to call repeatedly.
        let stream = DirectoryEventStream(directory: tmp.path) { _ in }
        stream.cancel()
        stream.cancel()
        stream.cancel()
    }

    func testDirectoryEventStreamDeliversEvents() {
        // End-to-end sanity for the FSEventStreamContext rework (weak box +
        // serial queue + create-inside-closure): the stream must still
        // deliver events for real file changes.
        let delivered = expectation(description: "FSEvents delivered")
        delivered.assertForOverFulfill = false
        let stream = DirectoryEventStream(directory: tmp.path, debounceDuration: 0.05) { events in
            if !events.isEmpty { delivered.fulfill() }
        }
        defer { stream.cancel() }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [tmp] in
            try? "changed".write(to: tmp!.appendingPathComponent("touched.txt"),
                                 atomically: true, encoding: .utf8)
        }
        wait(for: [delivered], timeout: 10)
    }

    func testGetEventsFromFlagsSurfacesUnrecognizedFlags() {
        // Flags with no recognized item bits — most importantly
        // kFSEventStreamEventFlagMustScanSubDirs (FSEvents coalesced/dropped
        // events, client must rescan) — used to yield an empty set and the
        // event was silently dropped.
        let stream = DirectoryEventStream(directory: tmp.path) { _ in }
        defer { stream.cancel() }

        XCTAssertEqual(
            stream.getEventsFromFlags(FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)),
            [.changeInDirectory])
        XCTAssertEqual(
            stream.getEventsFromFlags(FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)),
            [.changeInDirectory])
        // raw == 0 keeps its existing mapping.
        XCTAssertEqual(stream.getEventsFromFlags(0), [.changeInDirectory])
        // Recognized item bits keep their specific mapping (no spurious
        // .changeInDirectory added).
        XCTAssertEqual(
            stream.getEventsFromFlags(FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)),
            [.itemModified])
    }
}
