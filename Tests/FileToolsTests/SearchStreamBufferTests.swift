//
//  SearchStreamBufferTests.swift
//  FileToolsTests
//
//  The batching between a search walk and the main thread: the first file goes at once, later
//  ones wait for the interval, and the final hand-off closes the buffer.
//
//  Created by David Sherlock on 10/13/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class SearchStreamBufferTests: XCTestCase {
    private func result(_ name: String) -> SearchFileResult {
        SearchFileResult(url: URL(fileURLWithPath: "/p/\(name)"), matches: [])
    }

    func testTheFirstFileIsHandedOffAtOnce() {
        let buffer = SearchStreamBuffer()
        buffer.append(result("a"))
        XCTAssertEqual(buffer.drainIfDue(interval: 60, force: false)?.map(\.url.lastPathComponent), ["a"])
    }

    func testLaterFilesWaitForTheInterval() {
        let buffer = SearchStreamBuffer()
        buffer.append(result("a"))
        _ = buffer.drainIfDue(interval: 60, force: false)
        buffer.append(result("b"))
        XCTAssertNil(buffer.drainIfDue(interval: 60, force: false), "a second batch inside the interval waits")
        XCTAssertEqual(buffer.drainIfDue(interval: 0, force: false)?.map(\.url.lastPathComponent), ["b"], "and goes once it is due")
    }

    func testNothingPendingIsNotDue() {
        let buffer = SearchStreamBuffer()
        XCTAssertNil(buffer.drainIfDue(interval: 0, force: false))
    }

    func testTheFinalHandOffAlwaysGoesAndClosesTheBuffer() {
        let buffer = SearchStreamBuffer()
        buffer.append(result("a"))
        _ = buffer.drainIfDue(interval: 60, force: false)
        XCTAssertEqual(buffer.drainIfDue(interval: 60, force: true)?.count, 0, "the end of the walk hands off even nothing")
        buffer.append(result("late"))
        XCTAssertNil(buffer.drainIfDue(interval: 0, force: true), "a timer tick racing the end gets nothing")
    }
}
