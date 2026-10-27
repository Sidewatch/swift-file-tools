//
//  LargeTextMatchCount.swift
//  FileTools
//
//  How many matches a large text file holds, and how they fall among the blocks it was read in.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

/// What ``LargeTextSearch/count(_:in:isCancelled:)`` found: every match in a file, and how many lay before each block
/// it read, so where any one match falls among them is a search of one block away
/// (``LargeTextSearch/index(of:in:_:file:)``).
public struct LargeTextMatchCount: Sendable, Equatable {
    /// The matches in the file.
    public let total: Int
    /// The file's size when it was counted.
    public let byteCount: Int
    /// The blocks read, in order, and how many matches came before each.
    let blocks: [Range<Int>]
    let before: [Int]
}
