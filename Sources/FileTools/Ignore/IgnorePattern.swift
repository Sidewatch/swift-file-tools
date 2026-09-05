//
//  IgnorePattern.swift
//  FileTools
//
//  One compiled rule from a `.gitignore`-syntax ignore file. A pattern is parsed once
//  (`init?(line:)`) into a small set of path-segment matchers, then reused across a whole tree
//  walk.
//
//  Created by David Sherlock on 9/3/26.
//

import Foundation

/// One compiled rule from a `.gitignore`-syntax ignore file.
///
/// A pattern is parsed once (`init?(line:)`) into a small set of path-segment
/// matchers, then reused across a whole tree walk. Matching is always against a
/// path that has already been made relative to the *pattern's own directory* —
/// see ``IgnoreFile`` for that bookkeeping.
///
/// ```swift
/// let p = IgnorePattern(line: "*.log")!
/// p.matches(path: "build/output.log", isDirectory: false)   // true — unanchored
/// ```
///
/// Matching is always case-sensitive, matching git's own behaviour on
/// case-sensitive filesystems.
public struct IgnorePattern: Sendable, Equatable {

    /// The pattern's source line, exactly as read from the file (used for
    /// diagnostics and tests; not used for matching).
    public let raw: String

    /// `true` for a `!`-negated pattern: a file this pattern matches is
    /// re-included, undoing an earlier pattern's exclusion — unless a parent
    /// directory was itself excluded (see ``IgnoreStack``).
    public let negated: Bool

    /// `true` when the pattern ends in a (stripped) `/` and therefore matches
    /// directories only; `false` when it can match both files and directories.
    public let directoryOnly: Bool

    /// `true` when the pattern contains a `/` anywhere except as the very last
    /// character — meaning it is anchored to its ignore file's own directory.
    /// `false` means the pattern has no interior slash and so may match at any
    /// depth below that directory.
    public let anchored: Bool

    /// Compiled path-segment matchers, already unescaped. Empty (and therefore
    /// never matching) for a malformed line, e.g. one ending in a lone backslash.
    private let segments: [Segment]

    /// Parses one line of an ignore file.
    ///
    /// - Parameter line: One line of file text, without its line terminator.
    /// - Returns: `nil` for a blank line, a `#` comment, or a line that trims
    ///   away to nothing — none of these contribute a rule.
    public init?(line: String) {
        self.raw = line

        // A line starting with an *unescaped* '#' is a comment. Checking the
        // literal first character (rather than something trimmed) means an
        // escaped "\#name" — whose first character is '\', not '#' — correctly
        // falls through to be parsed as a literal pattern below.
        guard let first = line.first, first != "#" else { return nil }

        // Trailing spaces are ignored unless escaped with a backslash.
        let trimmed = IgnorePattern.trimTrailingUnescapedSpaces(line)
        guard !trimmed.isEmpty else { return nil }   // blank after trimming

        var body = trimmed

        // "!" negates; "\!" is a literal leading '!' and falls through untouched.
        var negated = false
        if body.first == "!" {
            negated = true
            body.removeFirst()
        }
        guard !body.isEmpty else { return nil }

        // A single trailing, unescaped '/' means directory-only.
        var directoryOnly = false
        if body.hasSuffix("/") {
            directoryOnly = true
            body.removeLast()
        }
        guard !body.isEmpty else { return nil }

        // A backslash at the very end of the pattern is invalid and never matches.
        if IgnorePattern.hasTrailingUnescapedBackslash(body) {
            self.negated = negated
            self.directoryOnly = directoryOnly
            self.anchored = false
            self.segments = []
            return
        }

        // A leading '/' anchors the pattern to the ignore file's own directory.
        let hasLeadingSlash = body.hasPrefix("/")
        if hasLeadingSlash { body.removeFirst() }

        let rawSegments = body.components(separatedBy: "/")
        let anchored = hasLeadingSlash || rawSegments.count > 1

        var segments = rawSegments.map { Segment.compile($0, allowDoubleStar: rawSegments.count > 1) }
        if !anchored {
            // No slash anywhere: the pattern may match at any depth below the
            // ignore file's directory, which is exactly what a leading "**/"
            // (zero-or-more path segments) gives us.
            segments.insert(.doubleStar, at: 0)
        }

        self.negated = negated
        self.directoryOnly = directoryOnly
        self.anchored = anchored
        self.segments = segments
    }

    /// Tests whether this pattern matches `path` — already relative to the
    /// pattern's OWN directory (i.e. the ignore file's directory has been
    /// stripped), `/`-separated, no leading slash.
    ///
    /// - Parameters:
    ///   - path: The candidate path, relative to this pattern's directory.
    ///   - isDirectory: Whether the candidate is a directory. A `directoryOnly`
    ///     pattern never matches a file.
    func matches(path: String, isDirectory: Bool) -> Bool {
        guard !segments.isEmpty else { return false }
        if directoryOnly, !isDirectory { return false }
        let pathSegments = path.isEmpty ? [] : path.components(separatedBy: "/")
        return Segment.match(segments, pathSegments)
    }

    // MARK: - Line pre-processing

    /// Strips trailing spaces, EXCEPT a trailing space immediately preceded by
    /// an odd number of backslashes (i.e. one that is itself escaped) — at which
    /// point trimming stops entirely, since everything from there leftward is
    /// untouched pattern content. The escaping backslash is left in place; it is
    /// consumed later, generically, by ``Segment/compile(_:allowDoubleStar:)``.
    private static func trimTrailingUnescapedSpaces(_ s: String) -> String {
        var chars = Array(s)
        while chars.last == " " {
            var backslashes = 0
            var i = chars.count - 2
            while i >= 0, chars[i] == "\\" { backslashes += 1; i -= 1 }
            if backslashes % 2 == 1 { break }   // escaped — stop trimming
            chars.removeLast()
        }
        return String(chars)
    }

    /// `true` if `s` ends in an odd run of backslashes — an unterminated escape,
    /// which git treats as an invalid pattern that never matches anything.
    private static func hasTrailingUnescapedBackslash(_ s: String) -> Bool {
        guard s.hasSuffix("\\") else { return false }
        var backslashes = 0
        var i = s.index(before: s.endIndex)
        while true {
            guard s[i] == "\\" else { break }
            backslashes += 1
            if i == s.startIndex { break }
            i = s.index(before: i)
        }
        return backslashes % 2 == 1
    }
}

/// A single component of a compiled pattern: either a literal glob (matches
/// exactly one path segment) or `**` (matches zero or more path segments).
private enum Segment: Sendable, Equatable {
    case glob([GlobToken])
    case doubleStar

    /// Compiles one `/`-delimited raw segment string into a ``Segment``.
    ///
    /// `allowDoubleStar` is `true` only when the ORIGINAL pattern actually
    /// contained a `/` (i.e. this segment has at least one neighbour) — a bare
    /// `**` with no adjacent slash anywhere in the pattern is, per the spec,
    /// "considered regular asterisks" and compiled as an ordinary glob instead.
    static func compile(_ raw: String, allowDoubleStar: Bool) -> Segment {
        if allowDoubleStar, raw == "**" { return .doubleStar }
        return .glob(GlobToken.compile(raw))
    }

    /// Matches a full sequence of compiled `Segment`s against a full sequence of
    /// path components — both ends must be entirely consumed.
    static func match(_ pattern: [Segment], _ path: [String]) -> Bool {
        matchFrom(pattern, 0, path, 0)
    }

    private static func matchFrom(_ pattern: [Segment], _ pi: Int, _ path: [String], _ si: Int) -> Bool {
        if pi == pattern.count { return si == path.count }
        switch pattern[pi] {
        case .glob(let tokens):
            guard si < path.count, GlobToken.match(tokens, path[si]) else { return false }
            return matchFrom(pattern, pi + 1, path, si + 1)

        case .doubleStar:
            if pi + 1 == pattern.count {
                // Last segment. A trailing "/**" after at least one concrete
                // segment matches only what's genuinely INSIDE that directory
                // (git: "abc/**" matches files inside abc, not abc itself), so
                // it needs at least one more path component. A pattern that is
                // "**" on its own (pi == 0) has nothing to be "inside" of, so it
                // matches everything, including zero remaining components.
                let minimum = pi > 0 ? 1 : 0
                return path.count - si >= minimum
            }
            // A leading or interior "**" matches zero or more path components —
            // try every possible split point.
            var k = 0
            while si + k <= path.count {
                if matchFrom(pattern, pi + 1, path, si + k) { return true }
                k += 1
            }
            return false
        }
    }
}

/// One atom within a single path segment's glob.
private enum GlobToken: Sendable, Equatable {
    case literal(Character)
    case anyChar                                     // '?'
    case anyRun                                      // '*' (zero or more, never crosses '/')
    case charClass(negated: Bool, singles: Set<Character>, ranges: [ClosedRange<Character>])

    /// Compiles a single (already slash-free) path segment's text into tokens,
    /// resolving backslash escapes as it goes: `\` followed by ANY character
    /// yields that character as a literal, which covers the spec's explicit
    /// list (`* ? [ # !` and space) and then some.
    static func compile(_ text: String) -> [GlobToken] {
        var tokens: [GlobToken] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            switch c {
            case "\\":
                if i + 1 < chars.count {
                    tokens.append(.literal(chars[i + 1]))
                    i += 2
                } else {
                    i += 1   // trailing lone backslash inside a segment: drop it
                }
            case "*":
                tokens.append(.anyRun)
                i += 1
            case "?":
                tokens.append(.anyChar)
                i += 1
            case "[":
                if let (token, consumed) = parseClass(chars, from: i) {
                    tokens.append(token)
                    i += consumed
                } else {
                    tokens.append(.literal("["))   // unterminated class: literal '['
                    i += 1
                }
            default:
                tokens.append(.literal(c))
                i += 1
            }
        }
        return tokens
    }

    /// Parses a `[...]` character class starting at `chars[i]` (which must be
    /// `[`). Returns `nil` (unterminated) if no closing `]` is found, in which
    /// case the caller treats the `[` as a literal character instead — the
    /// conventional glob fallback.
    private static func parseClass(_ chars: [Character], from i: Int) -> (GlobToken, Int)? {
        var j = i + 1
        var negated = false
        if j < chars.count, chars[j] == "!" || chars[j] == "^" {
            negated = true
            j += 1
        }
        var singles: Set<Character> = []
        var ranges: [ClosedRange<Character>] = []
        var first = true
        while j < chars.count {
            if chars[j] == "]", !first {
                let consumed = j - i + 1
                return (.charClass(negated: negated, singles: singles, ranges: ranges), consumed)
            }
            first = false
            var ch = chars[j]
            if ch == "\\", j + 1 < chars.count {
                j += 1
                ch = chars[j]
            }
            // A range like "a-z", but not when '-' is the class's last character
            // before ']' (then it's a literal '-').
            if j + 2 < chars.count, chars[j + 1] == "-", chars[j + 2] != "]" {
                let hi = chars[j + 2]
                if ch <= hi {
                    ranges.append(ch...hi)
                } else {
                    singles.insert(ch); singles.insert("-"); singles.insert(hi)
                }
                j += 3
            } else {
                singles.insert(ch)
                j += 1
            }
        }
        return nil   // no closing ']'
    }

    /// Matches compiled `tokens` against one full path segment's text.
    static func match(_ tokens: [GlobToken], _ text: String) -> Bool {
        matchFrom(tokens, 0, Array(text), 0)
    }

    private static func matchFrom(_ tokens: [GlobToken], _ ti: Int, _ text: [Character], _ ci: Int) -> Bool {
        if ti == tokens.count { return ci == text.count }
        switch tokens[ti] {
        case .literal(let ch):
            guard ci < text.count, text[ci] == ch else { return false }
            return matchFrom(tokens, ti + 1, text, ci + 1)
        case .anyChar:
            guard ci < text.count else { return false }
            return matchFrom(tokens, ti + 1, text, ci + 1)
        case .charClass(let negated, let singles, let ranges):
            guard ci < text.count else { return false }
            let inClass = singles.contains(text[ci]) || ranges.contains { $0.contains(text[ci]) }
            guard inClass != negated else { return false }
            return matchFrom(tokens, ti + 1, text, ci + 1)
        case .anyRun:
            var k = 0
            while ci + k <= text.count {
                if matchFrom(tokens, ti + 1, text, ci + k) { return true }
                k += 1
            }
            return false
        }
    }
}
