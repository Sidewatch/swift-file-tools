//
//  ExcerptWindows.swift
//  FileTools
//
//  Which lines to show around a file's matches: windows of context, overlapping ones merged.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The runs of lines an excerpt view shows around a file's matched lines.
public enum ExcerptWindows {
    /// The 1-based line runs to show around `marked` lines of a text `lineCount` lines long: `context`
    /// lines either side of each, clipped to the text, with windows that overlap or touch merged into
    /// one. A marked line outside `1...lineCount` (the file shrank since it was searched) is ignored.
    /// In line order, whatever order `marked` is in.
    public static func runs(around marked: [Int], context: Int, lineCount: Int) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        for line in Set(marked).sorted() where line >= 1 && line <= lineCount {
            let window = max(1, line - context)...min(lineCount, line + context)
            if let last = runs.last, window.lowerBound <= last.upperBound + 1 {
                runs[runs.count - 1] = last.lowerBound...max(last.upperBound, window.upperBound)
            } else {
                runs.append(window)
            }
        }
        return runs
    }
}
