//
//  IgnoreMatcher.swift
//  FileTools
//
//  Answers "is this URL ignored?" for consumers that do not walk the tree themselves — a file
//  tree dimming rows, a symbol index driven by `FileManager.enumerator`.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Answers "is this URL ignored?" for consumers that do not walk the tree themselves — a
/// file tree dimming rows, a symbol index driven by `FileManager.enumerator`. Builds the
/// ``IgnoreStack`` for each directory on first use (root's files, then each level down)
/// and caches it; rebuilds when ``IgnoreRulesCache/generation`` moves. Thread-safe.
///
/// A checkout nested inside the root is its own git root once the host names it through
/// ``setNestedRoots(_:)`` (or the initializer): every entry is judged by the deepest root
/// containing it, with that root's own ``GitIgnoredSet``, the way `git check-ignore` run in
/// that checkout would. Git never reads an outer `.gitignore` inside a nested repository and
/// neither does the matcher; the `.ignore` / `.rgignore` / `.fdignore` stack still flows down
/// from the root through every nested checkout, as ripgrep's does. Without the host's list a
/// nested checkout is one directory of the outer root, which is what git reports for it.
public final class IgnoreMatcher: @unchecked Sendable {
    /// The standardised scan root.
    public let root: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var stacks: [String: IgnoreStack] = [:]  // relative directory → stack in force there
    private var builtFor = -1
    /// The nested checkouts, as directories relative to the root.
    private var nested: Set<String> = []

    /// A matcher for the tree under `root`; nothing is read until the first question.
    /// `nestedRoots` names the checkouts inside it, see ``setNestedRoots(_:)``.
    public init(root: URL, nestedRoots: [URL] = [], fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
        setNestedRoots(nestedRoots)
    }

    /// The nested checkouts the matcher answers from their own rules, as absolute URLs.
    public var nestedRoots: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return nested.sorted().map { root.appendingPathComponent($0, isDirectory: true) }
    }

    /// Names the git work trees nested inside the root — every directory holding its own
    /// `.git` that the host discovered. A URL outside the root, or the root itself, is
    /// dropped. Replaces the previous list and drops the cached per-directory stacks.
    ///
    /// Each nested root's rules load through ``IgnoreRulesCache`` on the first question
    /// beneath it (one `git ls-files`); ``IgnoreRulesCache/warm(_:)`` loads them ahead.
    public func setNestedRoots(_ roots: [URL]) {
        let relative = Set(roots.compactMap { relativePath(of: $0) }.filter { !$0.isEmpty })
        lock.lock()
        nested = relative
        stacks = [:]
        lock.unlock()
    }

    /// `url` relative to the root with `/` separators, or nil when it is not under the root.
    public func relativePath(of url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let base = root.path
        if path == base { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    /// Whether `url` is ignored, itself or through an ignored ancestor directory; false outside
    /// the root and for the root itself.
    public func isIgnored(url: URL, isDirectory: Bool) -> Bool {
        guard let rel = relativePath(of: url), !rel.isEmpty else { return false }
        let nested = snapshotNested()
        // A file inside an ignored directory is ignored: check every ancestor as a directory,
        // each judged by the deepest root above it. Crossing into a nested checkout switches
        // the git rules; the stack of `.ignore` files carries on.
        var governing = Governing(root: root, relativeDirectory: "")
        var from = rel.startIndex
        while let slash = rel[from...].firstIndex(of: "/") {
            let ancestor = String(rel[..<slash])
            if isIgnored(relativePath: ancestor, isDirectory: true, under: governing) { return true }
            if nested.contains(ancestor) { governing = Governing(root: root, relativeDirectory: ancestor) }
            from = rel.index(after: slash)
        }
        return isIgnored(relativePath: rel, isDirectory: isDirectory, under: governing)
    }

    // MARK: - One entry

    /// The git root an entry is judged by: the scan root or a nested checkout.
    private struct Governing {
        let rules: IgnoreRules
        /// The root's directory relative to the scan root, "" for the scan root.
        let relativeDirectory: String

        init(root: URL, relativeDirectory: String) {
            self.relativeDirectory = relativeDirectory
            let url = relativeDirectory.isEmpty ? root : root.appendingPathComponent(relativeDirectory, isDirectory: true)
            self.rules = IgnoreRulesCache.rules(for: url)
        }

        /// `relativePath` (from the scan root) measured from this root instead.
        func localPath(of relativePath: String) -> String {
            relativeDirectory.isEmpty ? relativePath : String(relativePath.dropFirst(relativeDirectory.count + 1))
        }
    }

    /// Git's verdict from the governing root, then the ignore-file stack of the parent
    /// directory (paths in the stack are measured from the scan root).
    private func isIgnored(relativePath: String, isDirectory: Bool, under governing: Governing) -> Bool {
        if let git = governing.rules.git, git.isIgnored(relativePath: governing.localPath(of: relativePath), isDirectory: isDirectory) {
            return true
        }
        let parent = relativePath.contains("/") ? String(relativePath[..<relativePath.lastIndex(of: "/")!]) : ""
        let stack = stack(for: parent)
        return !stack.isEmpty && stack.isIgnored(relativePath: relativePath, isDirectory: isDirectory)
    }

    private func snapshotNested() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return nested
    }

    // MARK: - Stacks

    private func stack(for relativeDirectory: String) -> IgnoreStack {
        lock.lock(); defer { lock.unlock() }
        if builtFor != IgnoreRulesCache.generation { stacks = [:]; builtFor = IgnoreRulesCache.generation }
        if let hit = stacks[relativeDirectory] { return hit }
        let parentStack: IgnoreStack
        if relativeDirectory.isEmpty {
            parentStack = IgnoreStack()
        } else {
            let above = relativeDirectory.contains("/") ? String(relativeDirectory[..<relativeDirectory.lastIndex(of: "/")!]) : ""
            lock.unlock(); let p = stack(for: above); lock.lock()
            parentStack = p
        }
        let dir = relativeDirectory.isEmpty ? root : root.appendingPathComponent(relativeDirectory)
        let rules = rulesGoverning(directory: relativeDirectory)
        let built = parentStack.appending(contentsOf: rules.files(in: dir, relativeDirectory: relativeDirectory, fileManager: fileManager))
        stacks[relativeDirectory] = built
        return built
    }

    /// The rules whose file names apply inside `relativeDirectory`: the deepest nested
    /// checkout at or above it, else the scan root's. Called with the lock held; the nested
    /// set is read in place and the rules come from the cache.
    private func rulesGoverning(directory relativeDirectory: String) -> IgnoreRules {
        var candidate = Substring(relativeDirectory)
        while !candidate.isEmpty {
            if nested.contains(String(candidate)) {
                return IgnoreRulesCache.rules(for: root.appendingPathComponent(String(candidate), isDirectory: true))
            }
            guard let slash = candidate.lastIndex(of: "/") else { break }
            candidate = candidate[..<slash]
        }
        return IgnoreRulesCache.rules(for: root)
    }
}
