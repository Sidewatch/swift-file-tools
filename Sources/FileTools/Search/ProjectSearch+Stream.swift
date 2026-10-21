//
//  ProjectSearch+Stream.swift
//  FileTools
//
//  A search whose matching files arrive in batches while the walk runs.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

public extension ProjectSearch {
    /// Runs a search in the background and hands its matching files to `deliver` in batches while it
    /// runs: the first file at once, then at most every `interval` (a lone hit followed by a long run of
    /// misses still arrives within `interval`), and the rest with `final` true when the walk ends —
    /// exactly once, an empty batch if nothing was left. `deliver` is called on a background queue.
    ///
    /// Searches `files` when given (only those, in order), otherwise every root in `roots` on every core,
    /// honouring `include`; `isCancelled` stops the walk early (the final batch still comes).
    static func stream(
        query: String, roots: [URL], files: [URL]? = nil, caseSensitive: Bool, regex: Bool,
        include: (@Sendable (URL) -> Bool)? = nil, interval: TimeInterval = 0.03,
        isCancelled: @escaping @Sendable () -> Bool,
        deliver: @escaping @Sendable (_ batch: [SearchFileResult], _ final: Bool) -> Void
    ) {
        let buffer = SearchStreamBuffer()
        let post: @Sendable (Bool) -> Void = { final in
            guard let batch = buffer.drainIfDue(interval: interval, force: final) else { return }
            deliver(batch, final)
        }
        let ticker = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        ticker.schedule(deadline: .now() + interval, repeating: interval)
        ticker.setEventHandler { post(false) }
        ticker.resume()
        let onFile: @Sendable (SearchFileResult) -> Void = { result in
            buffer.append(result)
            post(false)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            if let files {
                _ = search(query: query, files: files, caseSensitive: caseSensitive, regex: regex, isCancelled: isCancelled, onFile: onFile)
            } else {
                for root in roots where !isCancelled() {
                    _ = searchInParallel(
                        query: query, in: root, caseSensitive: caseSensitive, regex: regex, isCancelled: isCancelled, include: include,
                        onFile: onFile)
                }
            }
            ticker.cancel()
            post(true)
        }
    }
}
