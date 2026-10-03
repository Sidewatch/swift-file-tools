//
//  IncludeGlobs.swift
//  FileTools
//
//  A "files to include" field — `*.php, src/**/*.ts` — as a predicate over file URLs.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A "files to include" field — `*.php, src/**/*.ts` — as a predicate over file URLs, for
/// ``ProjectSearch``'s `include`. Patterns are comma-separated and case-insensitive. `*` and `?`
/// stay inside one path segment and `**/` crosses segments; a pattern with no `/` matches the
/// file NAME at any depth (what `*.php` means to a person), one with a `/` matches the path
/// relative to whichever root holds the file.
public enum IncludeGlobs {
    /// The predicate for `field`, or nil when it names no usable pattern (search everything).
    public static func predicate(_ field: String, roots: [URL]) -> (@Sendable (URL) -> Bool)? {
        let pats = field.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let compiled: [(re: NSRegularExpression, nameOnly: Bool)] = pats.compactMap { pat in
            regex(for: pat).map { ($0, !pat.contains("/")) }
        }
        guard !compiled.isEmpty else { return nil }
        let prefixes = roots.map { $0.path.hasSuffix("/") ? $0.path : $0.path + "/" }
        nonisolated(unsafe) let patterns = compiled
        return { url in
            let p = url.path
            var rel = url.lastPathComponent
            for prefix in prefixes where p.hasPrefix(prefix) {
                rel = String(p.dropFirst(prefix.count))
                break
            }
            let name = url.lastPathComponent
            return patterns.contains { c in
                let target = c.nameOnly ? name : rel
                return c.re.firstMatch(in: target, range: NSRange(location: 0, length: (target as NSString).length)) != nil
            }
        }
    }

    /// One glob as an anchored regex: everything escaped, then the three glob forms re-opened —
    /// `**/` (any depth, including none), `*` (within a segment) and `?`.
    static func regex(for glob: String) -> NSRegularExpression? {
        var out = "^"
        var i = glob.startIndex
        while i < glob.endIndex {
            let c = glob[i]
            if c == "*" {
                let next = glob.index(after: i)
                if next < glob.endIndex, glob[next] == "*" {
                    let after = glob.index(after: next)
                    if after < glob.endIndex, glob[after] == "/" {
                        out += "(?:[^/]+/)*"
                        i = glob.index(after: after)
                        continue
                    }
                    out += ".*"
                    i = after
                    continue
                }
                out += "[^/]*"
            } else if c == "?" {
                out += "[^/]"
            } else {
                out += NSRegularExpression.escapedPattern(for: String(c))
            }
            i = glob.index(after: i)
        }
        out += "$"
        return try? NSRegularExpression(pattern: out, options: [.caseInsensitive])
    }
}
