//
//  TextFileContents.swift
//  FileTools
//
//  A text file as this package decodes it: the text, and the encoding it round-trips in.
//
//  Created by David Sherlock on 9/18/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A text file as this package decodes it: the text, and the encoding it round-trips in.
///
/// The point of the type is ``TextFileEncoding/data(for:)``: a rewrite that goes back
/// through it reproduces the file's own bytes everywhere it did not change. Re-encoding as
/// plain UTF-8 would drop a byte-order mark and rewrite every Latin-1 byte, a spurious diff.
public struct TextFileContents: Sendable {

    /// The decoded text, without the byte-order mark.
    public let text: String

    /// How the bytes decoded, and therefore how new text is written back.
    public let encoding: TextFileEncoding

    /// True when the bytes were not UTF-8 and were read as Latin-1 instead. Every byte maps to a
    /// character, so nothing is lost on the way in, but a file in another 8-bit encoding
    /// (Windows-1252, Mac Roman) shows its accents wrong: a host says so beside the encoding
    /// rather than presenting the guess as a fact.
    public let decodedByFallback: Bool

    /// How far into the bytes the binary sniff looks for a NUL.
    static let sniffLength = 8000

    /// Contents already decoded as `encoding`.
    public init(text: String, encoding: TextFileEncoding, decodedByFallback: Bool = false) {
        self.text = text
        self.encoding = encoding
        self.decodedByFallback = decodedByFallback
    }

    /// Reads and decodes the file at `url` as ``init(data:)`` does; nil when it cannot be read
    /// or is binary.
    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    /// Decodes `data` as text, or nil when it is binary: a NUL in the first 8,000 bytes, or
    /// bytes that are neither UTF-8 nor decodable as Windows-1252 or Latin-1. A UTF-16 byte-order
    /// mark is read first, since UTF-16 text is half NULs; every mark is removed from the text and
    /// remembered in ``encoding``.
    ///
    /// Text that is not UTF-8 is read as Windows-1252 first: it is what old Windows files are, and
    /// it differs from Latin-1 only in 0x80–0x9F, where it has the curly quotes, `€` and the dashes
    /// that Latin-1 reads as invisible control characters. The five bytes Windows-1252 leaves
    /// undefined (0x81, 0x8D, 0x8F, 0x90, 0x9D) fail its decode, and the file is read as Latin-1,
    /// which maps every byte. Either way unchanged text saves back byte for byte.
    public init?(data: Data) {
        if let utf16 = Self.markedUTF16(data) {
            self = utf16
            return
        }
        if Self.hasBinaryPrefix(data) { return nil }
        let bom = TextFileEncoding.utf8ByteOrderMark
        let hasBOM = data.starts(with: bom)
        if let utf8 = String(data: hasBOM ? data.dropFirst(bom.count) : data, encoding: .utf8) {
            self.init(text: utf8, encoding: TextFileEncoding(encoding: .utf8, hasByteOrderMark: hasBOM))
        } else if let windows = String(data: data, encoding: .windowsCP1252) {
            self.init(text: windows, encoding: TextFileEncoding(encoding: .windowsCP1252, hasByteOrderMark: false), decodedByFallback: true)
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            self.init(text: latin1, encoding: TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false), decodedByFallback: true)
        } else {
            return nil
        }
    }

    /// Whether `data` reads as binary before any decoding: a NUL in its first 8,000 bytes (a UTF-16 file with
    /// its byte-order mark is the one exception ``init(data:)`` makes). Only that prefix is read, so a caller can
    /// ask it of a memory-mapped file before deciding to read the whole file in.
    public static func hasBinaryPrefix(_ data: Data) -> Bool { data.prefix(sniffLength).contains(0) }

    /// Whether `data` holds a line of `length` bytes or more, its break not counted: one `memchr` pass that stops at
    /// the first such line. A host asks it before handing a text to a view that lays a line out whole.
    public static func hasLine(atLeast length: Int, in data: Data) -> Bool {
        guard length > 0 else { return true }
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return false }
            var start = 0
            while start < raw.count {
                guard let hit = memchr(base + start, 0x0A, raw.count - start) else { return raw.count - start >= length }
                let end = UnsafeRawPointer(hit) - base
                if end - start >= length { return true }
                start = end + 1
            }
            return false
        }
    }

    /// The text behind an `FF FE` or `FE FF` mark in that byte order, or nil when the bytes
    /// carry neither (an unmarked UTF-16 file still reads as binary) or do not decode.
    private static func markedUTF16(_ data: Data) -> TextFileContents? {
        for encoding in [TextFileEncoding.utf16LittleEndian, .utf16BigEndian] where data.starts(with: encoding.byteOrderMark) {
            guard let text = String(data: data.dropFirst(encoding.byteOrderMark.count), encoding: encoding.encoding) else { return nil }
            return TextFileContents(text: text, encoding: encoding)
        }
        return nil
    }

    /// `newText` in the file's own bytes — see ``TextFileEncoding/data(for:)``.
    public func data(for newText: String) -> Data? { encoding.data(for: newText) }
}

/// The encoding a text file was read in, and whether it began with a byte-order mark, so that
/// new text can be written back in the file's own bytes.
public struct TextFileEncoding: Sendable, Equatable {

    /// The string encoding: UTF-8, Windows-1252, ISO Latin-1, or UTF-16 in either byte order.
    public let encoding: String.Encoding

    /// Whether the file began with its encoding's byte-order mark (``byteOrderMark``).
    public let hasByteOrderMark: Bool

    /// The UTF-8 byte-order mark.
    static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Plain UTF-8 with no byte-order mark — what a new file is written as.
    public static let utf8 = TextFileEncoding(encoding: .utf8, hasByteOrderMark: false)

    /// UTF-16 with the low byte first, behind its `FF FE` mark (what Windows calls "Unicode").
    public static let utf16LittleEndian = TextFileEncoding(encoding: .utf16LittleEndian, hasByteOrderMark: true)

    /// UTF-16 with the high byte first, behind its `FE FF` mark.
    public static let utf16BigEndian = TextFileEncoding(encoding: .utf16BigEndian, hasByteOrderMark: true)

    /// Creates an encoding description.
    public init(encoding: String.Encoding, hasByteOrderMark: Bool) {
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    /// The bytes a file in this encoding opens with when it carries a mark.
    public var byteOrderMark: [UInt8] {
        switch encoding {
        case .utf16LittleEndian: return [0xFF, 0xFE]
        case .utf16BigEndian: return [0xFE, 0xFF]
        default: return Self.utf8ByteOrderMark
        }
    }

    /// A short name for a badge: "UTF-8", "UTF-8 with BOM", "Windows-1252", "Latin-1", "UTF-16 LE",
    /// "UTF-16 BE".
    public var displayName: String {
        switch encoding {
        case .utf8: return hasByteOrderMark ? "UTF-8 with BOM" : "UTF-8"
        case .windowsCP1252: return "Windows-1252"
        case .isoLatin1: return "Latin-1"
        case .utf16LittleEndian: return "UTF-16 LE"
        case .utf16BigEndian: return "UTF-16 BE"
        default: return encoding.description
        }
    }

    /// `newText` encoded this way, byte-order mark included, or nil when a character
    /// cannot be represented (a `€` into a Latin-1 file). A caller never switches encoding on
    /// its own: a UTF-8 rewrite of a Latin-1 file changes every accented byte the user did not
    /// touch, so the decision is the user's.
    public func data(for newText: String) -> Data? {
        guard var out = newText.data(using: encoding) else { return nil }
        if hasByteOrderMark { out.insert(contentsOf: byteOrderMark, at: 0) }
        return out
    }
}
