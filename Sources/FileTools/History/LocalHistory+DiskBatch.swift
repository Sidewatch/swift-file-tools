//
//  LocalHistory+DiskBatch.swift
//  FileTools
//
//  Keeping a batch of files that changed on disk: which are kept, and what each held before.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import GitKit

extension LocalHistory {
    /// Keeps the files of `batch` as they are on disk now. Synchronous file and `git` I/O: call it off
    /// the main thread, one batch at a time.
    ///
    /// The first `limit` paths in path order are considered; of those, a path inside a `.git` folder, one
    /// the deepest ignore root's rules ignore, or one git ignores NOW (asked of each repository once —
    /// a cached listing would not know an agent's brand-new build output) is skipped. The rest go to
    /// ``recordFromDisk(_:source:limit:at:previous:)``, a first sighting's "before" taken from the
    /// batch's captured buffer, else from its repository's `HEAD` (one `cat-file` per repository).
    /// Roots are matched under the path they were given and their real path.
    public func recordDiskBatch(_ batch: LocalHistoryDiskBatch, limit: Int = LocalHistory.defaultDiskBatchLimit) -> LocalHistoryDiskRecord {
        let roots = batch.ignoreRoots.map(RootSpellings.init(resolving:))
        let repos = batch.repoRoots.map(RootSpellings.init(resolving:))
        let sorted = batch.paths.sorted()
        var files: [URL] = []
        var passed = 0
        for path in sorted where files.count < limit {
            passed += 1
            if Self.isRecordablePath(path, roots: roots) { files.append(URL(fileURLWithPath: path)) }
        }
        let ignored = Self.gitIgnored(files, repos: repos)
        var outcome = recordFromDisk(files.filter { !ignored.contains($0) }, source: batch.source, limit: limit) { firstSeen in
            Self.previousContents(of: firstSeen, captured: batch.previous, repos: repos)
        }
        outcome.skipped += ignored.count
        outcome.unexamined += sorted.count - passed
        return outcome
    }

    /// Outside any `.git` folder and not ignored by the cached rules of the deepest root holding it.
    static func isRecordablePath(_ path: String, roots: [RootSpellings]) -> Bool {
        guard !path.split(separator: "/").contains(".git") else { return false }
        guard let (root, relative) = RootSpellings.deepest(roots, holding: path) else { return true }
        let matcher = IgnoreMatcherCache.shared.matcher(for: root.url)
        return !matcher.isIgnored(url: root.url.appendingPathComponent(relative), isDirectory: false)
    }

    /// The files git ignores now, asked of each repository once.
    static func gitIgnored(_ files: [URL], repos: [RootSpellings]) -> Set<URL> {
        var out = Set<URL>()
        for (repo, members) in byRepository(files, repos: repos) {
            let ignored = Git.ignoredPaths(members.map(\.relative), repoRoot: repo)
            for member in members where ignored.contains(member.relative) { out.insert(member.file) }
        }
        return out
    }

    /// What each first-seen file held before: its captured buffer, else its blob at `HEAD`.
    static func previousContents(of files: [URL], captured: [String: Data], repos: [RootSpellings]) -> [URL: Data] {
        var out: [URL: Data] = [:]
        var uncaptured: [URL] = []
        for file in files {
            if let data = captured[file.path] { out[file] = data } else { uncaptured.append(file) }
        }
        for (repo, members) in byRepository(uncaptured, repos: repos) {
            let blobs = Git.headContents(paths: members.map(\.relative), repoRoot: repo)
            for member in members { out[member.file] = blobs[member.relative] }
        }
        return out
    }

    /// `files` grouped under the deepest repository holding each, with its repository-relative path;
    /// a file in no repository is left out.
    private static func byRepository(_ files: [URL], repos: [RootSpellings]) -> [URL: [(file: URL, relative: String)]] {
        var grouped: [URL: [(file: URL, relative: String)]] = [:]
        for file in files {
            guard let (repo, relative) = RootSpellings.deepest(repos, holding: file.path) else { continue }
            grouped[repo.url, default: []].append((file, relative))
        }
        return grouped
    }
}
