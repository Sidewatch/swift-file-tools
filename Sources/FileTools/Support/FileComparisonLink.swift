//
//  FileComparisonLink.swift
//  FileTools
//
//  An app's "compare these two files" link — `<scheme>://diff?old=/abs/a&new=/abs/b` — built and
//  read back.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An app's "compare these two files" link: `<scheme>://diff?old=/abs/a&new=/abs/b`, what a
/// command-line `--diff a b` sends. `old` is the side a diff calls removed, `new` the added side.
///
/// Like ``FileLocationLink`` it is reachable from any web page or app, so both sides are ABSOLUTE
/// paths with no NUL; the caller still checks that each names a file before reading it.
public enum FileComparisonLink {
    /// The one verb, carried as the URL's host.
    public static let host = "diff"

    /// The link comparing `old` with `new` (both absolute); nil for a relative path or a scheme
    /// `URLComponents` refuses.
    public static func url(scheme: String, old: String, new: String) -> URL? {
        guard old.hasPrefix("/"), new.hasPrefix("/") else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        parts.queryItems = [URLQueryItem(name: "old", value: old), URLQueryItem(name: "new", value: new)]
        return parts.url
    }

    /// The two paths `url` names, as written. Nil for another scheme or verb, or when either side
    /// is missing, relative or holds a NUL.
    public static func paths(from url: URL, scheme: String) -> (old: String, new: String)? {
        guard url.scheme?.lowercased() == scheme.lowercased(), url.host?.lowercased() == host,
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let old = absolute(items, "old"), let new = absolute(items, "new")
        else { return nil }
        return (old, new)
    }

    private static func absolute(_ items: [URLQueryItem], _ name: String) -> String? {
        guard let path = items.first(where: { $0.name == name })?.value, path.hasPrefix("/"), !path.contains("\0") else { return nil }
        return path
    }
}
