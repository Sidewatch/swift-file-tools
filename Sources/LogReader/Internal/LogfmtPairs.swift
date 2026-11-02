//
//  LogfmtPairs.swift
//  LogReader
//
//  A logfmt line's key=value pairs.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// `time=2026-10-01T00:00:00Z level=info msg="hello there" component=api`: keys of letters, digits, `_ . -`;
/// a value bare up to the next space, or double-quoted with `\"` escapes. Only lines that start with a pair and
/// hold at least two count.
struct LogfmtPairs {
    private(set) var pairs: [(key: String, value: String)] = []

    init?(_ bytes: ArraySlice<UInt8>) {
        var c = ByteCursor(bytes)
        while !c.atEnd {
            c.skipSpaces()
            guard !c.atEnd else { break }
            let keyStart = c.i
            while let b = c.peek(), Self.isKeyByte(b) { c.i += 1 }
            let key = bytes[keyStart..<c.i]
            guard !key.isEmpty, c.expect("=") else {
                if pairs.isEmpty { return nil }
                break  // free text after the pairs
            }
            pairs.append((key.text, Self.value(&c)))
        }
        guard pairs.count >= 2 else { return nil }
    }

    subscript(key: String) -> String? { pairs.first { $0.key == key }?.value }

    private static func isKeyByte(_ b: UInt8) -> Bool {
        ByteCursor.isLetter(b) || ByteCursor.isDigit(b) || b == UInt8(ascii: "_") || b == UInt8(ascii: ".") || b == UInt8(ascii: "-")
    }

    private static func value(_ c: inout ByteCursor) -> String {
        guard c.expect("\"") else { return c.word().text }
        var out: [UInt8] = []
        while let b = c.peek() {
            c.i += 1
            if b == UInt8(ascii: "\\"), let next = c.peek() {
                out.append(next)
                c.i += 1
                continue
            }
            if b == UInt8(ascii: "\"") { break }
            out.append(b)
        }
        return String(decoding: out, as: UTF8.self)
    }
}
