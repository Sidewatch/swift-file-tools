//
//  ExcerptWindowsTests.swift
//  FileToolsTests
//
//  Context windows around matched lines: clipped, merged, and blind to lines that are gone.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

/// `ExcerptWindows.runs(around:context:lineCount:)`.
final class ExcerptWindowsTests: XCTestCase {
    func testWindowsAreClippedToTheText() {
        XCTAssertEqual(ExcerptWindows.runs(around: [1], context: 2, lineCount: 10), [1...3])
        XCTAssertEqual(ExcerptWindows.runs(around: [10], context: 2, lineCount: 10), [8...10])
    }

    func testWindowsThatOverlapOrTouchMergeAndApartStayApart() {
        XCTAssertEqual(ExcerptWindows.runs(around: [3, 5], context: 2, lineCount: 20), [1...7], "overlapping")
        XCTAssertEqual(ExcerptWindows.runs(around: [3, 8], context: 2, lineCount: 20), [1...10], "touching: 5 then 6")
        XCTAssertEqual(ExcerptWindows.runs(around: [3, 9], context: 2, lineCount: 20), [1...5, 7...11], "a line apart")
        XCTAssertEqual(ExcerptWindows.runs(around: [9, 3, 3], context: 2, lineCount: 20), [1...5, 7...11], "any order, repeats once")
    }

    func testALineTheFileNoLongerHasIsIgnored() {
        XCTAssertEqual(ExcerptWindows.runs(around: [2, 40], context: 1, lineCount: 5), [1...3])
        XCTAssertEqual(ExcerptWindows.runs(around: [0, 40], context: 1, lineCount: 5), [])
    }
}
