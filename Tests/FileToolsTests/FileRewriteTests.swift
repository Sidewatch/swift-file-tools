//
//  FileRewriteTests.swift
//  FileToolsTests
//
//  A rewrite lands on the file a path names, through a link, and leaves the file's own metadata
//  in place: permissions, group, extended attributes.
//
//  Created by David Sherlock on 10/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
import FoundationExtensions
@testable import FileTools

final class FileRewriteTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("rewrite-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir.appendingPathComponent("elsewhere"), withIntermediateDirectories: true)
    }
    override func tearDown() { try? fm.removeItem(at: dir) }

    private func file(_ name: String, _ text: String = "old\n") throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }
    private func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }
    private func isLink(_ url: URL) -> Bool { (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil }
    private func attribute(_ name: String, of url: URL) -> String? {
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size >= 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        _ = getxattr(url.path, name, &buffer, buffer.count, 0, 0)
        return String(decoding: buffer, as: UTF8.self)
    }

    func testAWriteThroughALinkLandsOnTheTargetAndTheLinkSurvives() throws {
        let target = try file("target.txt")
        let relative = dir.appendingPathComponent("relative.txt")
        try fm.createSymbolicLink(atPath: relative.path, withDestinationPath: "target.txt")
        try FileRewrite.write(Data("through relative\n".utf8), to: relative)
        XCTAssertEqual(text(target), "through relative\n")
        XCTAssertTrue(isLink(relative), "the link is still a link")

        let far = try file("elsewhere/far.txt")
        let absolute = dir.appendingPathComponent("absolute.txt")
        try fm.createSymbolicLink(at: absolute, withDestinationURL: far)
        try FileRewrite.write(Data("through absolute\n".utf8), to: absolute)
        XCTAssertEqual(text(far), "through absolute\n")
        XCTAssertTrue(isLink(absolute))
        XCTAssertEqual(absolute.realPath, far.realPath, "the link still points where it did")
    }

    func testADanglingLinkIsRefusedAndStaysALink() throws {
        let dangling = dir.appendingPathComponent("dangling.txt")
        try fm.createSymbolicLink(atPath: dangling.path, withDestinationPath: "gone.txt")
        XCTAssertThrowsError(try FileRewrite.write(Data("x".utf8), to: dangling)) { error in
            XCTAssertEqual(error as? FileRewriteError, .danglingSymbolicLink(dangling))
        }
        XCTAssertTrue(isLink(dangling), "the link was not turned into a file")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("gone.txt").path))
    }

    func testExtendedAttributesSurviveExceptTheQuarantineFlag() throws {
        let url = try file("tagged.txt")
        for (name, value) in [
            ("com.apple.TextEncoding", "utf-8;134217984"), ("user.note", "hello"), ("com.apple.quarantine", "0083;00000000;Safari;"),
        ] {
            XCTAssertEqual(setxattr(url.path, name, value, value.utf8.count, 0, 0), 0)
        }
        try FileRewrite.write(Data("new\n".utf8), to: url)
        XCTAssertEqual(text(url), "new\n")
        XCTAssertEqual(attribute("com.apple.TextEncoding", of: url), "utf-8;134217984")
        XCTAssertEqual(attribute("user.note", of: url), "hello")
        XCTAssertNil(attribute("com.apple.quarantine", of: url), "the quarantine flag describes the old bytes, not these")
    }

    func testTheGroupSurvivesTheRewrite() throws {
        let url = try file("grouped.txt")
        var info = stat()
        XCTAssertEqual(stat(url.path, &info), 0)
        var groups = [gid_t](repeating: 0, count: Int(NGROUPS_MAX))
        let count = getgroups(Int32(groups.count), &groups)
        guard let other = groups.prefix(Int(max(count, 0))).first(where: { $0 != info.st_gid }) else {
            throw XCTSkip("the user belongs to one group only; nothing to change the file's group to")
        }
        XCTAssertEqual(chown(url.path, uid_t.max, other), 0)
        try FileRewrite.write(Data("new\n".utf8), to: url)
        XCTAssertEqual(stat(url.path, &info), 0)
        XCTAssertEqual(info.st_gid, other, "the new inode wears the file's group, not the staging folder's")
    }

    func testAReadOnlyFileIsRefusedWithItsOwnError() throws {
        let url = try file("locked.txt")
        try fm.setAttributes([.posixPermissions: 0o444], ofItemAtPath: url.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path) }
        XCTAssertThrowsError(try FileRewrite.write(Data("x".utf8), to: url)) { error in
            XCTAssertEqual(error as? FileRewriteError, .fileNotWritable(url))
            XCTAssertEqual(error.localizedDescription, "“locked.txt” is read-only.")
        }
        XCTAssertEqual(text(url), "old\n")
    }

    func testAPathWithNothingAtItBecomesANewFile() throws {
        let url = dir.appendingPathComponent("fresh.txt")
        try FileRewrite.write(Data("born\n".utf8), to: url)
        XCTAssertEqual(text(url), "born\n")
    }
}
