//
//  LocalHistorySource.swift
//  FileTools
//
//  Why a version of a file was kept in local history.
//
//  Created by David Sherlock on 10/10/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Why ``LocalHistory`` kept a version. The raw value is what `entries.json` stores, so a raw
/// value never changes once shipped; ``LocalHistoryEntry/kind`` reads it back.
public enum LocalHistorySource: String, Sendable, CaseIterable {
    /// The host saved the file.
    case saved = "File Saved"
    /// The bytes on disk a save was about to replace: what another writer left there while the
    /// host's buffer held unsaved edits.
    case overwritten = "Overwritten on disk"
    /// Another writer changed the file while a coding agent was working.
    case agent = "Agent"
    /// Another writer changed the file and no agent is known to be working.
    case changedOnDisk = "Changed on disk"
    /// What the file held before the first change from disk that was recorded — the "before" the
    /// first outside write is compared with.
    case previous = "Before change"
}
