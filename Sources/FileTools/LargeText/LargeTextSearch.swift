//
//  LargeTextSearch.swift
//  FileTools
//
//  A large text file searched without ever holding its matches: the next one from a place, the one before, those in a
//  screenful, and a count of them all that can say where one falls.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A ``LargeTextFile`` searched for a ``LargeTextMatcher``'s matches without ever holding them all, so a file of any
/// size is searched in the memory one read takes: the next match from a place (``next(_:in:from:isCancelled:)``), the
/// one before (``previous(_:in:before:isCancelled:)``), both wrapping at the file's ends; the matches in a screenful
/// (``matches(_:in:within:)``); and a count of every one that can then say where one falls among them
/// (``count(_:in:isCancelled:)``, ``index(of:in:_:file:)``).
///
/// The file is read 8 MB at a time, each read cut back to just past its last line break so a block holds whole lines;
/// a search from the middle of a line starts at the line's start, and a match that begins before the place it was
/// asked from is not one after it. A line longer than a read is searched a read at a time, and a match across the edge
/// of one is missed. Run everything but ``matches(_:in:within:)`` off the main thread; `isCancelled` is asked between
/// reads.
public enum LargeTextSearch {
    /// How much is read at a time.
    static let block = 8 << 20

    /// The first match that starts at or after byte `offset`, searching on to the file's end and then from its start
    /// back to `offset`; nil when there is none, or when cancelled.
    public static func next(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, from offset: Int, isCancelled: () -> Bool = { false }
    ) -> Range<Int>? {
        next(matcher, in: file, from: offset, block: block, isCancelled: isCancelled)
    }

    /// The last match that starts before byte `offset`, searching back to the file's start and then from its end back
    /// to `offset`; nil when there is none, or when cancelled.
    public static func previous(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, before offset: Int, isCancelled: () -> Bool = { false }
    ) -> Range<Int>? {
        previous(matcher, in: file, before: offset, block: block, isCancelled: isCancelled)
    }

    /// The matches in the bytes `range` holds — a line on screen, or the stretch of a long one that is — in order.
    /// Cheap enough to run as the screen draws.
    public static func matches(_ matcher: LargeTextMatcher, in file: LargeTextFile, within range: Range<Int>) -> [Range<Int>] {
        var found: [Range<Int>] = []
        matcher.enumerate(in: file.bytes(in: range)[...], at: range.lowerBound) {
            found.append($0)
            return true
        }
        return found
    }

    /// Every match in the file counted, a block at a time; nil when cancelled.
    public static func count(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, isCancelled: () -> Bool = { false }
    ) -> LargeTextMatchCount? {
        count(matcher, in: file, block: block, isCancelled: isCancelled)
    }

    /// Where `match` falls among the matches `count` counted, from 0: the matches before its block, and those before
    /// it within the block, read again. Nil for a match outside what was counted.
    public static func index(of match: Range<Int>, in count: LargeTextMatchCount, _ matcher: LargeTextMatcher, file: LargeTextFile) -> Int?
    {
        var lo = 0
        var hi = count.blocks.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if count.blocks[mid].lowerBound <= match.lowerBound { lo = mid } else { hi = mid - 1 }
        }
        guard count.blocks.indices.contains(lo), count.blocks[lo].contains(match.lowerBound) else { return nil }
        var before = 0
        matcher.enumerate(in: file.bytes(in: count.blocks[lo])[...], at: count.blocks[lo].lowerBound) { found in
            guard found.lowerBound < match.lowerBound else { return false }
            before += 1
            return true
        }
        return count.before[lo] + before
    }

    // MARK: - With the read size given (a test makes it small)

    static func next(_ matcher: LargeTextMatcher, in file: LargeTextFile, from offset: Int, block: Int, isCancelled: () -> Bool) -> Range<
        Int
    >? {
        let size = file.byteCount
        let from = min(max(0, offset), size)
        if let found = first(matcher, in: file, from: from, to: size, block: block, isCancelled: isCancelled) { return found }
        guard from > 0 else { return nil }
        return first(matcher, in: file, from: 0, to: from, block: block, isCancelled: isCancelled)
    }

    static func previous(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, before offset: Int, block: Int, isCancelled: () -> Bool
    ) -> Range<Int>? {
        let size = file.byteCount
        let before = min(max(0, offset), size)
        if let found = last(matcher, in: file, from: 0, to: before, block: block, isCancelled: isCancelled) { return found }
        guard before < size else { return nil }
        return last(matcher, in: file, from: before, to: size, block: block, isCancelled: isCancelled)
    }

    static func count(_ matcher: LargeTextMatcher, in file: LargeTextFile, block: Int, isCancelled: () -> Bool) -> LargeTextMatchCount? {
        let size = file.byteCount
        var blocks: [Range<Int>] = []
        var before: [Int] = []
        var total = 0
        var start = 0
        while start < size {
            guard !isCancelled() else { return nil }
            let bytes = lines(of: file, at: start, size: size, block: block)
            guard !bytes.isEmpty else { break }
            var found = 0
            matcher.enumerate(in: bytes, at: start) { _ in
                found += 1
                return true
            }
            blocks.append(start..<(start + bytes.count))
            before.append(total)
            total += found
            start += bytes.count
        }
        return LargeTextMatchCount(total: total, byteCount: size, blocks: blocks, before: before)
    }

    // MARK: - Walking the blocks

    /// The first match starting in `from..<to`, read forward from the start of the line holding `from`.
    private static func first(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, from: Int, to: Int, block: Int, isCancelled: () -> Bool
    ) -> Range<Int>? {
        let size = file.byteCount
        var start = file.lineStart(atOrBefore: from, within: block)
        while start < to, !isCancelled() {
            let bytes = lines(of: file, at: start, size: size, block: block)
            guard !bytes.isEmpty else { return nil }
            var found: Range<Int>?
            var passed = false
            matcher.enumerate(in: bytes, at: start) { match in
                if match.lowerBound >= to {
                    passed = true
                    return false
                }
                guard match.lowerBound >= from else { return true }
                found = match
                return false
            }
            if found != nil || passed { return found }
            start += bytes.count
        }
        return nil
    }

    /// The last match starting in `from..<to`: a block's worth before `to` read forward from a line's start, then the
    /// block's worth before that, and so on back.
    private static func last(
        _ matcher: LargeTextMatcher, in file: LargeTextFile, from: Int, to: Int, block: Int, isCancelled: () -> Bool
    ) -> Range<Int>? {
        let size = file.byteCount
        var end = to
        while end > from, !isCancelled() {
            let start = file.lineStart(atOrBefore: max(from, end - block), within: block)
            var found: Range<Int>?
            var at = start
            while at < end, !isCancelled() {
                let bytes = lines(of: file, at: at, size: size, block: block)
                guard !bytes.isEmpty else { break }
                matcher.enumerate(in: bytes, at: at) { match in
                    guard match.lowerBound < end else { return false }
                    if match.lowerBound >= from { found = match }
                    return true
                }
                at += bytes.count
            }
            if let found { return found }
            guard start > from else { return nil }
            end = start
        }
        return nil
    }

    /// The block of whole lines starting at `start`: up to `block` bytes, cut back to just past its last line break
    /// unless it reaches the file's end (`size`) or holds no break at all (a line longer than a read).
    private static func lines(of file: LargeTextFile, at start: Int, size: Int, block: Int) -> ArraySlice<UInt8> {
        let bytes = file.bytes(in: start..<min(size, start + block))
        guard start + bytes.count < size, let lastBreak = bytes.lastIndex(of: 0x0A) else { return bytes[...] }
        return bytes[...lastBreak]
    }
}
