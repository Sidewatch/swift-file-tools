//
//  DiskStormDetectorTests.swift
//  FileToolsTests
//
//  Tests for `DiskStormDetector`: three hot seconds of five is a storm, a quiet tree is not,
//  and the per-second and per-directory thresholds hold.
//
//  Created by David Sherlock on 9/2/26.
//

import XCTest
@testable import FileTools

/// Tests for `DiskStormDetector`: three hot seconds of five is a storm, a quiet tree is not,
/// and the per-second and per-directory thresholds hold.
final class DiskStormDetectorTests: XCTestCase {

    private let root = URL(fileURLWithPath: "/proj", isDirectory: true)
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func paths(_ n: Int, under dir: String, root: String = "/proj") -> [String] {
        (0..<n).map { "\(root)/\(dir)/f\($0).php" }
    }

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    /// 25 changes a second for four seconds is an agent at work, not a storm.
    func testQuietTreeIsNotAStorm() {
        var d = DiskStormDetector()
        for s in 0..<4 { d.ingest(paths: paths(25, under: "src"), roots: [root], at: at(Double(s))) }
        XCTAssertNil(d.storm(at: at(3)))
    }

    /// The WordPress case: an object cache writing a hundred files a second. After
    /// three seconds it is a storm, named by the deepest folder holding 80% of it —
    /// `wp-content/cache/object`, not the 70% sub-folder and not `wp-content`.
    func testSustainedFloodNamesTheDeepestSharedFolder() throws {
        var d = DiskStormDetector()
        for s in 0..<3 {
            d.ingest(paths: paths(70, under: "wp-content/cache/object/a") + paths(30, under: "wp-content/cache/object/b"),
                     roots: [root], at: at(Double(s)))
        }
        let storm = try XCTUnwrap(d.storm(at: at(2.5)))
        XCTAssertEqual(storm.events, 300)
        XCTAssertEqual(storm.perSecond, 60, "averaged over the five-second window")
        XCTAssertEqual(storm.root, root)
        XCTAssertEqual(storm.relativeFolder, "wp-content/cache/object")
        XCTAssertEqual(storm.ancestorNames, ["object", "cache", "wp-content"], "deepest first — the user picks the level")
    }

    /// A `git checkout` touching two thousand files lands in one second. That is a
    /// burst, not a storm — and a trickle three seconds later does not make it one.
    func testOneSecondBurstIsNotAStorm() {
        var d = DiskStormDetector()
        d.ingest(paths: paths(2000, under: "src"), roots: [root], at: at(0))
        XCTAssertNil(d.storm(at: at(0)))
        d.ingest(paths: paths(5, under: "src"), roots: [root], at: at(3))
        XCTAssertNil(d.storm(at: at(3)), "two thousand events in the window, but only one hot second")
    }

    /// Two seconds of flood is still not sustained; the third makes it so.
    func testThreeHotSecondsAreRequired() {
        var d = DiskStormDetector()
        d.ingest(paths: paths(100, under: "cache"), roots: [root], at: at(0))
        d.ingest(paths: paths(100, under: "cache"), roots: [root], at: at(1))
        XCTAssertNil(d.storm(at: at(1)))
        d.ingest(paths: paths(100, under: "cache"), roots: [root], at: at(2))
        XCTAssertNotNil(d.storm(at: at(2)))
    }

    /// Once the tree goes quiet the hot seconds age out of the window and the
    /// storm is gone — nothing else clears it, so this is what makes the notice decay.
    func testStormDecaysOnceTheTreeGoesQuiet() {
        var d = DiskStormDetector()
        for s in 0..<3 { d.ingest(paths: paths(100, under: "cache"), roots: [root], at: at(Double(s))) }
        XCTAssertNotNil(d.storm(at: at(2)))
        XCTAssertNotNil(d.storm(at: at(4)), "still inside the window")
        XCTAssertNil(d.storm(at: at(9)), "the hot seconds have left the five-second window")
    }

    /// Events spread evenly across five top-level folders name no folder: no
    /// directory holds 80%, and the notice must say so rather than pick one.
    func testSpreadAcrossTheRootNamesNoFolder() throws {
        var d = DiskStormDetector()
        for s in 0..<3 {
            var batch: [String] = []
            for dir in ["a", "b", "c", "d", "e"] { batch += paths(20, under: dir) }
            d.ingest(paths: batch, roots: [root], at: at(Double(s)))
        }
        let storm = try XCTUnwrap(d.storm(at: at(2)))
        XCTAssertNil(storm.folder)
        XCTAssertEqual(storm.relativeFolder, "")
        XCTAssertTrue(storm.ancestorNames.isEmpty)
    }

    /// A flood under a reference root is reported against THAT root, so the
    /// folder reads relative to it and the skip candidates stop at its edge.
    func testReferenceRootResolvesAgainstItsOwnRoot() throws {
        let ref = URL(fileURLWithPath: "/libs/shared", isDirectory: true)
        var d = DiskStormDetector()
        for s in 0..<3 {
            d.ingest(paths: paths(100, under: "build/out", root: "/libs/shared"), roots: [root, ref], at: at(Double(s)))
        }
        let storm = try XCTUnwrap(d.storm(at: at(2)))
        XCTAssertEqual(storm.root, ref)
        XCTAssertEqual(storm.relativeFolder, "build/out")
        XCTAssertEqual(storm.ancestorNames, ["out", "build"])
    }

    /// Acting on a storm (adding the folder to the skip list) resets the window so
    /// the notice clears now, not five seconds later.
    func testResetForgetsTheWindow() {
        var d = DiskStormDetector()
        for s in 0..<3 { d.ingest(paths: paths(100, under: "cache"), roots: [root], at: at(Double(s))) }
        XCTAssertNotNil(d.storm(at: at(2)))
        d.reset()
        XCTAssertNil(d.storm(at: at(2)))
    }
}
