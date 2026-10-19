//
//  FileLocationLink.swift
//  FileTools
//
//  An app's "open this file at this line" link — `<scheme>://open?path=/abs/file&line=42` —
//  built, read back, and resolved against the disk.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An app's "open this file at this line" link: `<scheme>://open?path=/abs/file&line=42&column=7`.
///
/// A command-line wrapper sends the argument it was given, made absolute, and lets the app split
/// it: `path=/p/src/a.ts:42` names the file `/p/src/a.ts` at line 42 unless a file is literally
/// called `a.ts:42`. The split is ``TerminalPathParser/parse(_:)``, the same reading a click on
/// terminal output gets, so the two never disagree about what `file:line:col` means.
///
/// The link is reachable from any web page or app, so it names a FILE by an ABSOLUTE path and
/// nothing else: no relative path, no folder (``resolve(_:fileExists:)`` takes a predicate that
/// answers false for directories), no other verb.
public enum FileLocationLink {
    /// The one verb, carried as the URL's host.
    public static let host = "open"

    /// The link for `path` (absolute) at an optional 1-based line and column; nil for a relative
    /// path or a scheme `URLComponents` refuses.
    public static func url(scheme: String, path: String, line: Int? = nil, column: Int? = nil) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        var items = [URLQueryItem(name: "path", value: path)]
        if let line { items.append(URLQueryItem(name: "line", value: String(line))) }
        if let column { items.append(URLQueryItem(name: "column", value: String(column))) }
        parts.queryItems = items
        return parts.url
    }

    /// The reference `url` carries, as written: an absolute path (perhaps still ending in
    /// `:line:col`) and the `line` / `column` items when they are positive integers. Nil for
    /// another scheme or verb, a missing or relative path, or a path with a NUL.
    public static func reference(from url: URL, scheme: String) -> TerminalPathParser.Match? {
        guard url.scheme?.lowercased() == scheme.lowercased(), url.host?.lowercased() == host,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let path = items.first(where: { $0.name == "path" })?.value,
            path.hasPrefix("/"), !path.contains("\0")
        else { return nil }
        return TerminalPathParser.Match(
            path: path, line: positive(items, "line"), column: positive(items, "column"))
    }

    /// The file to open: the path as written when `fileExists` says it is a file, else the path
    /// with a trailing `:line[:col]` split off when THAT is a file (the link's own `line` /
    /// `column` win over the split's). Nil when neither names a file.
    public static func resolve(
        _ reference: TerminalPathParser.Match, fileExists: (String) -> Bool
    ) -> TerminalPathParser.Match? {
        if fileExists(reference.path) { return reference }
        guard reference.line == nil, let split = TerminalPathParser.parse(reference.path),
            split.path != reference.path, split.path.hasPrefix("/"), fileExists(split.path)
        else { return nil }
        return split
    }

    private static func positive(_ items: [URLQueryItem], _ name: String) -> Int? {
        guard let text = items.first(where: { $0.name == name })?.value, let n = Int(text), n > 0 else { return nil }
        return n
    }
}
