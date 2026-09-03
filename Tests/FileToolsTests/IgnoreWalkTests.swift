//
//  IgnoreWalkTests.swift
//  An end-to-end test: a small directory tree walked with a real
//  IgnoreStack.load(directory:relativeDirectory:) at each level, pruning
//  ignored directories rather than descending into them. This is what proves
//  the documented "a file inside an excluded directory cannot be re-included"
//  rule in practice — `build/keep.txt` has an explicit `!` negation, but is
//  never even visited because `build/` itself is pruned first.
//

import XCTest
@testable import FileTools

final class IgnoreWalkTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("IgnoreWalkTests-\(UUID().uuidString)", isDirectory: true)
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

    /// Walks `directory`, loading whichever ignore files exist at each level and
    /// extending the stack accordingly, collecting every non-ignored entry's
    /// relative path — and, crucially, never descending into an ignored
    /// directory, so nothing beneath it is ever even considered.
    private func walk(_ directory: URL, relativeDirectory: String, stack: IgnoreStack, into kept: inout [String]) {
        let loaded = IgnoreStack.load(directory: directory, relativeDirectory: relativeDirectory)
        let stack = stack.appending(contentsOf: loaded)

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? []

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = entry.lastPathComponent
            let relativePath = relativeDirectory.isEmpty ? name : relativeDirectory + "/" + name
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false

            if stack.isIgnored(relativePath: relativePath, isDirectory: isDirectory) {
                continue   // pruned — no visit, no descent, no chance for a deeper "!" to reach it
            }
            kept.append(relativePath)
            if isDirectory {
                walk(entry, relativeDirectory: relativePath, stack: stack, into: &kept)
            }
        }
    }

    func testWalkPrunesIgnoredDirectoriesAndAppliesStackPrecedence() throws {
        try write("*.log\nbuild/\n!important.log\n!build/keep.txt\n", to: ".gitignore")
        try write("hello", to: "a.txt")
        try write("noisy", to: "a.log")
        try write("keep me", to: "important.log")
        try write("output", to: "build/output.log")
        // Would be re-included by "!build/keep.txt" if the walker didn't prune
        // `build/` first — proving negation can't reach inside an excluded dir.
        try write("keep", to: "build/keep.txt")
        // sub's own ignore file re-includes only export.log, not b.log.
        try write("!export.log\n", to: "sub/.gitignore")
        try write("noisy2", to: "sub/b.log")
        try write("keep2", to: "sub/export.log")

        var kept: [String] = []
        walk(tmp, relativeDirectory: "", stack: IgnoreStack(), into: &kept)

        let expectedKept: Set<String> = [
            ".gitignore", "a.txt", "important.log", "sub", "sub/.gitignore", "sub/export.log",
        ]
        XCTAssertEqual(Set(kept), expectedKept)

        // The excluded directory itself, and its contents, were never visited —
        // not even the one with its own negation pattern.
        XCTAssertFalse(kept.contains("a.log"))
        XCTAssertFalse(kept.contains("build"))
        XCTAssertFalse(kept.contains("build/output.log"))
        XCTAssertFalse(kept.contains("build/keep.txt"))
        // Still excluded by the root's *.log: sub's own ignore file only
        // re-includes export.log.
        XCTAssertFalse(kept.contains("sub/b.log"))
    }

    func testIgnoreStackLoadReadsFilesInPrecedenceOrder() throws {
        try write("*.log\n", to: ".gitignore")
        try write("!kept.log\n", to: ".ignore")
        let files = IgnoreStack.load(directory: tmp, relativeDirectory: "")
        XCTAssertEqual(files.count, 2)

        var stack = IgnoreStack(files: files)
        // .ignore is later in IgnoreFileNames.orderedNames, so it wins.
        XCTAssertFalse(stack.isIgnored(relativePath: "kept.log", isDirectory: false))
        XCTAssertTrue(stack.isIgnored(relativePath: "other.log", isDirectory: false))
        stack.pop()   // dropping .ignore leaves only .gitignore's verdict
        XCTAssertTrue(stack.isIgnored(relativePath: "kept.log", isDirectory: false))
    }

    func testIgnoreStackLoadSkipsAbsentFiles() throws {
        // No ignore files at all in this directory.
        let files = IgnoreStack.load(directory: tmp, relativeDirectory: "")
        XCTAssertTrue(files.isEmpty)
    }
}
