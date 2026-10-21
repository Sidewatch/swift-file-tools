//
//  FileNamingCopiesTests.swift
//  FileToolsTests
//
//  Finder's duplicate names, valid names, and case-only renames.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// `FileNaming.copyDestination`, `isValidName` and `isCaseOnlyRename`.
final class FileNamingCopiesTests: XCTestCase {
    func testADuplicateTakesFindersNextFreeCopyName() {
        let taken: Set<String> = ["/p/a.txt", "/p/a copy.txt", "/p/a copy 2.txt"]
        XCTAssertEqual(FileNaming.copyDestination(for: URL(fileURLWithPath: "/p/a.txt")) { taken.contains($0) }.path, "/p/a copy 3.txt")
        XCTAssertEqual(
            FileNaming.copyDestination(for: URL(fileURLWithPath: "/p/b.txt")) { taken.contains($0) }.path, "/p/b.txt", "a free name stays")
        XCTAssertEqual(
            FileNaming.copyDestination(for: URL(fileURLWithPath: "/p/Makefile")) { $0 == "/p/Makefile" }.path, "/p/Makefile copy",
            "no extension")
    }

    func testOnlyRealNamesAreValid() {
        XCTAssertTrue(FileNaming.isValidName("notes.md"))
        for bad in ["", ".", "..", "a/b", "a:b"] { XCTAssertFalse(FileNaming.isValidName(bad), bad) }
    }

    func testACaseOnlyRenameIsToldFromARealOne() {
        XCTAssertTrue(FileNaming.isCaseOnlyRename(URL(fileURLWithPath: "/p/Foo.txt"), URL(fileURLWithPath: "/p/foo.txt")))
        XCTAssertFalse(FileNaming.isCaseOnlyRename(URL(fileURLWithPath: "/p/Foo.txt"), URL(fileURLWithPath: "/p/Foo.txt")), "the same path")
        XCTAssertFalse(FileNaming.isCaseOnlyRename(URL(fileURLWithPath: "/p/Foo.txt"), URL(fileURLWithPath: "/p/bar.txt")))
    }

    func testADanglingLinkStillTakesItsName() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("copies-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(
            atPath: dir.appendingPathComponent("a copy.txt").path, withDestinationPath: "/nowhere/gone")
        XCTAssertEqual(FileNaming.copyDestination(for: original).lastPathComponent, "a copy 2.txt", "the dangling link's name is taken")
    }
}
