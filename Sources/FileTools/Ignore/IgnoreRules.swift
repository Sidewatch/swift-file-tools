//
//  IgnoreRules.swift
//  FileTools
//
//  What ripgrep and fd do by default, for one scan root: honour `.gitignore` (exactly, by
//  asking git — see ``GitIgnoredSet``) and the tool-agnostic `.ignore` / `.rgignore` /
//  `.fdignore` files (parsed, see ``IgnoreStack``), per directory, as a walker descends.
//  Outside a git work tree the `.gitignore` files are parsed too, so a plain folder with a
//  `.gitignore` still behaves as its author intended.
//

import Foundation

/// The ignore decision for one scan root. Build one with ``load(root:)`` (runs `git`
/// once), then hand each directory's ``IgnoreStack`` down the walk.
public struct IgnoreRules: Sendable {
    public let root: URL
    /// Git's own answer for a work tree; nil for a plain folder.
    public let git: GitIgnoredSet?
    /// The ignore files a walker loads in each directory: everything when git is not
    /// answering, only the non-git ones when it is (git already applied `.gitignore`).
    public let perDirectoryFileNames: [String]

    public init(root: URL, git: GitIgnoredSet?) {
        self.root = root
        self.git = git
        self.perDirectoryFileNames = git == nil
            ? IgnoreFileNames.orderedNames
            : IgnoreFileNames.orderedNames.filter { $0 != ".gitignore" }
    }

    /// Rules for `root`: git-derived when it is a work tree, parser-only otherwise.
    public static func load(root: URL, fileManager: FileManager = .default) -> IgnoreRules {
        IgnoreRules(root: root, git: GitIgnoredSet.load(root: root, fileManager: fileManager))
    }

    /// Whether an entry is ignored, given the stack of ignore files from the root down to
    /// its parent directory. `relativePath` is `/`-separated, relative to `root`.
    public func isIgnored(relativePath: String, isDirectory: Bool, stack: IgnoreStack) -> Bool {
        if let git, git.isIgnored(relativePath: relativePath, isDirectory: isDirectory) { return true }
        return !stack.isEmpty && stack.isIgnored(relativePath: relativePath, isDirectory: isDirectory)
    }

    /// The ignore files in `directory`, ready to push onto a walker's stack.
    public func files(in directory: URL, relativeDirectory: String, fileManager: FileManager = .default) -> [IgnoreFile] {
        IgnoreStack.load(directory: directory, relativeDirectory: relativeDirectory,
                         names: perDirectoryFileNames, fileManager: fileManager)
    }
}

/// Per-root cache with a short lifetime: a search re-runs on every keystroke and must not
/// spawn `git` each time, yet a `.gitignore` edit should be noticed within seconds. Hosts
/// that watch the tree can call ``invalidate(root:)`` the moment an ignore file changes.
public enum IgnoreRulesCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [URL: (rules: IgnoreRules, at: Date)] = [:]
    /// Bumps whenever a root's rules are (re)loaded or invalidated, so a consumer holding
    /// derived state (``IgnoreMatcher``'s per-directory stacks) knows to rebuild.
    nonisolated(unsafe) public private(set) static var generation = 0
    /// How long a loaded set stays fresh without an explicit invalidation.
    nonisolated(unsafe) public static var lifetime: TimeInterval = 10

    public static func rules(for root: URL, fileManager: FileManager = .default) -> IgnoreRules {
        let key = root.standardizedFileURL
        lock.lock()
        if let hit = entries[key], Date().timeIntervalSince(hit.at) < lifetime { lock.unlock(); return hit.rules }
        lock.unlock()
        let fresh = IgnoreRules.load(root: key, fileManager: fileManager)
        lock.lock(); entries[key] = (fresh, Date()); generation &+= 1; lock.unlock()
        return fresh
    }

    /// Drops the cached set for `root` (and any root above it, whose rules may include it).
    public static func invalidate(root: URL) {
        let path = root.standardizedFileURL.path
        lock.lock()
        entries = entries.filter { !path.hasPrefix($0.key.path) && !$0.key.path.hasPrefix(path) }
        generation &+= 1
        lock.unlock()
    }

    public static func invalidateAll() { lock.lock(); entries = [:]; generation &+= 1; lock.unlock() }
}

/// Answers "is this URL ignored?" for consumers that do not walk the tree themselves — a
/// file tree dimming rows, a symbol index driven by `FileManager.enumerator`. Builds the
/// ``IgnoreStack`` for each directory on first use (root's files, then each level down)
/// and caches it; rebuilds when ``IgnoreRulesCache/generation`` moves. Thread-safe.
public final class IgnoreMatcher: @unchecked Sendable {
    public let root: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var stacks: [String: IgnoreStack] = [:]   // relative directory → stack in force there
    private var builtFor = -1

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager
    }

    /// `url` relative to the root with `/` separators, or nil when it is not under the root.
    public func relativePath(of url: URL) -> String? {
        let path = url.standardizedFileURL.path
        let base = root.path
        if path == base { return "" }
        guard path.hasPrefix(base + "/") else { return nil }
        return String(path.dropFirst(base.count + 1))
    }

    public func isIgnored(url: URL, isDirectory: Bool) -> Bool {
        guard let rel = relativePath(of: url), !rel.isEmpty else { return false }
        let rules = IgnoreRulesCache.rules(for: root, fileManager: fileManager)
        let parent = rel.contains("/") ? String(rel[..<rel.lastIndex(of: "/")!]) : ""
        // A file inside an ignored directory is ignored: check every ancestor as a directory.
        var ancestor = ""
        for component in parent.split(separator: "/") {
            ancestor = ancestor.isEmpty ? String(component) : ancestor + "/" + component
            let above = ancestor.contains("/") ? String(ancestor[..<ancestor.lastIndex(of: "/")!]) : ""
            if rules.isIgnored(relativePath: ancestor, isDirectory: true, stack: stack(for: above, rules: rules)) { return true }
        }
        return rules.isIgnored(relativePath: rel, isDirectory: isDirectory, stack: stack(for: parent, rules: rules))
    }

    private func stack(for relativeDirectory: String, rules: IgnoreRules) -> IgnoreStack {
        lock.lock(); defer { lock.unlock() }
        if builtFor != IgnoreRulesCache.generation { stacks = [:]; builtFor = IgnoreRulesCache.generation }
        if let hit = stacks[relativeDirectory] { return hit }
        let parentStack: IgnoreStack
        if relativeDirectory.isEmpty { parentStack = IgnoreStack() }
        else {
            let above = relativeDirectory.contains("/") ? String(relativeDirectory[..<relativeDirectory.lastIndex(of: "/")!]) : ""
            lock.unlock(); let p = stack(for: above, rules: rules); lock.lock()
            parentStack = p
        }
        let dir = relativeDirectory.isEmpty ? root : root.appendingPathComponent(relativeDirectory)
        let built = parentStack.appending(contentsOf: rules.files(in: dir, relativeDirectory: relativeDirectory, fileManager: fileManager))
        stacks[relativeDirectory] = built
        return built
    }
}
