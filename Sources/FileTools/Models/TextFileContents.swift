//
//  TextFileContents.swift
//  FileTools
//
//  A text file as this package decodes it: the text, and the encoding it round-trips in.
//
//  Created by David Sherlock on 9/18/26.
//

import Foundation

/// A text file as this package decodes it: the text, and the encoding it round-trips in.
///
/// The point of the type is ``TextFileEncoding/data(for:)``: a rewrite that goes back
/// through it reproduces the file's own bytes everywhere it did not change. Decoding the
/// plain string and re-encoding it as UTF-8 dropped the byte-order mark a Windows tool or
/// Excel put there and rewrote every Latin-1 byte — a spurious diff on every save.
public struct TextFileContents: Sendable {

    /// The decoded text, without the byte-order mark.
    public let text: String

    /// How the bytes decoded, and therefore how new text is written back.
    public let encoding: TextFileEncoding

    /// How far into the bytes the binary sniff looks for a NUL.
    static let sniffLength = 8000

    public init(text: String, encoding: TextFileEncoding) {
        self.text = text
        self.encoding = encoding
    }

    /// Decodes `data` as text, or nil when it is binary: a NUL in the first 8,000 bytes,
    /// or bytes that are neither UTF-8 nor decodable as Latin-1. A UTF-8 BOM is removed
    /// from the text and remembered in ``encoding``.
    public init?(data: Data) {
        if data.prefix(Self.sniffLength).contains(0) { return nil }
        let bom = TextFileEncoding.utf8ByteOrderMark
        let hasBOM = data.starts(with: bom)
        if let utf8 = String(data: hasBOM ? data.dropFirst(bom.count) : data, encoding: .utf8) {
            self.init(text: utf8, encoding: TextFileEncoding(encoding: .utf8, hasByteOrderMark: hasBOM))
        } else if let latin1 = String(data: data, encoding: .isoLatin1) {
            self.init(text: latin1, encoding: TextFileEncoding(encoding: .isoLatin1, hasByteOrderMark: false))
        } else {
            return nil
        }
    }

    /// `newText` in the file's own bytes — see ``TextFileEncoding/data(for:)``.
    public func data(for newText: String) -> Data? { encoding.data(for: newText) }
}

/// The encoding a text file was read in, and whether it began with a UTF-8 byte-order mark,
/// so that new text can be written back in the file's own bytes.
public struct TextFileEncoding: Sendable, Equatable {

    /// The string encoding: UTF-8, else ISO Latin-1.
    public let encoding: String.Encoding

    /// Whether the file began with the UTF-8 byte-order mark `EF BB BF`.
    public let hasByteOrderMark: Bool

    static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Plain UTF-8 with no byte-order mark — what a new file is written as.
    public static let utf8 = TextFileEncoding(encoding: .utf8, hasByteOrderMark: false)

    public init(encoding: String.Encoding, hasByteOrderMark: Bool) {
        self.encoding = encoding
        self.hasByteOrderMark = hasByteOrderMark
    }

    /// `newText` encoded this way, byte-order mark included, or nil when a character
    /// cannot be represented (a `€` into a Latin-1 file).
    public func data(for newText: String) -> Data? {
        guard var out = newText.data(using: encoding) else { return nil }
        if hasByteOrderMark { out.insert(contentsOf: Self.utf8ByteOrderMark, at: 0) }
        return out
    }
}
