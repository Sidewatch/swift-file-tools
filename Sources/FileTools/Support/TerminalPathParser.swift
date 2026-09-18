//
//  TerminalPathParser.swift
//  FileTools
//
//  Extracts a clickable file reference from a line of terminal output — the
//  `path/to/File.swift:42:10` style an agent prints when it edits a file or reports an error.
//
//  Created by David Sherlock on 7/21/26.
//

import Foundation

/// Extracts a clickable file reference from a line of terminal output — the
/// `path/to/File.swift:42:10` style an agent prints when it edits a file or reports an
/// error. Pure and tested; the app decides the click cell, calls ``match(in:at:)`` to pull
/// the token there, then resolves the path against the project and opens it at the line.
public enum TerminalPathParser {

    /// A parsed file reference: a path plus the optional 1-based line and column that
    /// trailed it (`file:line:col`).
    public struct Match: Equatable {
        public let path: String
        public let line: Int?
        public let column: Int?
        public init(path: String, line: Int? = nil, column: Int? = nil) {
            self.path = path; self.line = line; self.column = column
        }
    }

    /// Characters that bound a path token in terminal output (whitespace + common
    /// wrapping punctuation an agent or shell puts around a path).
    private static func isBoundary(_ c: Character) -> Bool {
        c == " " || c == "\t" || c == "\"" || c == "'" || c == "`"
            || c == "(" || c == ")" || c == "[" || c == "]" || c == "{" || c == "}"
            || c == "<" || c == ">" || c == "|" || c == "," || c == ";"
    }

    /// The token at 0-based character index `column` in `line`, parsed into a path plus
    /// optional line/column. Returns nil when there's no plausible path there (clicked
    /// whitespace, or the token doesn't look like a file). A click just past a short
    /// token's end still resolves the token.
    public static func match(in line: String, at column: Int) -> Match? {
        let chars = Array(line)
        guard !chars.isEmpty else { return nil }
        var col = column
        if col == chars.count { col -= 1 }                    // clicked one past the end
        guard col >= 0, col < chars.count, !isBoundary(chars[col]) else { return nil }

        var start = col, end = col
        while start > 0, !isBoundary(chars[start - 1]) { start -= 1 }
        while end < chars.count - 1, !isBoundary(chars[end + 1]) { end += 1 }
        // `src/a.ts(12,5)` — tsc's and MSBuild's shape. The parentheses are token
        // boundaries, so the click lands on the path or on `12,5`; either way the
        // reference is the path with the position that follows it.
        if end + 1 < chars.count, chars[end + 1] == "(", let close = positionSuffixEnd(chars, from: end + 1) {
            end = close                                       // clicked the path: take the suffix along
        } else {
            // Clicked inside the parentheses: walk back over the digits and comma to the
            // "(" — the reference is the token before it.
            var open = start - 1
            while open >= 0, chars[open].isNumber || chars[open] == "," { open -= 1 }
            if open >= 1, chars[open] == "(", !isBoundary(chars[open - 1]),
               let close = positionSuffixEnd(chars, from: open), close >= end {
                end = close
                start = open - 1
                while start > 0, !isBoundary(chars[start - 1]) { start -= 1 }
            }
        }
        return parse(String(chars[start...end]))
    }

    /// The index of the `)` closing a `(line,col)` or `(line)` suffix that starts with the
    /// `(` at `open`, or nil when what follows is not that shape.
    private static func positionSuffixEnd(_ chars: [Character], from open: Int) -> Int? {
        var k = open + 1
        var sawDigit = false, sawComma = false
        while k < chars.count {
            let c = chars[k]
            if c.isNumber { sawDigit = true }
            else if c == ",", sawDigit, !sawComma { sawComma = true; sawDigit = false }
            else if c == ")" { return sawDigit ? k : nil }
            else { return nil }
            k += 1
        }
        return nil
    }

    /// Parses a single token like `src/Foo.swift:42:10`, `./a.ts:5`, `src/a.ts(12,5)` or
    /// `/abs/x.rb`. Strips wrapping quotes/brackets and trailing sentence punctuation,
    /// peels a trailing `:line` / `:line:col` / `(line,col)`, and returns nil unless the
    /// leading portion looks like a path (has a `/` or a short file extension). URLs
    /// (`scheme://…`) are rejected — SwiftTerm opens those itself.
    public static func parse(_ rawToken: String) -> Match? {
        if rawToken.contains("://") { return nil }
        var token = rawToken
        while let last = token.last, ".,;:".contains(last) { token.removeLast() }
        if let paren = parenthesisedPosition(token) { return paren }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>"))
        while let last = token.last, ".,;:".contains(last) { token.removeLast() }
        while let first = token.first, first == ":" { token.removeFirst() }
        guard !token.isEmpty else { return nil }

        var path = token
        var line: Int?
        var column: Int?
        let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2 {
            var idx = parts.count - 1
            var trailing: [Int] = []                          // collected end-first: [col?, line]
            while idx >= 1, trailing.count < 2, let n = Int(parts[idx]) {
                trailing.append(n); idx -= 1
            }
            if !trailing.isEmpty {
                path = parts[0...idx].joined(separator: ":")
                if trailing.count == 2 { column = trailing[0]; line = trailing[1] }
                else { line = trailing[0] }
            }
        }

        guard looksLikePath(path) else { return nil }
        return Match(path: path, line: line, column: column)
    }

    /// `path(line,col)` / `path(line)`: the position tsc, MSBuild and the C# compiler print.
    private static func parenthesisedPosition(_ token: String) -> Match? {
        guard token.hasSuffix(")"), let open = token.lastIndex(of: "(") else { return nil }
        let inner = token[token.index(after: open)..<token.index(before: token.endIndex)]
        let parts = inner.split(separator: ",", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), let line = Int(parts[0]) else { return nil }
        let column = parts.count == 2 ? Int(parts[1]) : nil
        if parts.count == 2, column == nil { return nil }
        let path = String(token[..<open]).trimmingCharacters(in: CharacterSet(charactersIn: "\"'`[]{}<>"))
        guard looksLikePath(path) else { return nil }
        return Match(path: path, line: line, column: column)
    }

    /// A path token has a directory separator or a short (≤8 alphanumeric) file extension.
    private static func looksLikePath(_ s: String) -> Bool {
        if s.contains("/") { return true }
        guard let dot = s.lastIndex(of: "."), dot > s.startIndex, dot < s.index(before: s.endIndex)
        else { return false }
        let ext = s[s.index(after: dot)...]
        return ext.count <= 8 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
