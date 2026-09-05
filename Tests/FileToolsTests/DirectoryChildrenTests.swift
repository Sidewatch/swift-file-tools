//
//  DirectoryChildrenTests.swift
//  FileToolsTests
//
//  Tests for `DirectoryChildren.sorted`: directories first, then case-insensitive names, with
//  the noise list skipped.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import FileTools

/// Tests for `DirectoryChildren.sorted`: directories first, then case-insensitive names, with
/// the noise list skipped.
final class DirectoryChildrenTests: XCTestCase {
    func testDirectoriesFirstThenCaseInsensitiveNamesSkippingTheNoiseList() throws {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("children-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: d) }
        for sub in ["zeta", "Alpha", "node_modules"] { try FileManager.default.createDirectory(at: d.appendingPathComponent(sub), withIntermediateDirectories: true) }
        for f in ["b.txt", "A.txt", ".hidden"] { try "x".write(to: d.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        let names = DirectoryChildren.sorted(in: d, skipping: ["node_modules"]).map(\.lastPathComponent)
        XCTAssertEqual(names, ["Alpha", "zeta", "A.txt", "b.txt"])
        XCTAssertTrue(d.appendingPathComponent("Alpha").isDirectory)
        XCTAssertFalse(d.appendingPathComponent("b.txt").isDirectory)
        XCTAssertFalse(d.appendingPathComponent("missing").isDirectory)
        XCTAssertEqual(DirectoryChildren.sorted(in: d.appendingPathComponent("missing")), [])
    }
}
