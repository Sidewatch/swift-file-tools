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

    func testEventsUnderASkippedFolderNameThatFolderOnce() {
        let skipped: Set<String> = [".git", "node_modules", "vendor", "build"]
        let folders = EventPaths.skippedFolders(
            [
                "/work/site/plugins/a/vendor/lib/x.php", "/work/site/plugins/a/vendor/lib/y.php",
                "/work/site/plugins/b/src/build/out.js", "/work/site/plugins/b/src/main.js",
                "/work/site/plugins/a/.git/index", "/work/site/plugins/a/.git/vendor/x",
                "/work/site/plugins/c/vendor/pkg/.git/HEAD", "/elsewhere/vendor/z",
            ], root: "/work/site/", skipping: skipped)
        XCTAssertEqual(
            folders, ["/work/site/plugins/a/vendor", "/work/site/plugins/b/src/build", "/work/site/plugins/c/vendor"],
            "the first skipped folder of each path; nothing for git's own folder, a shown file or a path outside the root")
    }

    func testAVersionControlFolderBelowASkippedOneStillNamesTheSkippedFolder() {
        // The skipped folder is reached first: what lies deeper does not make it quiet.
        XCTAssertEqual(
            EventPaths.skippedFolders(["/r/vendor/pkg/.git/HEAD"], root: "/r/", skipping: ["vendor", ".git"]), ["/r/vendor"])
        XCTAssertEqual(EventPaths.skippedFolders(["/r/.git/modules/vendor/x"], root: "/r/", skipping: ["vendor", ".git"]), [])
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
