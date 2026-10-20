//
//  FileComparisonLinkTests.swift
//  FileToolsTests
//
//  Tests for `FileComparisonLink`: the link round-trips, and foreign or unsafe links are refused.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `FileComparisonLink`: the link round-trips, and foreign or unsafe links are refused.
final class FileComparisonLinkTests: XCTestCase {
    private func paths(_ text: String) -> (old: String, new: String)? {
        URL(string: text).flatMap { FileComparisonLink.paths(from: $0, scheme: "sidewatch") }
    }

    func testRoundTripKeepsSpacesUnicodeAndAmpersands() throws {
        let old = "/Users/a/My Project/naïve & old.txt", new = "/Users/a/new?#=.txt"
        let url = try XCTUnwrap(FileComparisonLink.url(scheme: "sidewatch", old: old, new: new))
        let read = try XCTUnwrap(FileComparisonLink.paths(from: url, scheme: "sidewatch"))
        XCTAssertEqual(read.old, old)
        XCTAssertEqual(read.new, new)
    }

    func testURLRefusesARelativeSide() {
        XCTAssertNil(FileComparisonLink.url(scheme: "sidewatch", old: "a.txt", new: "/b.txt"))
        XCTAssertNil(FileComparisonLink.url(scheme: "sidewatch", old: "/a.txt", new: "b.txt"))
    }

    func testPathsRefuseAnotherSchemeOrVerb() {
        XCTAssertNil(paths("vscode://diff?old=/a&new=/b"))
        XCTAssertNil(paths("sidewatch://open?old=/a&new=/b"))
    }

    func testPathsRefuseAMissingRelativeOrNulSide() {
        XCTAssertNil(paths("sidewatch://diff?old=/a"))
        XCTAssertNil(paths("sidewatch://diff?new=/b"))
        XCTAssertNil(paths("sidewatch://diff?old=a&new=/b"))
        XCTAssertNil(paths("sidewatch://diff?old=/a&new=../b"))
        XCTAssertNil(paths("sidewatch://diff?old=/a%00.png&new=/b"))
    }

    func testSchemeAndVerbMatchWhateverTheirCase() {
        XCTAssertEqual(paths("SideWatch://DIFF?old=/a&new=/b")?.new, "/b")
    }
}
