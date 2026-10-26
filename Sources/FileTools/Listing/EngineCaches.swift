//
//  EngineCaches.swift
//  FileTools
//
//  The folders a game engine fills with its own caches, skipped beside the entry that marks the
//  engine's project: Unity's Library, Unreal's Intermediate, Godot's .godot.
//
//  Created by David Sherlock on 10/26/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The cache folders a game engine writes into its project — tens of thousands of files nobody reads,
/// rewritten while the editor runs — skipped like ``SkippedDirs``, but only beside the entry that
/// marks the folder as the engine's project, so a `Library` anywhere else stays.
///
/// - Unity: `Library`, `Temp` and `obj` beside both `Assets` and `ProjectSettings`.
/// - Unreal: `Intermediate` and `DerivedDataCache` beside a `.uproject` or a plugin's `.uplugin`
///   (`Saved`, which holds the logs, and `Binaries` stay).
/// - Godot: `.godot` (Godot 4) and `.import` (Godot 3) beside `project.godot`.
///
/// A listing that drops ``SkippedDirs`` drops these too (``FastDirectoryListing``, the tree's
/// children, ``EventPaths/relevant(_:root:skipping:)``); a walker that tests one folder at a time
/// asks ``isCache(_:)``.
public enum EngineCaches {
    /// Every folder name a rule can skip: the cheap first test, before any marker is looked for.
    public static let folderNames: Set<String> = rules.reduce(into: []) { $0.formUnion($1.folders) }

    /// The cache folders among one folder's entries, given their names.
    public static func skipped(among names: some Sequence<String>) -> Set<String> {
        let entries = Set(names)
        guard !entries.isDisjoint(with: folderNames) else { return [] }
        var skipped = Set<String>()
        for rule in rules where !entries.isDisjoint(with: rule.folders) && rule.marksProject(entries) {
            skipped.formUnion(rule.folders.intersection(entries))
        }
        return skipped
    }

    /// Whether `folder` is an engine's cache: its name is one a rule skips and its parent holds
    /// that rule's marker. The parent is listed only for those names.
    public static func isCache(_ folder: URL) -> Bool {
        let name = folder.lastPathComponent
        guard folderNames.contains(name) else { return false }
        let siblings = (try? FileManager.default.contentsOfDirectory(atPath: folder.deletingLastPathComponent().path)) ?? []
        return skipped(among: siblings).contains(name)
    }

    private static let rules: [Rule] = [
        Rule(folders: ["Library", "Temp", "obj"]) { $0.contains("Assets") && $0.contains("ProjectSettings") },
        Rule(folders: ["Intermediate", "DerivedDataCache"]) { names in
            names.contains { $0.hasSuffix(".uproject") || $0.hasSuffix(".uplugin") }
        },
        Rule(folders: [".godot", ".import"]) { $0.contains("project.godot") },
    ]

    /// One engine's cache folders and the test of a folder's entries that marks it as the
    /// engine's project.
    private struct Rule: Sendable {
        let folders: Set<String>
        let marksProject: @Sendable (Set<String>) -> Bool

        init(folders: Set<String>, marksProject: @escaping @Sendable (Set<String>) -> Bool) {
            self.folders = folders
            self.marksProject = marksProject
        }
    }
}
