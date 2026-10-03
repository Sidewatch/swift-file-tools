//
//  ProjectSearch.swift
//  FileTools
//
//  Fast, recursive, project-wide text search over a directory. Runs
//  synchronously; callers should dispatch it to a background queue.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Fast recursive project-wide text search and replace.
///
/// Runs synchronously on the calling queue, so dispatch it to the background. Noise directories
/// (``SkippedDirs``), oversized files and binary files are skipped.
public enum ProjectSearch {
    /// Files bigger than this are skipped (likely generated/minified/lock files).
    private static let maxFileBytes = 2_000_000
    /// The search stops after this many matches across the whole project.
    private static let maxTotalMatches = 5_000
    /// Per-file cap; scanning of a file stops once it is reached.
    private static let maxMatchesPerFile = 200

    /// Recursively searches `root` for `query`: one ``SearchFileResult`` per matching file,
    /// sorted by path. An empty query or an invalid regex yields nothing; `isCancelled` is
    /// polled between files, `include` filters files and `onProgress` gets the running count.
    /// `onFile` receives each matching file the moment it is found (walk order, on the calling
    /// queue), so a caller can show results before the walk ends.
    public static func search(
        query: String,
        in root: URL,
        caseSensitive: Bool,
        regex: Bool,
        isCancelled: () -> Bool,
        include: ((URL) -> Bool)? = nil,
        onProgress: ((Int) -> Void)? = nil,
        onFile: ((SearchFileResult) -> Void)? = nil
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }

        let regexObj: NSRegularExpression? =
            regex
            ? try? NSRegularExpression(
                pattern: query,
                options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return [] }  // invalid pattern

        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        var results: [SearchFileResult] = []
        var total = 0
        enumerateTextFiles(in: root, isCancelled: isCancelled, include: include, onProgress: onProgress) { url, file in
            let text = file.text
            guard mightMatch(text) else { return true }
            let fileMatches = matches(
                in: text, query: query,
                caseSensitive: caseSensitive, regex: regexObj)
            guard !fileMatches.isEmpty else { return true }
            let found = SearchFileResult(url: url, matches: fileMatches)
            results.append(found)
            onFile?(found)
            total += fileMatches.count
            return total < maxTotalMatches  // stop the walk once the global cap is hit
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
        isCancelled: () -> Bool,
        onProgress: ((Int) -> Void)? = nil,
        onFile: ((SearchFileResult) -> Void)? = nil
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }
        let regexObj: NSRegularExpression? =
            regex
            ? try? NSRegularExpression(
                pattern: query,
                options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return [] }
        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        var results: [SearchFileResult] = []
        var total = 0
        var scanned = 0
        for url in files {
            if isCancelled() || total >= maxTotalMatches { break }
            scanned += 1; onProgress?(scanned)
            guard let text = readTextFile(url)?.text, mightMatch(text) else { continue }
            let fileMatches = matches(
                in: text, query: query,
                caseSensitive: caseSensitive, regex: regexObj)
            guard !fileMatches.isEmpty else { continue }
            let found = SearchFileResult(url: url, matches: fileMatches)
            results.append(found)
            onFile?(found)
            total += fileMatches.count
        }
        results.sort { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
        return results
    }

    /// One file through the shared searchability guards: regular, under the size
    /// cap, non-binary, UTF-8-or-Latin-1 (see ``TextFileContents``). The single-file
    /// twin of the walk below.
    public static func readTextFile(_ url: URL) -> TextFileContents? {
        let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard attrs?.isRegularFile == true else { return nil }
        if (attrs?.fileSize ?? 0) > maxFileBytes { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return TextFileContents(data: data)
    }

    /// The files a search would consider under `root` — one fast pass, for a
    /// "Searching 1,234 of 20,000 files" counter. Same walk and filters as the
    /// search itself (skip list, the hidden-files flag, symlinks, `include`), so the total
    /// and the running count agree; the only thing NOT applied is the per-file size
    /// cap, which the scan still counts as it passes over.
    public static func countCandidateFiles(
        in root: URL, include: ((URL) -> Bool)? = nil,
        isCancelled: () -> Bool = { false }
    ) -> Int {
        var n = 0
        walkRegularFiles(in: root, isCancelled: isCancelled, include: include) { _, _ in
            n += 1; return true
        }
        return n
    }

    /// Honour `.gitignore` / `.ignore` / `.rgignore` / `.fdignore` (see ``IgnoreRules``) —
    /// on by default, as in ripgrep and fd. A host exposes this as a preference.
    nonisolated(unsafe) public static var respectIgnoreFiles = true

    /// Walk dot-files and dot-directories too (`.env`, `.github/workflows`). Off by default, as
    /// in ripgrep and fd without `--hidden`; a host sets it from the same preference as its file
    /// tree. The name skip list and the ignore files still apply on top.
    nonisolated(unsafe) public static var includeHiddenFiles = false

    /// Walks `root` for regular files, cheaply: `d_type` from the listing plus one `lstat` per
    /// entry, not `FileManager.enumerator`'s `getattrlist` per entry. Symlinks are skipped both
    /// ways (a linked file would bypass the size cap, a linked directory could loop). `body`
    /// returns false to stop.
    private static func walkRegularFiles(
        in root: URL, isCancelled: () -> Bool,
        include: ((URL) -> Bool)?,
        body: (URL, Int) -> Bool
    ) {
        let rules: IgnoreRules? = respectIgnoreFiles ? IgnoreRulesCache.rules(for: root) : nil
        // Each frame carries the directory, its path relative to the root, and the ignore
        // files in force there (root's first, deeper ones override).
        var stack: [(dir: URL, rel: String, ignore: IgnoreStack)] = [(root, "", IgnoreStack())]
        while let frame = stack.popLast() {
            if isCancelled() { return }
            let (dir, rel) = (frame.dir, frame.rel)
            var ignore = frame.ignore
            if let rules {
                for file in rules.files(in: dir, relativeDirectory: rel) { ignore.push(file) }
            }
            let entries = FastDirectoryListing.list(dir, includeHidden: includeHiddenFiles, skipping: SkippedDirs.names)
            var subdirs: [(URL, String)] = []
            for entry in entries {
                if isCancelled() { return }
                var st = stat()
                guard lstat(entry.url.path, &st) == 0 else { continue }
                let mode = st.st_mode & S_IFMT
                let isDir = mode == S_IFDIR
                if !isDir, mode != S_IFREG { continue }  // symlinks, FIFOs, sockets, devices
                let relPath = rel.isEmpty ? entry.url.lastPathComponent : rel + "/" + entry.url.lastPathComponent
                if let rules, rules.isIgnored(relativePath: relPath, isDirectory: isDir, stack: ignore) { continue }
                if isDir { subdirs.append((entry.url, relPath)); continue }
                if let include, !include(entry.url) { continue }
                if !body(entry.url, Int(st.st_size)) { return }
            }
            // Directories were listed in Finder order; push reversed so they pop in order.
            for (url, relPath) in subdirs.reversed() { stack.append((url, relPath, ignore)) }
        }
    }

    /// The single walker behind `search` and `replaceAll`: every regular text file under `root`
    /// that passes the skip list, the size cap and the binary sniff, as ``TextFileContents``.
    /// `onProgress` counts files the size cap skips too, so it climbs to the candidate total.
    private static func enumerateTextFiles(
        in root: URL,
        isCancelled: () -> Bool,
        include: ((URL) -> Bool)? = nil,
        onProgress: ((Int) -> Void)? = nil,
        body: (URL, TextFileContents) -> Bool
    ) {
        var scanned = 0
        walkRegularFiles(in: root, isCancelled: isCancelled, include: include) { url, size in
            scanned += 1; onProgress?(scanned)
            if size > maxFileBytes { return true }
            guard let data = try? Data(contentsOf: url),
                let contents = TextFileContents(data: data)  // binary files are skipped
            else { return true }
            return body(url, contents)
        }
    }

    /// Whole-file pre-check: a predicate that is false only when a file's text certainly holds
    /// no match, so the typical all-miss file skips the per-line walk. It may over-admit, never
    /// under-admit: regex mode recompiles with `.anchorsMatchLines`, and patterns using
    /// `\A`/`\z`/`\Z` or negative lookaround (whose meaning differs on the whole text) skip it.
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
            !query.contains("(?!"), !query.contains("(?<!")
        else { return { _ in true } }
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
            if out.count >= maxMatchesPerFile {  // per-file cap
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
                    let r = ns.range(
                        of: query, options: opts,
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

    /// Replaces every match of `query` across every searchable file under `root`.
    /// **Destructive**: call with `commit: false` first for a dry run whose counts equal what
    /// the commit writes. Matching is exactly `search`'s, per line, so no pattern can consume a
    /// newline the preview didn't show; in regex mode `replacement` is a template (`$1`).
    /// A rewritten file keeps its encoding, byte-order mark and permissions (``FileRewrite``);
    /// files written before a cancellation stay written.
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
        enumerateTextFiles(in: root, isCancelled: isCancelled, include: include) { url, file in
            let text = file.text
            guard mightMatch(text) else { return true }
            let (newText, count) = replaced(
                in: text, query: query, caseSensitive: caseSensitive,
                regex: regexObj, replacement: replacement)
            guard count > 0, newText != text else { return true }
            // Round-trip in the file's original encoding. A replacement that adds a
            // character the encoding can't represent is a FAILURE, not a change —
            // checked identically in both the dry run and the commit so the dry-run
            // count the caller confirms against exactly equals what commit writes.
            guard let data = file.data(for: newText) else { filesFailed += 1; return true }
            if !commit {  // dry run: report what WOULD change, write nothing
                filesChanged += 1
                totalReplacements += count
                return true
            }
            do {
                try FileRewrite.write(data, to: url)
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
            let (replacedLine, n) = replacedInLine(
                line, query: query, caseSensitive: caseSensitive,
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
