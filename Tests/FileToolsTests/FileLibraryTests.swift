//
//  FileLibraryTests.swift
//  FileToolsTests
//
//  FileLibraryTests.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import FileTools

final class FileLibraryTests: XCTestCase {

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testProjectEntriesComeFirstAndEachFolderSortsLikeFinder() throws {
        let global = try temporaryFolder(), root = try temporaryFolder()
        let library = FileLibrary(globalDirectory: global, fileExtension: "http", projectSubpath: ".app/http")
        library.save("g", name: "zeta", in: global)
        library.save("g", name: "item 10", in: global)
        library.save("g", name: "item 2", in: global)
        try "x".write(to: global.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        library.save("p", name: "local", in: library.projectDirectory(for: root))

        let titles = library.entries(projectRoot: root).map { ($0.title, $0.isProject) }
        XCTAssertEqual(titles.map(\.0), ["local", "item 2", "item 10", "zeta"])
        XCTAssertEqual(titles.map(\.1), [true, false, false, false])
        XCTAssertEqual(library.entries(projectRoot: nil).count, 3, "no root: global only, and the .txt is not an entry")
    }

    func testSavingTwiceNeverOverwrites() throws {
        let dir = try temporaryFolder()
        let library = FileLibrary(globalDirectory: dir, fileExtension: "http", projectSubpath: ".app/http")
        let first = library.save("one", name: "req", in: dir)
        let second = library.save("two", name: "req", in: dir)
        XCTAssertEqual(first?.lastPathComponent, "req.http")
        XCTAssertEqual(second?.lastPathComponent, "req 2.http")
        XCTAssertEqual(try String(contentsOf: first!, encoding: .utf8), "one")
    }

    func testNamesAreMadeFilenameSafe() {
        XCTAssertEqual(FileLibrary.sanitize(" api/users: list "), "api-users- list")
        XCTAssertEqual(FileLibrary.sanitize("   "), "Untitled")
    }

    func testSeedingIsAdditive() throws {
        let dir = try temporaryFolder()
        let library = FileLibrary(globalDirectory: dir, fileExtension: "http", projectSubpath: ".app/http")
        library.save("mine", name: "Example", in: dir)
        let written = library.seed([("Example", "seed"), ("Other", "seed")], into: dir)
        XCTAssertEqual(written, 1)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("Example.http"), encoding: .utf8), "mine", "an existing file is left alone")
        XCTAssertEqual(library.seed([("Other", "seed")], into: dir), 0, "a second pass writes nothing")
    }
}
