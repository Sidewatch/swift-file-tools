//
//  IgnoreStack.swift
//  SwiftFileTools
//
//  An ordered stack of `IgnoreFile`s — root down to the directory currently
//  being visited — that together decide whether one path is ignored, per
//  git's own precedence rules.
//
//  Created by David Sherlock on 9/2/26.
//

import Foundation

/// The ignore-file names a directory walker should look for, in ripgrep's
/// precedence order: a name later in this list wins over an earlier one when
/// both exist in the SAME directory (e.g. an `.ignore` entry beats a
/// `.gitignore` entry for the same path, in that directory).
///
/// ```swift
/// for name in IgnoreFileNames.orderedNames { … }
/// ```
public enum IgnoreFileNames {

    /// `.gitignore`, `.ignore`, `.rgignore`, `.fdignore`, in that precedence
    /// order (later wins).
    public static let orderedNames: [String] = [".gitignore", ".ignore", ".rgignore", ".fdignore"]
}

/// An ordered stack of ``IgnoreFile``s, from the scan root down to the
/// directory currently being visited, that together answer "is this path
/// ignored?" the way git does.
///
/// Precedence follows the gitignore documentation directly: within one file
/// the LAST matching pattern decides that file's own verdict; across the
/// stack, a deeper file's verdict (if it has one at all) overrides a shallower
/// file's, regardless of pattern order between the two files. Two files at the
/// same directory level (e.g. `.gitignore` and `.ignore`, both pushed via
/// ``load(directory:relativeDirectory:fileManager:)``) resolve the same way —
/// the later one in ``IgnoreFileNames/orderedNames`` wins — because it simply
/// sits deeper in the stack.
///
/// ```swift
/// var stack = IgnoreStack()
/// stack.push(rootIgnoreFile)
/// stack.push(subdirIgnoreFile)
/// stack.isIgnored(relativePath: "sub/build/output.log", isDirectory: false)
/// ```
///
/// - Important: A `!`-negated pattern cannot re-include a file whose PARENT
///   directory was itself excluded — git never even lists an excluded
///   directory's contents, so patterns inside it are moot. `isIgnored` does
///   not reconstruct that from the stack's patterns alone; it answers only for
///   the exact path given. A caller walking a tree must itself stop descending
///   into a directory once `isIgnored` reports it excluded, exactly mirroring
///   what git does — this file never needs to be told which directories were
///   already pruned.
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
    /// pushing everything ``load(directory:relativeDirectory:fileManager:)``
    /// found in one directory at once.
    public func appending(contentsOf files: [IgnoreFile]) -> IgnoreStack {
        var copy = self
        for file in files { copy.push(file) }
        return copy
    }

    /// Whether `relativePath` is ignored by this stack, applying git's
    /// last-matching-pattern-wins rule across every file in the stack, root to
    /// leaf.
    ///
    /// - Parameters:
    ///   - relativePath: `/`-separated path from the scan root, no leading
    ///     slash (e.g. `"src/build/output.log"`).
    ///   - isDirectory: Whether the path names a directory. Required because
    ///     directory-only patterns (a trailing `/`) never match a file.
    /// - Returns: `true` if the last pattern (in the whole stack) that matched
    ///   this exact path was a non-negated exclusion; `false` if it was a
    ///   negation, or if nothing in the stack matched at all.
    public func isIgnored(relativePath: String, isDirectory: Bool) -> Bool {
        var verdict = false
        for file in files {
            if let v = file.verdict(for: relativePath, isDirectory: isDirectory) {
                verdict = v
            }
        }
        return verdict
    }

    /// Reads whichever of ``IgnoreFileNames/orderedNames`` exist directly
    /// inside `directory`, parses each as an ``IgnoreFile`` bound to
    /// `relativeDirectory`, and returns them in that same precedence order —
    /// ready to hand to ``appending(contentsOf:)`` or push one at a time.
    ///
    /// A name that doesn't exist, isn't readable, or isn't valid UTF-8 is
    /// silently skipped (an ignore file that can't be read contributes no
    /// rules, rather than failing the whole walk).
    ///
    /// - Parameters:
    ///   - directory: The directory to look in, as a filesystem `URL`.
    ///   - relativeDirectory: That same directory's path relative to the scan
    ///     root (what each loaded ``IgnoreFile/directory`` will be set to).
    ///   - fileManager: The file manager to read with.
    /// - Returns: Zero or more ``IgnoreFile``s, in ``IgnoreFileNames`` order.
    public static func load(directory: URL, relativeDirectory: String,
                            names: [String] = IgnoreFileNames.orderedNames,
                            fileManager: FileManager = .default) -> [IgnoreFile] {
        var result: [IgnoreFile] = []
        for name in names {
            let fileURL = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: fileURL.path),
                  let data = try? Data(contentsOf: fileURL),
                  let text = String(data: data, encoding: .utf8) else { continue }
            result.append(IgnoreFile(text: text, directory: relativeDirectory))
        }
        return result
    }
}
