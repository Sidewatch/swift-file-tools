//
//  ProjectSearch.swift
//  SwiftFileTools
//
//  Fast, recursive, project-wide text search over a directory. Runs
//  synchronously; callers should dispatch it to a background queue.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Fast recursive project-wide text search.
///
/// Runs synchronously on whatever queue it's called from — callers should
/// dispatch it to the background. Noise directories (see ``SkippedDirs``),
/// oversized files and binary files are skipped automatically.
///
/// ```swift
/// let hits = ProjectSearch.search(query: "TODO", in: root,
///                                 caseSensitive: false, regex: false,
///                                 isCancelled: { false })
/// ```
public enum ProjectSearch {
    /// Files bigger than this are skipped (likely generated/minified/lock files).
    private static let maxFileBytes = 2_000_000
    /// The search stops after this many matches across the whole project.
    private static let maxTotalMatches = 5_000
    /// Per-file cap; scanning of a file stops once it is reached.
    private static let maxMatchesPerFile = 200

    /// Recursively searches `root` for `query`.
    ///
    /// - Parameters:
    ///   - query: The text (or regular-expression pattern) to search for. An
    ///     empty query returns no results.
    ///   - root: The directory to search.
    ///   - caseSensitive: Whether matching is case-sensitive.
    ///   - regex: When `true`, `query` is treated as a regular expression; an
    ///     invalid pattern yields no results.
    ///   - isCancelled: Polled between files; return `true` to stop early.
    /// - Returns: One ``SearchFileResult`` per matching file, sorted by path.
    /// - Note: Performs blocking file I/O for the whole walk — dispatch to a
    ///   background queue when searching a large project.
    public static func search(
        query: String,
        in root: URL,
        caseSensitive: Bool,
        regex: Bool,
        isCancelled: () -> Bool,
        include: ((URL) -> Bool)? = nil
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }

        let regexObj: NSRegularExpression? = regex
            ? try? NSRegularExpression(pattern: query,
                                       options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return [] }   // invalid pattern

        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        var results: [SearchFileResult] = []
        var total = 0
        enumerateTextFiles(in: root, isCancelled: isCancelled, include: include) { url, text, _ in
            guard mightMatch(text) else { return true }
            let fileMatches = matches(in: text, query: query,
                                      caseSensitive: caseSensitive, regex: regexObj)
            guard !fileMatches.isEmpty else { return true }
            results.append(SearchFileResult(url: url, matches: fileMatches))
            total += fileMatches.count
            return total < maxTotalMatches   // stop the walk once the global cap is hit
        }

        results.sort { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
        return results
    }

    /// Searches an EXPLICIT file list instead of walking a root — the
    /// "changed files only" scope, where the caller already knows the files
    /// (e.g. from `git status`). The same size/binary/encoding guards apply,
    /// so the two entry points can't diverge on what counts as searchable.
    public static func search(
        query: String,
        files: [URL],
        caseSensitive: Bool,
        regex: Bool,
        isCancelled: () -> Bool
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }
        let regexObj: NSRegularExpression? = regex
            ? try? NSRegularExpression(pattern: query,
                                       options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return [] }
        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        var results: [SearchFileResult] = []
        var total = 0
        for url in files {
            if isCancelled() || total >= maxTotalMatches { break }
            guard let (text, _) = readTextFile(url) else { continue }
            guard mightMatch(text) else { continue }
            let fileMatches = matches(in: text, query: query,
                                      caseSensitive: caseSensitive, regex: regexObj)
            guard !fileMatches.isEmpty else { continue }
            results.append(SearchFileResult(url: url, matches: fileMatches))
            total += fileMatches.count
        }
        results.sort { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
        return results
    }

    /// One file through the shared searchability guards: regular, under the size
    /// cap, non-binary, UTF-8-or-Latin-1. The single-file twin of the walk below.
    public static func readTextFile(_ url: URL) -> (text: String, encoding: String.Encoding)? {
        let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attrs?.isRegularFile == true else { return nil }
        if (attrs?.fileSize ?? 0) > maxFileBytes { return nil }
        guard let data = try? Data(contentsOf: url), !data.prefix(4000).contains(0) else { return nil }
        if let utf8 = String(data: data, encoding: .utf8) { return (utf8, .utf8) }
        if let latin1 = String(data: data, encoding: .isoLatin1) { return (latin1, .isoLatin1) }
        return nil
    }

    /// Walks `root` yielding each eligible text file's URL + decoded contents,
    /// applying the shared skip/size/binary guards. `body` returns `false` to stop
    /// the walk early. The single source of truth for "which files are searchable",
    /// shared by ``search(query:in:caseSensitive:regex:isCancelled:)`` and
    /// ``replaceAll(query:in:caseSensitive:regex:replacement:isCancelled:)`` so the
    /// two can never diverge on what they touch.
    private static func enumerateTextFiles(
        in root: URL,
        isCancelled: () -> Bool,
        include: ((URL) -> Bool)? = nil,
        body: (URL, String, String.Encoding) -> Bool
    ) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator {
            if isCancelled() { break }

            let name = url.lastPathComponent
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                if SkippedDirs.names.contains(name) { enumerator.skipDescendants() }
                continue
            }
            if SkippedDirs.names.contains(name) { continue }
            if let include, !include(url) { continue }

            // Only read regular files. Symlinks report the size of the LINK
            // (a few bytes) here while `Data(contentsOf:)` would follow them
            // and read the whole target — bypassing the size guard — and
            // special files (FIFOs, sockets, devices) aren't searchable text.
            let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard attrs?.isRegularFile == true else { continue }

            let size = attrs?.fileSize ?? 0
            if size > maxFileBytes { continue }

            guard let data = try? Data(contentsOf: url),
                  !data.prefix(4000).contains(0)                  // skip binary
            else { continue }
            // Decode as UTF-8, else fall back to Latin-1. Track WHICH so a rewrite
            // (replaceAll) can round-trip the file in its original encoding instead
            // of silently converting a Latin-1 / Windows-1252 file to UTF-8.
            let text: String, encoding: String.Encoding
            if let utf8 = String(data: data, encoding: .utf8) {
                text = utf8; encoding = .utf8
            } else if let latin1 = String(data: data, encoding: .isoLatin1) {
                text = latin1; encoding = .isoLatin1
            } else {
                continue
            }

            if !body(url, text, encoding) { break }
        }
    }

    /// Whole-file pre-check: returns a predicate that is `true` when a file's
    /// text MIGHT contain a match and `false` only when it certainly contains
    /// none — so the (typical) all-miss files skip the per-line walk and its
    /// per-line String/NSString allocations entirely. Literal mode is a single
    /// contiguous whole-text search, which can only over-admit (e.g. a query
    /// containing `\n` passes here but the line walk still finds nothing). Regex
    /// mode recompiles the pattern with `.anchorsMatchLines` so `^`/`$` keep
    /// their per-line meaning; that variant over-admits but never under-admits —
    /// EXCEPT for `\A`/`\z`/`\Z` and negative lookaround, whose meaning genuinely
    /// differs between a line substring and the whole text, so patterns
    /// containing them skip the pre-check and keep the plain per-line walk.
    private static func prefilter(
        query: String,
        caseSensitive: Bool,
        regexMode: Bool
    ) -> (String) -> Bool {
        guard regexMode else {
            let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            return { text in
                (text as NSString).range(of: query, options: opts).location != NSNotFound
            }
        }
        guard !query.contains("\\A"), !query.contains("\\z"), !query.contains("\\Z"),
              !query.contains("(?!"), !query.contains("(?<!") else { return { _ in true } }
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]
        if !caseSensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: query, options: opts) else {
            return { _ in true }
        }
        return { text in
            let full = NSRange(location: 0, length: (text as NSString).length)
            return re.firstMatch(in: text, options: [], range: full) != nil
        }
    }

    /// Finds every match of `query` (or the precompiled `regex`) in `text`,
    /// line by line, capped at `maxMatchesPerFile`.
    private static func matches(
        in text: String,
        query: String,
        caseSensitive: Bool,
        regex: NSRegularExpression?
    ) -> [SearchMatch] {
        var out: [SearchMatch] = []
        var lineNo = 0

        text.enumerateLines { line, stop in
            lineNo += 1
            if out.count >= maxMatchesPerFile {   // per-file cap
                stop = true
                return
            }
            let ns = line as NSString
            let full = NSRange(location: 0, length: ns.length)

            if let regex {
                for m in regex.matches(in: line, options: [], range: full) {
                    if out.count >= maxMatchesPerFile { break }
                    out.append(SearchMatch(line: lineNo, lineText: line, range: m.range))
                }
            } else {
                var searchStart = 0
                let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
                while searchStart < ns.length {
                    let r = ns.range(of: query, options: opts,
                                     range: NSRange(location: searchStart, length: ns.length - searchStart))
                    if r.location == NSNotFound { break }
                    if out.count >= maxMatchesPerFile { break }
                    out.append(SearchMatch(line: lineNo, lineText: line, range: r))
                    searchStart = NSMaxRange(r) > r.location ? NSMaxRange(r) : r.location + 1
                }
            }
        }
        return out
    }

    // MARK: - Replace

    /// Replaces every match of `query` with `replacement` across every searchable
    /// file under `root`. **Destructive** — the caller is expected to confirm first,
    /// ideally by first calling with `commit: false` (a dry run) to get the exact
    /// count it then confirms against.
    ///
    /// Matching mirrors ``search(query:in:caseSensitive:regex:isCancelled:)`` exactly:
    /// the same file set, and the regex is applied **per line** (each line without its
    /// terminator), so `^`/`$` anchor to line boundaries and no pattern can consume a
    /// newline — a replace can therefore never touch or collapse content the search
    /// preview didn't surface. In regex mode `replacement` is an `NSRegularExpression`
    /// template (`$1`, `$2`, … expand); in literal mode it is inserted verbatim. A
    /// rewritten file keeps its original encoding (UTF-8, else Latin-1).
    ///
    /// - Parameters:
    ///   - query: The literal text or regex pattern (same as search — whole-word is
    ///     the caller's `\b(?:…)\b` regex wrap).
    ///   - replacement: The replacement text (regex template when `regex` is true).
    ///   - commit: When `false`, nothing is written — the returned summary is a dry
    ///     run reporting exactly what a `commit: true` call would change.
    ///   - isCancelled: Polled between files; return `true` to stop early. Files
    ///     already written stay written.
    /// - Returns: A ``ReplaceSummary`` of files changed (or that would change), total
    ///   replacements, and files that matched but could not be written.
    /// - Note: Blocking file I/O for the whole walk — dispatch to the background.
    public static func replaceAll(
        query: String,
        in root: URL,
        caseSensitive: Bool,
        regex: Bool,
        replacement: String,
        commit: Bool,
        isCancelled: () -> Bool,
        include: ((URL) -> Bool)? = nil
    ) -> ReplaceSummary {
        guard !query.isEmpty else { return .empty }

        let regexObj: NSRegularExpression?
        if regex {
            let opts: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            guard let r = try? NSRegularExpression(pattern: query, options: opts) else { return .empty }
            regexObj = r
        } else {
            regexObj = nil
        }

        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        var filesChanged = 0, totalReplacements = 0, filesFailed = 0
        enumerateTextFiles(in: root, isCancelled: isCancelled, include: include) { url, text, encoding in
            guard mightMatch(text) else { return true }
            let (newText, count) = replaced(in: text, query: query, caseSensitive: caseSensitive,
                                            regex: regexObj, replacement: replacement)
            guard count > 0, newText != text else { return true }
            // Round-trip in the file's original encoding. A replacement that adds a
            // character the encoding can't represent is a FAILURE, not a change —
            // checked identically in both the dry run and the commit so the dry-run
            // count the caller confirms against exactly equals what commit writes.
            guard let data = newText.data(using: encoding) else { filesFailed += 1; return true }
            if !commit {   // dry run: report what WOULD change, write nothing
                filesChanged += 1
                totalReplacements += count
                return true
            }
            do {
                try data.write(to: url, options: .atomic)
                filesChanged += 1
                totalReplacements += count
            } catch {
                filesFailed += 1
            }
            return true
        }
        return ReplaceSummary(filesChanged: filesChanged, replacements: totalReplacements, filesFailed: filesFailed)
    }

    /// Applies the replacement to one file's contents **line by line** (mirroring
    /// `search`'s per-line matching), preserving each line's original terminator
    /// (`\n`, `\r\n`, none), and returns the new text plus the replacement count.
    /// Returns the input unchanged when nothing matched.
    private static func replaced(
        in text: String,
        query: String,
        caseSensitive: Bool,
        regex: NSRegularExpression?,
        replacement: String
    ) -> (text: String, count: Int) {
        var out = ""
        var count = 0
        // `.byLines` yields each line's content range plus the enclosing range (which
        // includes the terminator); the two tile the whole string, so reassembling
        // content + terminator reproduces the file exactly except at replaced sites.
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byLines) { _, sub, encl, _ in
            let line = String(text[sub])
            let terminator = String(text[sub.upperBound..<encl.upperBound])
            let (replacedLine, n) = replacedInLine(line, query: query, caseSensitive: caseSensitive,
                                                   regex: regex, replacement: replacement)
            out += replacedLine + terminator
            count += n
        }
        return count > 0 ? (out, count) : (text, 0)
    }

    /// One line's replacement: regex template substitution, or a case-(in)sensitive
    /// literal replace counting non-overlapping matches the way `matches` advances.
    private static func replacedInLine(
        _ line: String,
        query: String,
        caseSensitive: Bool,
        regex: NSRegularExpression?,
        replacement: String
    ) -> (String, Int) {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let regex {
            let count = regex.numberOfMatches(in: line, options: [], range: full)
            guard count > 0 else { return (line, 0) }
            return (regex.stringByReplacingMatches(in: line, options: [], range: full, withTemplate: replacement), count)
        }

        let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var count = 0, start = 0
        while start < ns.length {
            let r = ns.range(of: query, options: opts, range: NSRange(location: start, length: ns.length - start))
            if r.location == NSNotFound { break }
            count += 1
            start = NSMaxRange(r) > r.location ? NSMaxRange(r) : r.location + 1
        }
        guard count > 0 else { return (line, 0) }
        return (ns.replacingOccurrences(of: query, with: replacement, options: opts, range: full), count)
    }
}
