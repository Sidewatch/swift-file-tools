//
//  ProjectScriptsTests.swift
//  FileToolsTests
//
//  Tests for `ProjectScripts.detect`: npm scripts, Make targets and composer scripts found in
//  temp-dir fixtures.
//
//  Created by David Sherlock on 7/19/26.
//

import XCTest
@testable import FileTools

/// Tests for `ProjectScripts.detect`: npm scripts, Make targets and composer scripts found in
/// temp-dir fixtures.
final class ProjectScriptsTests: XCTestCase {

    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ProjectScriptsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
    }

    private func write(_ contents: String, to name: String) throws {
        try contents.write(to: tmp.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    // MARK: - package.json

    func testNpmScriptsSortedWithNpmRunner() throws {
        try write(#"{"scripts": {"build": "tsc", "test": "vitest", "dev": "vite"}}"#, to: "package.json")
        let scripts = ProjectScripts.detect(root: tmp)
        XCTAssertEqual(scripts.map(\.name), ["build", "dev", "test"])       // sorted
        XCTAssertEqual(scripts.map(\.command), ["npm run build", "npm run dev", "npm run test"])
        XCTAssertTrue(scripts.allSatisfy { $0.source == "package.json" })
    }

    func testPnpmLockChoosesPnpmRunner() throws {
        try write(#"{"scripts": {"build": "tsc"}}"#, to: "package.json")
        try write("lockfileVersion: '9.0'", to: "pnpm-lock.yaml")
        XCTAssertEqual(ProjectScripts.detect(root: tmp).first?.command, "pnpm run build")
    }

    func testYarnLockDropsRunKeyword() throws {
        try write(#"{"scripts": {"start": "node ."}}"#, to: "package.json")
        try write("# yarn lockfile v1", to: "yarn.lock")
        XCTAssertEqual(ProjectScripts.detect(root: tmp).first?.command, "yarn start")
    }

    func testBunLockChoosesBunRunner() throws {
        try write(#"{"scripts": {"start": "bun ."}}"#, to: "package.json")
        try write("", to: "bun.lockb")
        XCTAssertEqual(ProjectScripts.detect(root: tmp).first?.command, "bun run start")
    }

    // MARK: - composer.json

    func testComposerScriptsSkipReservedHooks() throws {
        try write(#"""
        {"scripts": {
            "test": "phpunit",
            "post-install-cmd": "echo hi",
            "lint": "phpcs"
        }}
        """#, to: "composer.json")
        let scripts = ProjectScripts.detect(root: tmp)
        XCTAssertEqual(scripts.map(\.name), ["lint", "test"])
        XCTAssertEqual(scripts.first?.command, "composer run lint")
    }

    // MARK: - Makefile

    func testMakefileTargetsDetectedTargetsOnly() throws {
        try write("""
        CC = clang
        build:
        \t$(CC) main.c
        test: build
        \t./a.out
        .PHONY: clean
        clean:
        \trm -f a.out
        # a comment: not a target
        """, to: "Makefile")
        let names = ProjectScripts.detect(root: tmp).map(\.name)
        XCTAssertEqual(names, ["build", "test", "clean"])
        XCTAssertFalse(names.contains("CC"))          // variable assignment excluded
        XCTAssertFalse(names.contains(".PHONY"))      // dot-target excluded
    }

    func testMakefileColonAssignmentsAreNotTargets() throws {
        // `VAR := value` (and `::=`/`:::=`) puts the '=' AFTER the colon, so the
        // name-side guards never saw it — these leaked into the task list as
        // bogus "make CC" entries.
        try write("""
        CC := gcc
        CFLAGS:=-Wall
        IMMEDIATE ::= now
        POSIX :::= later
        build:
        \t$(CC) main.c
        """, to: "Makefile")
        XCTAssertEqual(ProjectScripts.detect(root: tmp).map(\.name), ["build"])
    }

    func testMakefileDeduplicatesTargets() throws {
        try write("all:\n\techo one\nall:\n\techo two\n", to: "Makefile")
        XCTAssertEqual(ProjectScripts.detect(root: tmp).filter { $0.source == "Makefile" }.count, 1)
    }

    // MARK: - Combined / empty

    func testEmptyRootYieldsNothing() {
        XCTAssertTrue(ProjectScripts.detect(root: tmp).isEmpty)
    }

    func testAllThreeSourcesCombine() throws {
        try write(#"{"scripts": {"build": "tsc"}}"#, to: "package.json")
        try write(#"{"scripts": {"test": "phpunit"}}"#, to: "composer.json")
        try write("run:\n\techo go\n", to: "Makefile")
        let sources = Set(ProjectScripts.detect(root: tmp).map(\.source))
        XCTAssertEqual(sources, ["package.json", "composer.json", "Makefile"])
    }
}
