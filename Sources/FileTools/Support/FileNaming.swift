//
//  FileNaming.swift
//  FileTools
//
//  A name that is free in a folder: `base`, else `base 2`, `base 3`, …, Finder-style.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Names for new items that never collide with what a folder already holds.
public enum FileNaming {

    /// `base` (plus `.pathExtension` when given), or the first `base N` (N ≥ 2) that names
    /// nothing in `directory` yet — the suffix goes before the extension, as Finder places it.
    ///
    /// Taken means anything at the path: a file, a folder or a link, even a dangling one.
    public static func availableName(_ base: String, pathExtension: String = "", in directory: URL) -> String {
        func name(_ stem: String) -> String { pathExtension.isEmpty ? stem : "\(stem).\(pathExtension)" }
        func taken(_ candidate: String) -> Bool {
            let path = directory.appendingPathComponent(candidate).path
            // lstat, not fileExists: a dangling link still occupies its name.
            var info = stat()
            return lstat(path, &info) == 0
        }
        var candidate = name(base)
        var n = 2
        while taken(candidate) {
            candidate = name("\(base) \(n)")
            n += 1
        }
        return candidate
    }
}
