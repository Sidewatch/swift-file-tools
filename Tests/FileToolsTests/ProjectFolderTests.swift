//
//  ProjectFolderTests.swift
//  FileToolsTests
//
//  Tests for `ProjectFolder.create`: a fresh folder is made, an empty one is accepted, and a
//  folder with files or a file holding the name is refused with nothing changed.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `ProjectFolder`.
final class ProjectFolderTests: XCTestCase {

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("project-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func isFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    func testCreatesAFreshFolderAndItsMissingParents() throws {
        let parent = try temporaryFolder()
        let url = parent.appendingPathComponent("deep/New Project")
        try ProjectFolder.create(at: url)
        XCTAssertTrue(isFolder(url))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), [], "nothing is written inside")
    }

    func testAcceptsAnExistingEmptyFolderAsItIs() throws {
        let parent = try temporaryFolder()
        let url = parent.appendingPathComponent("Empty")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        try Data().write(to: url.appendingPathComponent(".DS_Store"))
        XCTAssertNoThrow(try ProjectFolder.create(at: url), "Finder's .DS_Store does not make a folder non-empty")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), [".DS_Store"])
    }

    func testRefusesAFolderWithFilesAndLeavesItUntouched() throws {
        let parent = try temporaryFolder()
        let url = parent.appendingPathComponent("Occupied")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let kept = url.appendingPathComponent(".env")
        try "SECRET=1".write(to: kept, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProjectFolder.create(at: url)) { error in
            XCTAssertEqual(error as? ProjectFolderError, .notEmpty(url))
        }
        XCTAssertEqual(try String(contentsOf: kept, encoding: .utf8), "SECRET=1", "a hidden file counts, and survives")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: url.path), [".env"])
    }

    func testRefusesAFileOrALinkHoldingTheName() throws {
        let parent = try temporaryFolder()
        let file = parent.appendingPathComponent("Taken")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProjectFolder.create(at: file)) { error in
            XCTAssertEqual(error as? ProjectFolderError, .notAFolder(file))
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "x")

        let target = parent.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let link = parent.appendingPathComponent("Linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try ProjectFolder.create(at: link), "a link to an empty folder is still not a new folder") { error in
            XCTAssertEqual(error as? ProjectFolderError, .notAFolder(link))
        }
    }

    func testEmptinessNeedsAReadableFolder() throws {
        let parent = try temporaryFolder()
        XCTAssertFalse(ProjectFolder.isEmptyFolder(parent.appendingPathComponent("missing")))
        let file = parent.appendingPathComponent("file")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertFalse(ProjectFolder.isEmptyFolder(file))
        XCTAssertFalse(ProjectFolder.isEmptyFolder(parent), "a folder holding a file")
    }
}
