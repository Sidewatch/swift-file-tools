//
//  FileNamingTests.swift
//  FileToolsTests
//
//  Tests for `FileNaming.availableName`: the base when free, then `base 2`, `base 3`, …,
//  the suffix before any extension, and anything at the path counts as taken.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `FileNaming.availableName`.
final class FileNamingTests: XCTestCase {

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("naming-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTheBaseNameWhenNothingHoldsIt() throws {
        let dir = try temporaryFolder()
        XCTAssertEqual(FileNaming.availableName("Untitled Project", in: dir), "Untitled Project")
        XCTAssertEqual(FileNaming.availableName("notes", pathExtension: "md", in: dir), "notes.md")
    }

    func testTakenNamesCountUpFromTwo() throws {
        let dir = try temporaryFolder()
        let fm = FileManager.default
        try fm.createDirectory(at: dir.appendingPathComponent("Untitled Project"), withIntermediateDirectories: false)
        XCTAssertEqual(FileNaming.availableName("Untitled Project", in: dir), "Untitled Project 2")
        try fm.createDirectory(at: dir.appendingPathComponent("Untitled Project 2"), withIntermediateDirectories: false)
        XCTAssertEqual(FileNaming.availableName("Untitled Project", in: dir), "Untitled Project 3")
    }

    func testTheSuffixGoesBeforeTheExtension() throws {
        let dir = try temporaryFolder()
        try "x".write(to: dir.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        XCTAssertEqual(FileNaming.availableName("notes", pathExtension: "md", in: dir), "notes 2.md")
        XCTAssertEqual(FileNaming.availableName("notes", in: dir), "notes", "notes.md does not hold the bare name")
    }

    func testAFileOrADanglingLinkHoldsTheName() throws {
        let dir = try temporaryFolder()
        try "x".write(to: dir.appendingPathComponent("a"), atomically: true, encoding: .utf8)
        XCTAssertEqual(FileNaming.availableName("a", in: dir), "a 2", "a file holds a folder's name too")
        try FileManager.default.createSymbolicLink(atPath: dir.appendingPathComponent("b").path, withDestinationPath: "/nonexistent/target")
        XCTAssertEqual(FileNaming.availableName("b", in: dir), "b 2", "a dangling link still occupies its name")
    }
}
