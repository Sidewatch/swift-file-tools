//
//  LocalHistoryEntry.swift
//  FileTools
//
//  One kept version of a file.
//
//  Created by David Sherlock on 9/20/26.
//

import Foundation

/// One version `LocalHistory` kept of a file: when, why, how big, and the blob's name.
public struct LocalHistoryEntry: Equatable, Sendable, Codable {
    /// The blob's file name inside the file's history folder: `<millis>-<rand>.<ext>`.
    public let id: String
    public let timestamp: Date
    /// What caused the version — "File Saved" for a save; a caller may name others.
    public let source: String
    public let byteCount: Int

    public init(id: String, timestamp: Date, source: String, byteCount: Int) {
        self.id = id; self.timestamp = timestamp; self.source = source; self.byteCount = byteCount
    }
}
