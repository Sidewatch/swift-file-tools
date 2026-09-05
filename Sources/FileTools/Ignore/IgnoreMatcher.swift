//
//  IgnoreMatcher.swift
//  FileTools
//
//  Answers "is this URL ignored?" for consumers that do not walk the tree themselves — a file
//  tree dimming rows, a symbol index driven by `FileManager.enumerator`.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

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
