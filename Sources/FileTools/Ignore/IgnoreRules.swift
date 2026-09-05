//
//  IgnoreRules.swift
//  FileTools
//
//  The ignore decision for one scan root. Build one with ``load(root:)`` (runs `git` once),
//  then hand each directory's ``IgnoreStack`` down the walk.
//
//  Created by David Sherlock on 9/3/26.
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
