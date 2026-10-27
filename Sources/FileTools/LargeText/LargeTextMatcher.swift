//
//  LargeTextMatcher.swift
//  FileTools
//
//  What a search of a large text file looks for, made ready once: a literal swept for in the file's own bytes, or a
//  regular expression run over them decoded.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What a search of a ``LargeTextFile`` looks for, made ready once for every search that uses it
/// (``LargeTextSearch``). A literal is encoded in the file's encoding and swept for with Boyer–Moore–Horspool over the
/// raw bytes, ASCII letters in either case unless case-sensitive; a case-insensitive literal with letters beyond ASCII
/// goes the regular expression's way instead, which folds every case. A regular expression runs over a block of whole
/// lines decoded at once, `^` and `$` meaning a line's ends.
///
/// A match is never empty and never runs across a line break: one that would is dropped. Matches do not overlap.
/// `NSRegularExpression` is immutable and safe to share across threads, so a matcher is too.
public final class LargeTextMatcher: @unchecked Sendable {
    /// How the matches are found.
    private enum Method {
        /// The pattern's bytes (folded when `folding`) and Horspool's skip for each byte value.
        case literal(pattern: [UInt8], folding: Bool, skip: [Int])
        case regex(NSRegularExpression)
    }

    private let method: Method

    /// The encoding of the file it was made for.
    public let encoding: String.Encoding

    /// A matcher for `text` in a file of `encoding` (``LargeTextFile/encoding``); nil when `text` is empty, a regular
    /// expression that does not compile, or a literal the encoding cannot hold or holding a line break (it could never
    /// match).
    public init?(text: String, caseSensitive: Bool, isRegex: Bool, encoding: String.Encoding) {
        guard !text.isEmpty else { return nil }
        self.encoding = encoding
        let options: NSRegularExpression.Options = caseSensitive ? [.anchorsMatchLines] : [.anchorsMatchLines, .caseInsensitive]
        if isRegex || (!caseSensitive && !text.unicodeScalars.allSatisfy(\.isASCII)) {
            let pattern = isRegex ? text : NSRegularExpression.escapedPattern(for: text)
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
            method = .regex(regex)
        } else {
            guard let encoded = text.data(using: encoding), !encoded.contains(0x0A) else { return nil }
            let pattern = [UInt8](encoded).map { caseSensitive ? $0 : Self.fold($0) }
            method = .literal(pattern: pattern, folding: !caseSensitive, skip: Self.skipTable(pattern, folding: !caseSensitive))
        }
    }

    /// Calls `body` with each match in `bytes` — whole lines that start at byte `start` of the file — in order, as byte
    /// ranges in the file, until it returns false.
    func enumerate(in bytes: ArraySlice<UInt8>, at start: Int, _ body: (Range<Int>) -> Bool) {
        switch method {
        case .literal(let pattern, let folding, let skip):
            Self.sweep(pattern, skip: skip, folding: folding, in: bytes, at: start, body)
        case .regex(let regex):
            Self.run(regex, in: bytes, at: start, encoding: encoding, body)
        }
    }

    // MARK: - Literals

    /// Horspool's skip: how far the pattern may move when the text byte under its last position is each value.
    private static func skipTable(_ pattern: [UInt8], folding: Bool) -> [Int] {
        let m = pattern.count
        var skip = [Int](repeating: m, count: 256)
        for i in 0..<(m - 1) {
            skip[Int(pattern[i])] = m - 1 - i
            if folding, let other = otherCase(pattern[i]) { skip[Int(other)] = m - 1 - i }
        }
        return skip
    }

    /// Horspool over `bytes`: the last pattern byte is compared first, and a mismatch skips by how far that text byte
    /// lies from the pattern's end. A match moves the sweep past itself, so matches do not overlap.
    private static func sweep(
        _ pattern: [UInt8], skip: [Int], folding: Bool, in bytes: ArraySlice<UInt8>, at start: Int, _ body: (Range<Int>) -> Bool
    ) {
        let m = pattern.count
        bytes.withUnsafeBufferPointer { buffer in
            guard let text = buffer.baseAddress, m <= buffer.count else { return }
            var at = 0
            while at <= buffer.count - m {
                let last = text[at + m - 1]
                if (folding ? fold(last) : last) == pattern[m - 1], equals(pattern, at: text + at, folding: folding) {
                    guard body((start + at)..<(start + at + m)) else { return }
                    at += m
                } else {
                    at += skip[Int(last)]
                }
            }
        }
    }

    /// Whether the `pattern.count` bytes at `bytes` equal `pattern` (already folded when `folding`).
    @inline(__always)
    private static func equals(_ pattern: [UInt8], at bytes: UnsafePointer<UInt8>, folding: Bool) -> Bool {
        for i in 0..<pattern.count where (folding ? fold(bytes[i]) : bytes[i]) != pattern[i] { return false }
        return true
    }

    /// An ASCII capital as its small letter; any other byte as itself.
    @inline(__always)
    static func fold(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte | 0x20 : byte }

    /// The other case of an ASCII letter, or nil.
    private static func otherCase(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x41...0x5A: return byte | 0x20
        case 0x61...0x7A: return byte & ~0x20
        default: return nil
        }
    }

    // MARK: - Regular expressions

    /// The regular expression over `bytes` decoded at once (one call per block, not per line: ten million lines would
    /// otherwise cost a minute), each match mapped back to its bytes.
    private static func run(
        _ regex: NSRegularExpression, in bytes: ArraySlice<UInt8>, at start: Int, encoding: String.Encoding,
        _ body: (Range<Int>) -> Bool
    ) {
        let text =
            encoding == .utf8
            ? String(decoding: bytes, as: UTF8.self)
            : (String(bytes: bytes, encoding: .windowsCP1252) ?? String(bytes: bytes, encoding: .isoLatin1) ?? "")
        // One UTF-16 unit to a byte in ASCII and in Windows-1252; other UTF-8 is walked, invalid bytes included.
        let direct = encoding != .utf8 || text.utf8.count == text.utf16.count
        var walker = UTF8OffsetWalker(bytes)
        func byteOffset(_ utf16: Int) -> Int { direct ? utf16 : walker.byteOffset(ofUTF16: utf16) }
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: text.utf16.count)) { match, _, stop in
            guard let range = match?.range, range.length > 0 else { return }
            let lower = byteOffset(range.location)
            let upper = byteOffset(range.location + range.length)
            guard lower < upper, upper <= bytes.count, !bytes[(bytes.startIndex + lower)..<(bytes.startIndex + upper)].contains(0x0A)
            else { return }
            if !body((start + lower)..<(start + upper)) { stop.pointee = true }
        }
    }
}
