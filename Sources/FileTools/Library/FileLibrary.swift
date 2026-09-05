//
//  FileLibrary.swift
//  FileTools
//
//  Plain files of one extension in a global folder (Application Support, say) plus a
//  per-project folder (`<root>/<projectSubpath>`).
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// Plain files of one extension in a global folder (Application Support, say) plus a
/// per-project folder (`<root>/<projectSubpath>`). No database, no index: what is on disk is
/// the library, and anything that writes there is a valid editor.
public struct FileLibrary: Sendable {

    /// One file in the library.
    public struct Entry: Equatable, Sendable {
        /// The file name without its extension.
        public let title: String
        public let url: URL
        /// Project entries sort first and are labelled: which one you are about to use matters
        /// more than its name when a project overrides a global default.
        public let isProject: Bool

        public init(title: String, url: URL, isProject: Bool) {
            self.title = title
            self.url = url
            self.isProject = isProject
        }
    }

    public let globalDirectory: URL
    /// The extension every entry has, without the dot (`http`, `md`).
    public let fileExtension: String
    /// Where a project keeps its own entries, relative to its root (`.sidewatch/http`).
    public let projectSubpath: String

    public init(globalDirectory: URL, fileExtension: String, projectSubpath: String) {
        self.globalDirectory = globalDirectory
        self.fileExtension = fileExtension.lowercased()
        self.projectSubpath = projectSubpath
    }

    /// A project's own folder: `<root>/<projectSubpath>`.
    public func projectDirectory(for root: URL) -> URL {
        root.appendingPathComponent(projectSubpath, isDirectory: true)
    }

    /// Every entry visible right now: the project's (if a root is given) then the global
    /// library, each sorted by name.
    ///
    /// Not deduplicated by title on purpose. Two files that happen to share a name are two
    /// files, and silently hiding one would make the library lie about what is on disk.
    public func entries(projectRoot: URL?) -> [Entry] {
        var out: [Entry] = []
        if let root = projectRoot {
            out += entries(in: projectDirectory(for: root), isProject: true)
        }
        out += entries(in: globalDirectory, isProject: false)
        return out
    }

    /// The entries in one folder, sorted the way Finder sorts.
    public func entries(in directory: URL, isProject: Bool) -> [Entry] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == fileExtension }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { Entry(title: $0.deletingPathExtension().lastPathComponent, url: $0, isProject: isProject) }
    }

    /// Writes `content` as a new entry and returns its URL, or nil when the write failed.
    /// The name is sanitised, and suffixed (`name 2`, `name 3`, …) if it would collide, so
    /// saving twice never silently overwrites the earlier file.
    @discardableResult
    public func save(_ content: String, name: String, in directory: URL) -> URL? {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(named: Self.sanitize(name), in: directory)
        return (try? content.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    /// `<directory>/<base>.<ext>`, or the first `<base> N.<ext>` (N ≥ 2) that does not exist yet.
    public func uniqueURL(named base: String, in directory: URL) -> URL {
        var candidate = directory.appendingPathComponent("\(base).\(fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(n).\(fileExtension)")
            n += 1
        }
        return candidate
    }

    /// A filename-safe base name. Path separators and colons would escape the directory or
    /// break on other filesystems, so they are replaced rather than rejected — a save should
    /// not fail because the user typed a slash. Blank becomes `Untitled`.
    public static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    /// Writes each seed whose file is absent into `directory`; returns how many were written.
    /// Additive: an edited or deliberately deleted entry is never resurrected or clobbered.
    /// Version gating ("seed once per release") is the caller's, so this stays free of defaults.
    @discardableResult
    public func seed(_ seeds: [(name: String, body: String)], into directory: URL) -> Int {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written = 0
        for seed in seeds {
            let target = directory.appendingPathComponent("\(Self.sanitize(seed.name)).\(fileExtension)")
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            if (try? seed.body.write(to: target, atomically: true, encoding: .utf8)) != nil { written += 1 }
        }
        return written
    }
}
