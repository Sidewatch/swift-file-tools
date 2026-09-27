//
//  IgnoreStack.swift
//  FileTools
//
//  An ordered stack of `IgnoreFile`s — root down to the directory currently
//  being visited — that together decide whether one path is ignored, per
//  git's own precedence rules.
//
//  Created by David Sherlock on 9/2/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import FoundationExtensions

/// An ordered stack of ``IgnoreFile``s, from the scan root down to the directory being
/// visited, that answers "is this path ignored?" the way git does: within one file the LAST
/// matching pattern decides, and a deeper file's verdict overrides a shallower one's (two files
/// in one directory resolve by ``IgnoreFileNames/orderedNames``).
///
/// - Important: It answers only for the exact path given. A walker must stop descending into
///   a directory reported ignored, since `!` cannot re-include a file under an excluded parent.
public struct IgnoreStack: Sendable {

    private var files: [IgnoreFile]

    /// Creates a stack, optionally pre-seeded (root-to-leaf order) with files.
    public init(files: [IgnoreFile] = []) {
        self.files = files
    }

    /// `true` when the stack holds no ignore files at all.
    public var isEmpty: Bool { files.isEmpty }

    /// Pushes one more (deeper) ignore file onto the stack.
    public mutating func push(_ file: IgnoreFile) {
        files.append(file)
    }

    /// Pops and returns the most recently pushed (deepest) ignore file, if any.
    @discardableResult
    public mutating func pop() -> IgnoreFile? {
        files.popLast()
    }

    /// A copy of this stack with `file` pushed — the value-type twin of
    /// ``push(_:)``, handy for a recursive walker that wants to pass a child
    /// call its own extended stack without mutating the parent's.
    public func appending(_ file: IgnoreFile) -> IgnoreStack {
        var copy = self
        copy.push(file)
        return copy
    }

    /// A copy of this stack with every file in `files` pushed, in order — for
    /// pushing everything ``load(directory:relativeDirectory:names:fileManager:)``
    /// found in one directory at once.
    public func appending(contentsOf files: [IgnoreFile]) -> IgnoreStack {
        var copy = self
        for file in files { copy.push(file) }
        return copy
    }

    /// Whether `relativePath` (`/`-separated from the scan root, no leading slash) is ignored:
    /// true when the last pattern in the whole stack to match it is an exclusion. `isDirectory`
    /// matters because directory-only patterns never match a file.
    public func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        var verdict = false
        for file in files {
            if let v = file.verdict(for: relativePath, isDirectory: isDirectory) {
                verdict = v
            }
        }
        return verdict
    }

    /// Reads whichever of `names` exist directly inside `directory`, each parsed as an
    /// ``IgnoreFile`` bound to `relativeDirectory` (its path from the scan root), in `names` order.
    ///
    /// A file that is missing, unreadable or not UTF-8 is skipped: it contributes no rules
    /// rather than failing the walk.
    public static func load(
        directory: URL, relativeDirectory: String,
        names: [String] = IgnoreFileNames.orderedNames,
        fileManager: FileManager = .default
    ) -> [IgnoreFile] {
        var result: [IgnoreFile] = []
        for name in names {
            let fileURL = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: fileURL.path),
                let data = try? Data(contentsOf: fileURL),
                let text = data.utf8String
            else { continue }
            result.append(IgnoreFile(text: text, directory: relativeDirectory))
        }
        return result
    }
}
