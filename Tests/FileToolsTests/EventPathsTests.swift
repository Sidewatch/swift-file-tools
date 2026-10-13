//
//  EventPathsTests.swift
//  FileToolsTests
//
//  Event paths renamed back under a folder opened through a symlink, and the skip filter.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class EventPathsTests: XCTestCase {
    func testAPathUnderTheRealFolderIsRenamedUnderTheLinkItWasOpenedBy() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("eventpaths-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let realPath = try XCTUnwrap(link.realPath)  // what FSEvents would report
        let named = EventPaths.namedByOpenedRoots([realPath + "/src/a.swift", realPath, "/elsewhere/b.txt"], roots: [link])
        XCTAssertEqual(named, [link.path + "/src/a.swift", link.path, "/elsewhere/b.txt"])
    }

    func testARootThatIsItsOwnRealPathIsLeftAlone() throws {
        let dir = URL(fileURLWithPath: FileManager.default.temporaryDirectory.path).resolvingSymlinksInPath()
        let real = try XCTUnwrap(dir.realPath)
        let paths: Set<String> = [real + "/a.txt"]
        XCTAssertEqual(EventPaths.namedByOpenedRoots(paths, roots: [URL(fileURLWithPath: real)]), paths)
    }

    func testTheFilterSkipsBelowTheRootOnly() {
        let kept = EventPaths.relevant(
            ["/p/src/a.swift", "/p/.git/index", "/p/node_modules/x/y.js", "/p/src/build/out.o", "/elsewhere/z"],
            root: "/p/", skipping: [".git", "node_modules", "build"])
        XCTAssertEqual(kept, ["/p/src/a.swift", "/elsewhere/z"])
        let nested = EventPaths.relevant(
            ["/w/node_modules/mylib/index.js", "/w/node_modules/mylib/node_modules/dep/a.js"],
            root: "/w/node_modules/mylib/", skipping: ["node_modules"])
        XCTAssertEqual(nested, ["/w/node_modules/mylib/index.js"], "a root inside a skipped folder keeps its own events")
    }
}
