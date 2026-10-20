//
//  WaitingFiles.swift
//  FileTools
//
//  The files a command-line wrapper is waiting on, each with its wait marker.
//
//  Created by David Sherlock on 10/20/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The files a command-line `--wait` is blocked on, each with the ``WaitMarker`` that ends it.
/// The app adds one when it opens a file for a waiting wrapper and settles the list whenever a
/// tab closes: every marker whose file is no longer open comes back to be released.
///
/// Paths are compared exactly as given, so the caller names both sides the same way (a real
/// path, say), or a file opened through a link would never count as closed.
public struct WaitingFiles: Sendable {
    private struct Entry: Sendable {
        let file: String
        let marker: URL
    }

    private var entries: [Entry] = []

    public init() {}

    /// True when nothing is waiting.
    public var isEmpty: Bool { entries.isEmpty }

    /// Waits on `file` for `marker`. Two waits on one file are two markers, both released when it closes.
    public mutating func add(file: String, marker: URL) {
        entries.append(Entry(file: file, marker: marker))
    }

    /// Takes out and returns the markers whose file is not in `open`.
    public mutating func settle(open: Set<String>) -> [URL] {
        let done = entries.filter { !open.contains($0.file) }.map(\.marker)
        entries.removeAll { !open.contains($0.file) }
        return done
    }

    /// Takes out and returns every marker (the app is quitting).
    public mutating func removeAll() -> [URL] {
        defer { entries = [] }
        return entries.map(\.marker)
    }
}
