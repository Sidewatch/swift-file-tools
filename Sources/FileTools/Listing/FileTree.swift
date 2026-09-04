//
//  FileTree.swift
//  SwiftFileTools
//
//  Renders a directory as an ASCII `tree`, for pasting a project's structure to
//  an AI agent. Skips noise directories and is bounded so a huge tree can't run
//  away.
//
//  Created by David Sherlock on 7/9/26.
//

import Foundation

/// Renders a folder as an ASCII `tree` — for pasting your project structure to
/// an agent. Skips noise directories and is bounded so a huge tree can't run away.
///
/// ```swift
/// let text = FileTree.ascii(of: projectURL)
/// // MyApp/
/// // ├── Sources/
/// // │   └── main.swift
/// // └── README.md
/// ```
public enum FileTree {

    /// Renders `root` and its descendants as an ASCII tree.
    ///
    /// Directories are listed before files and sorted case-insensitively. Noise
    /// directories (``SkippedDirs/names``, read live so a user override applies)
    /// are omitted. Traversal stops descending past `maxDepth`, and once
    /// `maxEntries` rows have been emitted the output is truncated with an
    /// ellipsis row.
    ///
    /// - Parameters:
    ///   - root: The directory to render. Its own name forms the first line.
    ///   - maxDepth: The deepest level to descend into (default `8`).
    ///   - maxEntries: The maximum number of entries to emit (default `800`).
    /// - Returns: A newline-joined ASCII tree.
    public static func ascii(of root: URL, maxDepth: Int = 8, maxEntries: Int = 800) -> String {
        var lines = [root.lastPathComponent + "/"]
        var count = 0
        var truncated = false
        // Snapshot the skip list once so one rendering can't straddle an override.
        let skip = SkippedDirs.names

        func walk(_ dir: URL, prefix: String, depth: Int) {
            guard depth <= maxDepth, !truncated else { return }
            let fm = FileManager.default
            guard let items = try? fm.contentsOfDirectory(at: dir,
                includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            let sorted = items.filter { !skip.contains($0.lastPathComponent) }.sorted { a, b in
                let ad = (try? a.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                let bd = (try? b.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if ad != bd { return ad }   // directories first
                return a.lastPathComponent.localizedCaseInsensitiveCompare(b.lastPathComponent) == .orderedAscending
            }
            for (i, item) in sorted.enumerated() {
                if count >= maxEntries { lines.append(prefix + "└── …"); truncated = true; return }
                let isLast = i == sorted.count - 1
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                lines.append(prefix + (isLast ? "└── " : "├── ") + item.lastPathComponent + (isDir ? "/" : ""))
                count += 1
                if isDir { walk(item, prefix: prefix + (isLast ? "    " : "│   "), depth: depth + 1) }
            }
        }
        walk(root, prefix: "", depth: 1)
        return lines.joined(separator: "\n")
    }
}
