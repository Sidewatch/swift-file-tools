//
//  FileLocationLinkTests.swift
//  FileToolsTests
//
//  Tests for `FileLocationLink`: the link round-trips, foreign and unsafe links are refused, and
//  a trailing `:line:col` is split only when the literal path is not a file.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// Tests for `FileLocationLink`: the link round-trips, foreign and unsafe links are refused, and
/// a trailing `:line:col` is split only when the literal path is not a file.
final class FileLocationLinkTests: XCTestCase {
    typealias Match = TerminalPathParser.Match

    private func reference(_ text: String) -> Match? {
        URL(string: text).flatMap { FileLocationLink.reference(from: $0, scheme: "sidewatch") }
    }

    // MARK: - url / reference

    func testRoundTripKeepsSpacesUnicodeAndPosition() throws {
        let path = "/Users/a/My Project/naïve #1.swift"
        let url = try XCTUnwrap(FileLocationLink.url(scheme: "sidewatch", path: path, line: 42, column: 7))
        XCTAssertEqual(FileLocationLink.reference(from: url, scheme: "sidewatch"), Match(path: path, line: 42, column: 7))
    }

    func testURLRefusesARelativePath() {
        XCTAssertNil(FileLocationLink.url(scheme: "sidewatch", path: "src/a.ts"))
    }

    func testReferenceRefusesAnotherSchemeOrVerb() {
        XCTAssertNil(reference("vscode://open?path=/p/a.ts"))
        XCTAssertNil(reference("sidewatch://run?path=/p/a.ts"))
        XCTAssertNil(reference("sidewatch://open/p/a.ts"))
    }

    func testReferenceRefusesARelativeOrMissingPath() {
        XCTAssertNil(reference("sidewatch://open?path=src/a.ts"))
        XCTAssertNil(reference("sidewatch://open?path=../etc/hosts"))
        XCTAssertNil(reference("sidewatch://open?line=4"))
    }

    func testReferenceRefusesANul() {
        XCTAssertNil(reference("sidewatch://open?path=/p/a.ts%00.png"))
    }

    func testReferenceIgnoresANonPositiveOrNonNumericLine() {
        XCTAssertEqual(reference("sidewatch://open?path=/p/a.ts&line=0"), Match(path: "/p/a.ts"))
        XCTAssertEqual(reference("sidewatch://open?path=/p/a.ts&line=-3&column=x"), Match(path: "/p/a.ts"))
    }

    func testSchemeAndVerbMatchWhateverTheirCase() {
        XCTAssertEqual(reference("SideWatch://OPEN?path=/p/a.ts&line=2"), Match(path: "/p/a.ts", line: 2))
    }

    // MARK: - resolve

    func testResolveKeepsAPathThatIsAFile() {
        let ref = Match(path: "/p/a.ts:42")
        XCTAssertEqual(FileLocationLink.resolve(ref, fileExists: { $0 == "/p/a.ts:42" }), ref)
    }

    func testResolveSplitsATrailingLineAndColumn() {
        XCTAssertEqual(
            FileLocationLink.resolve(Match(path: "/p/a.ts:42:7"), fileExists: { $0 == "/p/a.ts" }),
            Match(path: "/p/a.ts", line: 42, column: 7))
    }

    func testResolveDoesNotSplitWhenTheLinkCarriesALine() {
        XCTAssertNil(FileLocationLink.resolve(Match(path: "/p/a.ts:42", line: 3), fileExists: { $0 == "/p/a.ts" }))
    }

    func testResolveFindsNothingWhenNeitherIsAFile() {
        XCTAssertNil(FileLocationLink.resolve(Match(path: "/p/a.ts:42"), fileExists: { _ in false }))
    }
}
