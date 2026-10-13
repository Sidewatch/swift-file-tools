//
//  IgnoreMatcherCacheTests.swift
//  FileToolsTests
//
//  One matcher per root: built once and shared, loaded off-main when asked not to wait, and
//  rebuilt when an ignore file changes.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class IgnoreMatcherCacheTests: XCTestCase {
    private func project(ignoring pattern: String) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ignore-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "\(pattern)\n".write(to: root.appendingPathComponent(".ignore"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("a.log"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("a.tmp"), atomically: true, encoding: .utf8)
        return root
    }

    func testOneRootGetsOneMatcherWithItsRules() throws {
        let root = try project(ignoring: "*.log")
        let cache = IgnoreMatcherCache()
        let first = cache.matcher(for: root)
        XCTAssertTrue(first === cache.matcher(for: root), "a root's rules are parsed once and shared")
        XCTAssertTrue(first.isIgnored(url: root.appendingPathComponent("a.log"), isDirectory: false))
        XCTAssertFalse(first.isIgnored(url: root.appendingPathComponent("a.tmp"), isDirectory: false))
    }

    func testAskingWithoutWaitingLoadsInTheBackgroundAndCallsBack() throws {
        let root = try project(ignoring: "*.log")
        let cache = IgnoreMatcherCache()
        let ready = expectation(description: "loaded")
        XCTAssertNil(cache.matcher(for: root) { ready.fulfill() }, "not loaded yet: the caller never waits")
        wait(for: [ready], timeout: 10)
        XCTAssertNotNil(cache.matcher(for: root) {}, "loaded now: answered at once")
    }

    func testAChangedIgnoreFileRebuildsTheMatcher() throws {
        let root = try project(ignoring: "*.log")
        let cache = IgnoreMatcherCache()
        XCTAssertFalse(cache.matcher(for: root).isIgnored(url: root.appendingPathComponent("a.tmp"), isDirectory: false))
        try "*.tmp\n".write(to: root.appendingPathComponent(".ignore"), atomically: true, encoding: .utf8)
        let reread = expectation(description: "reread")
        cache.noteChanged(under: root) { reread.fulfill() }
        wait(for: [reread], timeout: 10)
        let fresh = cache.matcher(for: root)
        XCTAssertTrue(fresh.isIgnored(url: root.appendingPathComponent("a.tmp"), isDirectory: false), "the new rule applies")
        XCTAssertFalse(fresh.isIgnored(url: root.appendingPathComponent("a.log"), isDirectory: false), "the old one is gone")
    }
}
