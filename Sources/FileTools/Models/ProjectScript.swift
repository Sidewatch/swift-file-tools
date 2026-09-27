//
//  ProjectScript.swift
//  FileTools
//
//  A runnable task discovered in a project manifest — the command to type at the terminal, plus
//  where it came from.
//
//  Created by David Sherlock on 9/5/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A runnable task discovered in a project manifest — the command to type at the
/// terminal, plus where it came from.
public struct ProjectScript: Equatable {
    /// The script's name as the manifest declares it.
    public let name: String       // e.g. "build"
    /// The command line that runs it.
    public let command: String    // e.g. "npm run build"
    /// The manifest file it came from.
    public let source: String     // e.g. "package.json"

    /// Creates a script.
    public init(name: String, command: String, source: String) {
        self.name = name
        self.command = command
        self.source = source
    }
}
