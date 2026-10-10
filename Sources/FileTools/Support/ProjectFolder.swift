//
//  ProjectFolder.swift
//  FileTools
//
//  Creating the folder for a new project: a fresh one, or an existing one that is empty.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The folder a new project starts in.
public enum ProjectFolder {

    /// Names that do not make a folder non-empty: Finder writes `.DS_Store` into any folder it
    /// has merely shown.
    public static let ignoredNames: Set<String> = [".DS_Store"]

    /// Whether `url` is a folder holding nothing but ``ignoredNames``; false when it is not a
    /// folder or cannot be read.
    public static func isEmptyFolder(_ url: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return names.allSatisfy(ignoredNames.contains)
    }

    /// Makes `url` the new project's folder: creates it (and any missing parents), or accepts it
    /// as it is when it already exists and is empty. Never removes, replaces or writes anything
    /// that is already there.
    ///
    /// - Throws: ``ProjectFolderError/notEmpty(_:)`` for a folder that holds files,
    ///   ``ProjectFolderError/notAFolder(_:)`` when a file or link holds the name, or the file
    ///   system's error when the folder cannot be created.
    public static func create(at url: URL) throws {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & S_IFMT == S_IFDIR else { throw ProjectFolderError.notAFolder(url) }
            guard isEmptyFolder(url) else { throw ProjectFolderError.notEmpty(url) }
            return
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
