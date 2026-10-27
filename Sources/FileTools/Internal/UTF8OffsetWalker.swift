//
//  UTF8OffsetWalker.swift
//  FileTools
//
//  UTF-16 offsets into text decoded from UTF-8 mapped back to offsets into the bytes, invalid sequences included.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// Maps UTF-16 offsets into the text `String(decoding:as: UTF8.self)` makes of some bytes back to offsets into those
/// bytes, walking forward only. The decoder puts one U+FFFD for each invalid sequence, however many bytes it spans —
/// the same maximal pieces `Unicode.UTF8.ForwardParser` reports — so the walk stays on the bytes where the text's own
/// UTF-8 would drift by two bytes a repair.
struct UTF8OffsetWalker {
    private var iterator: ArraySlice<UInt8>.Iterator
    private var parser = Unicode.UTF8.ForwardParser()
    /// Where the walk has got to, in the text and in the bytes.
    private var utf16 = 0
    private var byte = 0

    init(_ bytes: ArraySlice<UInt8>) { iterator = bytes.makeIterator() }

    /// The byte offset of the character at UTF-16 offset `target`, which must not be before the last one asked for;
    /// the bytes' end when `target` is past the text's.
    mutating func byteOffset(ofUTF16 target: Int) -> Int {
        while utf16 < target {
            switch parser.parseScalar(from: &iterator) {
            case .valid(let encoded):
                byte += encoded.count
                utf16 += encoded.count == 4 ? 2 : 1
            case .error(let length):
                byte += length
                utf16 += 1
            case .emptyInput:
                return byte
            }
        }
        return byte
    }
}
