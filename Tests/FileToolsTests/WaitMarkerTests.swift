//
//  WaitMarkerTests.swift
//  FileToolsTests
//
//  Tests for `WaitMarker` and `WaitingFiles`: only a regular file of this user's, straight inside
//  the folder and under the prefix, is a marker; releasing deletes it; settling returns the markers
//  of closed files.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `WaitMarker` and `WaitingFiles`: only a regular file of this user's, straight inside
/// the folder and under the prefix, is a marker; releasing deletes it; settling returns the markers
/// of closed files.
final class WaitMarkerTests: XCTestCase {
    private var dir: URL!
    private let prefix = "app-wait."

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("wait-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func touch(_ name: String) -> String {
        let path = dir.appendingPathComponent(name).path
        FileManager.default.createFile(atPath: path, contents: Data())
        return path
    }

    private func accept(_ path: String) -> URL? { WaitMarker.accept(path, directory: dir.path, prefix: prefix) }

    // MARK: - accept

    func testAcceptsAFileOfOursInTheFolderUnderThePrefix() {
        let path = touch("app-wait.Ab12Cd")
        XCTAssertEqual(accept(path)?.path, path)
    }

    func testAcceptsTheFolderThroughItsOtherSpelling() throws {
        // `/var/folders/…` and `/private/var/folders/…` are one folder.
        let path = touch("app-wait.x")
        let real = try XCTUnwrap(dir.realPath)
        XCTAssertNotNil(WaitMarker.accept(real + "/app-wait.x", directory: dir.path, prefix: prefix))
        XCTAssertNotNil(WaitMarker.accept(path, directory: real, prefix: prefix))
    }

    func testRefusesAnotherNameOrTheBarePrefix() {
        XCTAssertNil(accept(touch("notes.txt")))
        XCTAssertNil(accept(touch("app-wait.")))
        XCTAssertNil(accept(touch("x-app-wait.1")))
    }

    func testRefusesAFileOutsideTheFolder() {
        XCTAssertNil(accept(touch("sub/app-wait.1")))
        _ = touch("app-wait.2")
        XCTAssertNil(
            WaitMarker.accept(
                dir.appendingPathComponent("sub").path + "/../app-wait.2", directory: dir.appendingPathComponent("sub").path, prefix: prefix
            ))
    }

    func testRefusesARelativeOrNulOrMissingPath() {
        XCTAssertNil(accept("app-wait.1"))
        XCTAssertNil(accept(dir.path + "/app-wait.1\0"))
        XCTAssertNil(accept(dir.path + "/app-wait.missing"))
    }

    func testRefusesALinkAndAFolder() throws {
        let target = touch("precious.txt")
        let link = dir.appendingPathComponent("app-wait.link").path
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        XCTAssertNil(accept(link))
        try FileManager.default.createDirectory(atPath: dir.appendingPathComponent("app-wait.dir").path, withIntermediateDirectories: false)
        XCTAssertNil(accept(dir.appendingPathComponent("app-wait.dir").path))
    }

    func testMarkerReadsTheLinksWaitItem() throws {
        let path = touch("app-wait.q")
        var parts = URLComponents(string: "app://open")!
        parts.queryItems = [URLQueryItem(name: "path", value: "/p/a.ts"), URLQueryItem(name: WaitMarker.queryItem, value: path)]
        XCTAssertEqual(WaitMarker.marker(in: try XCTUnwrap(parts.url), directory: dir.path, prefix: prefix)?.path, path)
        XCTAssertNil(WaitMarker.marker(in: URL(string: "app://open?path=/p/a.ts")!, directory: dir.path, prefix: prefix))
    }

    // MARK: - release

    func testReleaseDeletesTheMarkerOnce() throws {
        let marker = try XCTUnwrap(accept(touch("app-wait.r")))
        XCTAssertTrue(WaitMarker.release(marker))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertFalse(WaitMarker.release(marker))
    }

    func testReleaseLeavesAMarkerThatBecameALink() throws {
        let marker = try XCTUnwrap(accept(touch("app-wait.s")))
        let target = touch("precious.txt")
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createSymbolicLink(atPath: marker.path, withDestinationPath: target)
        XCTAssertFalse(WaitMarker.release(marker))
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: marker.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target))
    }

    // MARK: - WaitingFiles

    func testSettleReturnsOnlyTheClosedFilesMarkers() {
        var waits = WaitingFiles()
        let m1 = URL(fileURLWithPath: "/t/w.1"), m2 = URL(fileURLWithPath: "/t/w.2"), m3 = URL(fileURLWithPath: "/t/w.3")
        waits.add(file: "/p/a", marker: m1)
        waits.add(file: "/p/b", marker: m2)
        waits.add(file: "/p/a", marker: m3)
        XCTAssertEqual(waits.settle(open: ["/p/a", "/p/b"]), [])
        XCTAssertEqual(waits.settle(open: ["/p/b"]), [m1, m3])
        XCTAssertFalse(waits.isEmpty)
        XCTAssertEqual(waits.settle(open: ["/p/b"]), [])
        XCTAssertEqual(waits.removeAll(), [m2])
        XCTAssertTrue(waits.isEmpty)
    }
}
