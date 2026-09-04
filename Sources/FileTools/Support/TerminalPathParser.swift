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
        return parse(String(chars[start...end]))
    }

    /// Parses a single token like `src/Foo.swift:42:10`, `./a.ts:5`, or `/abs/x.rb`.
    /// Strips wrapping quotes/brackets and trailing sentence punctuation, peels a trailing
    /// `:line` / `:line:col`, and returns nil unless the leading portion looks like a path
    /// (has a `/` or a short file extension). URLs (`scheme://…`) are rejected — SwiftTerm
    /// opens those itself.
    public static func parse(_ rawToken: String) -> Match? {
        if rawToken.contains("://") { return nil }
        var token = rawToken.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`()[]{}<>"))
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

    /// A path token has a directory separator or a short (≤8 alphanumeric) file extension.
    private static func looksLikePath(_ s: String) -> Bool {
        if s.contains("/") { return true }
        guard let dot = s.lastIndex(of: "."), dot > s.startIndex, dot < s.index(before: s.endIndex)
        else { return false }
        let ext = s[s.index(after: dot)...]
        return ext.count <= 8 && ext.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
