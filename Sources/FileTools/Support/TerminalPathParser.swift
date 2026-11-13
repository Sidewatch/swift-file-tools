//
//  TerminalPathParser.swift
//  FileTools
//
//  Extracts a clickable file reference from a line of terminal output — the
//  `path/to/File.swift:42:10` style an agent prints when it edits a file or reports an error.
//
//  Created by David Sherlock on 7/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
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
        /// The path as printed, not yet resolved against a project.
        public let path: String
        /// The 1-based line, when one trailed the path.
        public let line: Int?
        /// The 1-based column, when one trailed the line.
        public let column: Int?
        /// Creates a match.
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
        if col == chars.count { col -= 1 }  // clicked one past the end
        guard col >= 0, col < chars.count, !isBoundary(chars[col]) else { return nil }

        var start = col, end = col
        while start > 0, !isBoundary(chars[start - 1]) { start -= 1 }
        while end < chars.count - 1, !isBoundary(chars[end + 1]) { end += 1 }
        // `src/a.ts(12,5)` — tsc's and MSBuild's shape. The parentheses are token
        // boundaries, so the click lands on the path or on `12,5`; either way the
        // reference is the path with the position that follows it.
        if end + 1 < chars.count, chars[end + 1] == "(", let close = positionSuffixEnd(chars, from: end + 1) {
            end = close  // clicked the path: take the suffix along
        } else {
            // Clicked inside the parentheses: walk back over the digits and comma to the
            // "(" — the reference is the token before it.
            var open = start - 1
            while open >= 0, chars[open].isNumber || chars[open] == "," { open -= 1 }
            if open >= 1, chars[open] == "(", !isBoundary(chars[open - 1]),
                let close = positionSuffixEnd(chars, from: open), close >= end
            {
                end = close
                start = open - 1
                while start > 0, !isBoundary(chars[start - 1]) { start -= 1 }
            }
        }
        guard var found = parse(String(chars[start...end])) else { return nil }
        // `File "app/main.py", line 12, in run` — Python's traceback, and `"a.rb", line 3, column 9`:
        // the position is written after the closing quote, outside the token.
        if found.line == nil, let position = spokenPosition(chars, after: end) {
            found = Match(path: found.path, line: position.line, column: position.column)
        }
        return found
    }

    /// The `, line N` (and `, column C`) written after a quoted path, starting just past the
    /// token that ends at `end`; nil when what follows is not that.
    private static func spokenPosition(_ chars: [Character], after end: Int) -> (line: Int, column: Int?)? {
        let rest = String(chars[min(end + 1, chars.count)...])
        guard let match = spokenPositionPattern.firstMatch(in: rest, range: NSRange(location: 0, length: (rest as NSString).length)),
            let line = Int((rest as NSString).substring(with: match.range(at: 1)))
        else { return nil }
        let column = match.range(at: 2).location == NSNotFound ? nil : Int((rest as NSString).substring(with: match.range(at: 2)))
        return (line, column)
    }

    private static let spokenPositionPattern = try! NSRegularExpression(pattern: #"^["']?,\s+line\s+(\d+)(?:,\s+column\s+(\d+))?"#)

    /// The index of the `)` closing a `(line,col)` or `(line)` suffix that starts with the
    /// `(` at `open`, or nil when what follows is not that shape.
    private static func positionSuffixEnd(_ chars: [Character], from open: Int) -> Int? {
        var k = open + 1
        var sawDigit = false, sawComma = false
        while k < chars.count {
            let c = chars[k]
            if c.isNumber {
                sawDigit = true
            } else if c == ",", sawDigit, !sawComma {
                sawComma = true; sawDigit = false
            } else if c == ")" {
                return sawDigit ? k : nil
            } else {
                return nil
            }
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
        if let anchored = anchoredPosition(token) { return anchored }
        // `src/a.swift:10-14` — a range of lines: the reference is its first line.
        if let dash = token.lastIndex(of: "-"), let colon = token.lastIndex(of: ":"), colon < dash,
            Int(token[token.index(after: dash)...]) != nil, Int(token[token.index(after: colon)..<dash]) != nil
        {
            token = String(token[..<dash])
        }

        var path = token
        var line: Int?
        var column: Int?
        let parts = token.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 2 {
            var idx = parts.count - 1
            var trailing: [Int] = []  // collected end-first: [col?, line]
            while idx >= 1, trailing.count < 2, let n = Int(parts[idx]) {
                trailing.append(n); idx -= 1
            }
            if !trailing.isEmpty {
                path = parts[0...idx].joined(separator: ":")
                if trailing.count == 2 { column = trailing[0]; line = trailing[1] } else { line = trailing[0] }
            }
        }

        guard looksLikePath(path) else { return nil }
        return Match(path: path, line: line, column: column)
    }

    /// `path#L12`, `path#L12C3`, `path#L12-L14`: the line anchor a link to a hosted file carries,
    /// which agents copy into their prose.
    private static func anchoredPosition(_ token: String) -> Match? {
        guard let hash = token.lastIndex(of: "#") else { return nil }
        let anchor = token[token.index(after: hash)...]
        guard anchor.first == "L" else { return nil }
        let digits = anchor.dropFirst().prefix { $0.isNumber }
        guard let line = Int(digits) else { return nil }
        var rest = anchor.dropFirst().dropFirst(digits.count)
        var column: Int?
        if rest.first == "C" || rest.first == ":" {
            let columnDigits = rest.dropFirst().prefix { $0.isNumber }
            column = Int(columnDigits)
            rest = rest.dropFirst().dropFirst(columnDigits.count)
        }
        // What is left is nothing, or the end of a range (`-L14`).
        guard rest.isEmpty || (rest.first == "-" && rest.dropFirst().allSatisfy { $0 == "L" || $0 == "C" || $0.isNumber }) else {
            return nil
        }
        let path = String(token[..<hash])
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

    // MARK: - Finding the file a printed path means

    /// The paths a printed `path` may mean, most literal first: as written, then without the
    /// `a/` or `b/` a diff header puts before a repository path (`--- a/src/x.swift`).
    public static func candidates(for path: String) -> [String] {
        guard path.hasPrefix("a/") || path.hasPrefix("b/"), path.count > 2 else { return [path] }
        return [path, String(path.dropFirst(2))]
    }

    /// The file `match` names: an absolute path as it is; a relative one under the first of `bases`
    /// that holds it — the terminal's working directory, then the project and repository roots,
    /// since an agent prints paths from the repository's root whatever folder its shell stands in
    /// — trying each of ``candidates(for:)``. Nil when no such file exists. `isFile` answers
    /// whether a regular file is at a path.
    public static func resolve(_ match: Match, bases: [URL], isFile: (URL) -> Bool) -> URL? {
        for candidate in candidates(for: match.path) {
            if candidate.hasPrefix("/") {
                let url = URL(fileURLWithPath: candidate)
                if isFile(url) { return url }
                continue
            }
            for base in bases {
                // `appendingPathComponent` treats `base` as a directory whether or not it ends in a slash.
                let url = base.appendingPathComponent(candidate).standardizedFileURL
                if isFile(url) { return url }
            }
        }
        return nil
    }

    /// The whole logical line a click on `rows[row]` is in, and the click's place in it: a row that
    /// fills the terminal's width runs on into the next (the terminal wrapped it), so a path cut by
    /// the right edge is read whole. `isFull` says whether a row fills the width; at most
    /// `maximumRows` rows are joined.
    public static func logicalLine(
        rows: [String], row: Int, column: Int, maximumRows: Int = 8, isFull: (String) -> Bool
    ) -> (line: String, column: Int) {
        guard rows.indices.contains(row) else { return ("", column) }
        var first = row, last = row
        while first > 0, row - first < maximumRows, isFull(rows[first - 1]) { first -= 1 }
        while last + 1 < rows.count, last - row < maximumRows, isFull(rows[last]) { last += 1 }
        let before = rows[first..<row].reduce(0) { $0 + $1.count }
        return (rows[first...last].joined(), before + column)
    }
}
