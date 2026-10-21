//
//  RootSpellings.swift
//  FileTools
//
//  A folder under the path it was given and its real path, for matching paths named either way.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// A root folder and every spelling of its path: as given, and its real path when a link is involved
/// (`/tmp` vs `/private/tmp`, a project opened through a symlink). FSEvents name the real path while
/// a window names what it opened, so a path may arrive under either.
struct RootSpellings: Sendable, Equatable {
    /// The folder as given.
    let url: URL
    /// Its path as given, and its real path (one entry when no link is involved).
    let spellings: [String]

    /// The root at `url`, its real path resolved once.
    init(resolving url: URL) {
        let given = url.standardizedFileURL.path
        let real = url.realPath ?? given
        self.url = url
        spellings = real == given ? [given] : [given, real]
    }

    /// `path` relative to this root under either spelling, or nil when it lies outside (or is the
    /// root itself).
    func relativePath(of path: String) -> String? {
        for spelling in spellings {
            if let relative = path.relativePath(under: spelling), !relative.isEmpty { return relative }
        }
        return nil
    }

    /// The deepest of `roots` holding `path` and the path relative to it, matched by name first and
    /// then by `path`'s real path.
    static func deepest(_ roots: [RootSpellings], holding path: String) -> (root: RootSpellings, relative: String)? {
        if let found = deepestByName(roots, holding: path) { return found }
        guard let real = URL(fileURLWithPath: path).realPath, real != path else { return nil }
        return deepestByName(roots, holding: real)
    }

    /// The root giving `path` the shortest relative path — the deepest one holding it.
    private static func deepestByName(_ roots: [RootSpellings], holding path: String) -> (root: RootSpellings, relative: String)? {
        var best: (root: RootSpellings, relative: String)?
        for root in roots {
            guard let relative = root.relativePath(of: path) else { continue }
            if best.map({ relative.count < $0.relative.count }) ?? true { best = (root, relative) }
        }
        return best
    }
}
