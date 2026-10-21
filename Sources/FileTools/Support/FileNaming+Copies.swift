//
//  FileNaming+Copies.swift
//  FileTools
//
//  A duplicate's name, Finder's way, and the checks a rename runs first.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension FileNaming {
    /// Where a copy of `url` goes when `url` itself is taken: Finder's duplicate names — `name copy.ext`,
    /// then `name copy 2.ext`, `name copy 3.ext` … — the first that is not taken (`exists` checks a path;
    /// by default anything there, a dangling link included, as ``availableName(_:pathExtension:in:)`` reads
    /// it). `url` itself when it is free. Only the last extension is kept apart from the name, as
    /// `URL.pathExtension` reads it.
    static func copyDestination(for url: URL, exists: (String) -> Bool = FileNaming.isTaken) -> URL {
        guard exists(url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        func named(_ name: String) -> URL {
            ext.isEmpty ? folder.appendingPathComponent(name) : folder.appendingPathComponent(name).appendingPathExtension(ext)
        }
        var candidate = named("\(base) copy")
        var n = 2
        while exists(candidate.path) {
            candidate = named("\(base) copy \(n)")
            n += 1
        }
        return candidate
    }

    /// Whether anything is at `path` — a file, a folder or a link, even a dangling one (`lstat`, not
    /// `fileExists`, which follows the link and calls a dangling one free).
    static func isTaken(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Whether `name` can be a file or folder name: not empty, not `.` or `..`, no `/` and no `:` (Finder
    /// shows a `/` as `:` and the other way round, so both are refused).
    static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains(":")
    }

    /// Whether renaming `source` to `destination` changes only letter case (`Foo.txt` → `foo.txt`). On a
    /// case-insensitive volume the destination then "exists" because it IS the source, so a collision
    /// check must let it through; the move renames it in place.
    static func isCaseOnlyRename(_ source: URL, _ destination: URL) -> Bool {
        source.path != destination.path && source.path.caseInsensitiveCompare(destination.path) == .orderedSame
    }
}
