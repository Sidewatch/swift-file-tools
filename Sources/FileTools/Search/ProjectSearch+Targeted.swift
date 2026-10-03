//
//  ProjectSearch+Targeted.swift
//  FileTools
//
//  Replace exactly the matches a search showed: each verified against the file as it is now.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension ProjectSearch {
    /// Replaces EXACTLY the given matches — the ones a result list still shows after the person
    /// dismissed some, or a scope that is a fixed file list. Each file is re-read and each match
    /// line verified against the text the result showed; only verified ranges are rewritten
    /// (descending, so earlier offsets stay valid). A line that changed since the search is
    /// skipped and its file counted as failed, never guessed at. The dry run (`commit: false`)
    /// and the commit share this body, so a confirmation counts exactly what a commit writes;
    /// like ``replaceAll(query:in:caseSensitive:regex:replacement:commit:isCancelled:include:)``,
    /// a rewritten file keeps its encoding, byte-order mark and permissions.
    public static func replaceMatches(
        _ files: [SearchFileResult],
        query: String, caseSensitive: Bool, regex: Bool,
        replacement: String, commit: Bool
    ) -> ReplaceSummary {
        let regexObj: NSRegularExpression? =
            regex
            ? try? NSRegularExpression(pattern: query, options: caseSensitive ? [] : [.caseInsensitive])
            : nil
        if regex && regexObj == nil { return .empty }
        var changed = 0, total = 0, failed = 0
        for entry in files where !entry.matches.isEmpty {
            guard let file = readTextFile(entry.url) else { failed += 1; continue }
            let text = file.text
            let ns = text as NSString
            // 1-based line starts, walked once.
            var lineStarts: [Int] = [0]
            var i = 0
            while i < ns.length {
                let r = ns.lineRange(for: NSRange(location: i, length: 0))
                i = NSMaxRange(r)
                lineStarts.append(i)
            }
            var out = text
            var applied = 0
            var fileFailed = false
            let ordered = entry.matches.sorted { ($0.line, $0.range.location) > ($1.line, $1.range.location) }
            for m in ordered {
                guard m.line >= 1, m.line <= lineStarts.count - 1 else { fileFailed = true; continue }
                // `contentsEnd` excludes the terminator whatever it is (\n, \r, \r\n, U+2028…):
                // a suffix trim would treat "\r\n" as one grapheme and fail every CRLF line.
                var lineStart = 0, lineEnd = 0, contentsEnd = 0
                ns.getLineStart(
                    &lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: lineStarts[m.line - 1], length: 0))
                let line = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
                guard line == m.lineText else { fileFailed = true; continue }  // the file moved on
                let lineNS = line as NSString
                guard NSMaxRange(m.range) <= lineNS.length else { fileFailed = true; continue }
                let newFragment: String
                if let regexObj {
                    // Verify with the semantics that produced the match: a full-line pass accepting
                    // the hit whose range is the recorded one (a lookaround may reach outside it).
                    guard
                        let hit = regexObj.matches(in: line, options: [], range: NSRange(location: 0, length: lineNS.length))
                            .first(where: { $0.range == m.range })
                    else { fileFailed = true; continue }
                    newFragment = regexObj.replacementString(for: hit, in: line, offset: 0, template: replacement)
                } else {
                    newFragment = replacement
                }
                let absolute = NSRange(location: lineStart + m.range.location, length: m.range.length)
                out = (out as NSString).replacingCharacters(in: absolute, with: newFragment)
                applied += 1
            }
            if fileFailed { failed += 1 }
            guard applied > 0 else { continue }
            // Encodability is checked in both passes, so the dry run counts what a commit can write.
            guard let data = file.data(for: out) else {
                if !fileFailed { failed += 1 }
                continue
            }
            if commit {
                do { try FileRewrite.write(data, to: entry.url) } catch {
                    if !fileFailed { failed += 1 }
                    continue
                }
            }
            total += applied
            changed += 1
        }
        return ReplaceSummary(filesChanged: changed, replacements: total, filesFailed: failed)
    }
}
