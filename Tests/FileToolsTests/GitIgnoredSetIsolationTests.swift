//
//  GitIgnoredSetIsolationTests.swift
//  FileToolsTests
//
//  The ignore listing reads a checkout's own config, so it must not run the commands that config
//  names: opening a folder is not consent to run its code.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class GitIgnoredSetIsolationTests: XCTestCase {
    private func git(_ args: [String], in dir: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    /// A checkout whose `core.fsmonitor` names a script that leaves `marker` behind when run.
    private func hostileCheckout() throws -> (root: URL, marker: URL) {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fsmonitor-\(UUID().uuidString)")
        let root = base.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        git(["init", "-q"], in: root)
        try "*.log\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
        let marker = base.appendingPathComponent("MARKER")
        let script = base.appendingPathComponent("monitor.sh")
        try "#!/bin/sh\ntouch '\(marker.path)'\nexit 1\n".write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        git(["config", "core.fsmonitor", script.path], in: root)
        return (root, marker)
    }

    func testListingACheckoutNeverRunsItsFsmonitorCommand() throws {
        let (root, marker) = try hostileCheckout()
        let set = try XCTUnwrap(GitIgnoredSet.load(root: root), "the listing still works")
        XCTAssertTrue(set.isIgnored(relativePath: "debug.log", isDirectory: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "the checkout's fsmonitor command ran")
    }
}
