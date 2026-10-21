//
//  ProjectSearchStreamTests.swift
//  FileToolsTests
//
//  A streamed search delivers every matching file, then one final batch.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// `ProjectSearch.stream`.
final class ProjectSearchStreamTests: XCTestCase {
    /// Every batch handed over, in order, with its `final` flag.
    private final class Deliveries: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [(names: [String], final: Bool)] = []
        func add(_ batch: [SearchFileResult], _ final: Bool) {
            lock.lock()
            items.append((batch.map(\.url.lastPathComponent), final))
            lock.unlock()
        }
        var all: [(names: [String], final: Bool)] {
            lock.lock()
            defer { lock.unlock() }
            return items
        }
    }

    private func project() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("stream-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        for (path, text) in [("a.txt", "needle\n"), ("sub/b.txt", "a needle\n"), ("c.txt", "nothing\n"), ("sub/d.txt", "needle needle\n")] {
            try text.write(to: root.appendingPathComponent(path), atomically: true, encoding: .utf8)
        }
        return root
    }

    private func run(_ root: URL, files: [URL]? = nil) -> [(names: [String], final: Bool)] {
        let got = Deliveries()
        let done = expectation(description: "final batch")
        ProjectSearch.stream(query: "needle", roots: [root], files: files, caseSensitive: false, regex: false, isCancelled: { false }) {
            batch, final in
            got.add(batch, final)
            if final { done.fulfill() }
        }
        wait(for: [done], timeout: 10)
        Thread.sleep(forTimeInterval: 0.1)  // nothing may arrive after the final batch
        return got.all
    }

    func testEveryMatchingFileArrivesOnceAndTheFinalBatchIsLast() throws {
        let root = try project()
        defer { try? FileManager.default.removeItem(at: root) }
        let all = run(root)
        XCTAssertEqual(all.flatMap(\.names).sorted(), ["a.txt", "b.txt", "d.txt"])
        XCTAssertEqual(all.filter(\.final).count, 1)
        XCTAssertEqual(all.last?.final, true)
    }

    func testGivenFilesAreTheOnlyOnesSearched() throws {
        let root = try project()
        defer { try? FileManager.default.removeItem(at: root) }
        let all = run(root, files: [root.appendingPathComponent("a.txt"), root.appendingPathComponent("c.txt")])
        XCTAssertEqual(all.flatMap(\.names), ["a.txt"])
        XCTAssertEqual(all.last?.final, true)
    }
}
