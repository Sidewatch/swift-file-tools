//
//  ProjectScript.swift
//  FileTools
//
//  A runnable task discovered in a project manifest — the command to type at the terminal, plus
//  where it came from.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// A runnable task discovered in a project manifest — the command to type at the
/// terminal, plus where it came from.
public struct ProjectScript: Equatable {
    public let name: String       // e.g. "build"
    public let command: String    // e.g. "npm run build"
    public let source: String     // e.g. "package.json"

    public init(name: String, command: String, source: String) {
        self.name = name
        self.command = command
        self.source = source
    }
}
