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
    /// bytes that are neither UTF-8 nor decodable as Latin-1. A UTF-16 byte-order mark is read
    /// first, since UTF-16 text is half NULs; every mark is removed from the text and remembered
    /// in ``encoding``.
    public init?(data: Data) {
        if let utf16 = Self.markedUTF16(data) {
            self = utf16
            return
        }
        if data.prefix(Self.sniffLength).contains(0) { return nil }
        let bom = TextFileEncoding.utf8ByteOrderMark
        let hasBOM = data.starts(with: bom)
        if let utf8 = String(data: hasBOM ? data.dropFirst(bom.count) : data, encoding: .utf8) {
            self.init(text: utf8, encoding: TextFileEncoding(encoding: .utf8, hasByteOrderMark: hasBOM))
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            self.init(text: latin1, encoding: TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false), decodedByFallback: true)
        } else {
            return nil
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

    /// The string encoding: UTF-8, ISO Latin-1, or UTF-16 in either byte order.
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

    /// A short name for a badge: "UTF-8", "UTF-8 with BOM", "Latin-1", "UTF-16 LE", "UTF-16 BE".
    public var displayName: String {
        switch encoding {
        case .utf8: return hasByteOrderMark ? "UTF-8 with BOM" : "UTF-8"
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
