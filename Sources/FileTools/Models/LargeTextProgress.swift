//
//  LargeTextProgress.swift
//  FileTools
//
//  Where a large text file's line scan has got to.
//
//  Created by David Sherlock on 10/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Where a ``LargeTextFile``'s line scan has got to.
public struct LargeTextProgress: Sendable, Equatable {
    /// The lines that can be asked for so far: every line the scan has seen end, and the last once it is done.
    public let lineCount: Int
    /// How many bytes the scan has read.
    public let bytesScanned: Int
    /// The file's size when it was opened, or at its last growth.
    public let byteCount: Int
    /// Whether the scan has read every byte.
    public let isComplete: Bool
    /// The longest line found so far, in bytes, its break not counted.
    public let longestLineBytes: Int
}
