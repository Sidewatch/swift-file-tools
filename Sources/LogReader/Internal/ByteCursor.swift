//
//  ByteCursor.swift
//  LogReader
//
//  A position in one line's bytes, and the small reads every log format's header is made of.
//
//  Created by David Sherlock on 11/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// A position in a line's bytes. Every read either consumes what it matched and returns it, or
/// returns nil and leaves the position where it was, so a parser can try one shape and then another.
struct ByteCursor {
    let bytes: ArraySlice<UInt8>
    var i: Int

    init(_ bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
        i = bytes.startIndex
    }

    var atEnd: Bool { i >= bytes.endIndex }
    /// The byte `k` places on, or nil past the end.
    func peek(_ k: Int = 0) -> UInt8? { i + k < bytes.endIndex ? bytes[i + k] : nil }
    /// How far into the line the cursor is.
    var offset: Int { i - bytes.startIndex }
    /// The bytes from the cursor to the end.
    var rest: ArraySlice<UInt8> { bytes[min(i, bytes.endIndex)...] }

    static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
    static func isSpace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 }
    static func isLetter(_ b: UInt8) -> Bool { (b | 0x20) >= 0x61 && (b | 0x20) <= 0x7A }

    /// Exactly `n` digits, as a number.
    mutating func digits(_ n: Int) -> Int? {
        guard i + n <= bytes.endIndex else { return nil }
        var v = 0
        for k in 0..<n {
            let b = bytes[i + k]
            guard Self.isDigit(b) else { return nil }
            v = v * 10 + Int(b - 0x30)
        }
        i += n
        return v
    }

    /// One to `max` digits, as a number and how many there were.
    mutating func someDigits(max: Int = 18) -> (value: Int, count: Int)? {
        var v = 0, n = 0
        while n < max, let b = peek(n), Self.isDigit(b) {
            v = v * 10 + Int(b - 0x30)
            n += 1
        }
        guard n > 0 else { return nil }
        i += n
        return (v, n)
    }

    /// The byte `c`, consumed.
    mutating func expect(_ c: Unicode.Scalar) -> Bool {
        guard peek() == UInt8(c.value) else { return false }
        i += 1
        return true
    }

    /// The ASCII text `s` exactly, consumed.
    mutating func expect(_ s: String) -> Bool {
        let u = Array(s.utf8)
        guard i + u.count <= bytes.endIndex, bytes[i..<i + u.count].elementsEqual(u) else { return false }
        i += u.count
        return true
    }

    /// Spaces and tabs, consumed; how many.
    @discardableResult mutating func skipSpaces() -> Int {
        let start = i
        while let b = peek(), Self.isSpace(b) { i += 1 }
        return i - start
    }

    /// The bytes up to the next space or the end, consumed (empty at a space).
    mutating func word() -> ArraySlice<UInt8> {
        let start = i
        while let b = peek(), !Self.isSpace(b) { i += 1 }
        return bytes[start..<i]
    }

    /// The bytes up to (not including) `c`, consumed with `c`; nil when `c` does not come before the end.
    mutating func until(_ c: Unicode.Scalar) -> ArraySlice<UInt8>? {
        let target = UInt8(c.value)
        var k = i
        while k < bytes.endIndex, bytes[k] != target { k += 1 }
        guard k < bytes.endIndex else { return nil }
        let out = bytes[i..<k]
        i = k + 1
        return out
    }

    /// A three-letter English month name (`Jan` … `Dec`, any case), as 1 … 12.
    mutating func monthName() -> Int? {
        guard i + 3 <= bytes.endIndex else { return nil }
        let key = String(decoding: bytes[i..<i + 3], as: UTF8.self).lowercased()
        guard let m = Self.months[key] else { return nil }
        i += 3
        return m
    }

    /// A three-letter English weekday name, consumed (its value is not needed).
    mutating func weekdayName() -> Bool {
        guard i + 3 <= bytes.endIndex else { return false }
        let key = String(decoding: bytes[i..<i + 3], as: UTF8.self).lowercased()
        guard Self.weekdays.contains(key) else { return false }
        i += 3
        return true
    }

    private static let months = [
        "jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6, "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12,
    ]
    private static let weekdays: Set<String> = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
}

extension ArraySlice<UInt8> {
    /// The bytes as text (a bad UTF-8 sequence as U+FFFD).
    var text: String { String(decoding: self, as: UTF8.self) }
}
