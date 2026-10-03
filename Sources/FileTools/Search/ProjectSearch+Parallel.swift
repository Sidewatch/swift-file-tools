//
//  ProjectSearch+Parallel.swift
//  FileTools
//
//  The same search over every core: the walk lists the candidates, the cores read and match them.
//
//  Created by David Sherlock on 10/3/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension ProjectSearch {
    /// ``search(query:in:caseSensitive:regex:isCancelled:include:onProgress:onFile:)`` over every
    /// core, pipelined: the walk hands out small batches of candidate files as it finds them, and
    /// the cores read and match each batch while the walk goes on — so the first hit comes as early
    /// as the serial search's and the whole tree finishes several times sooner. Each matching file
    /// goes to `onFile` as it is found (from whichever thread found it; calls never overlap). Same
    /// skip list, ignore rules, size cap, binary sniff, caps and cancellation as the serial search;
    /// the returned list is sorted by path, so only the ORDER of the `onFile` calls differs.
    public static func searchInParallel(
        query: String,
        in root: URL,
        caseSensitive: Bool,
        regex: Bool,
        isCancelled: @escaping @Sendable () -> Bool,
        include: (@Sendable (URL) -> Bool)? = nil,
        onFile: (@Sendable (SearchFileResult) -> Void)? = nil
    ) -> [SearchFileResult] {
        guard !query.isEmpty else { return [] }
        let regexObj: NSRegularExpression? =
            regex ? try? NSRegularExpression(pattern: query, options: caseSensitive ? [] : [.caseInsensitive]) : nil
        if regex && regexObj == nil { return [] }
        nonisolated(unsafe) let pattern = regexObj
        let mightMatch = prefilter(query: query, caseSensitive: caseSensitive, regexMode: regex)
        nonisolated(unsafe) let mayMatch = mightMatch
        let state = ParallelSearchState()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        // At most two batches per core in flight: reads block, and an unbounded fan-out would make
        // GCD spawn a thread per waiting read.
        let slots = DispatchSemaphore(value: max(2, ProcessInfo.processInfo.activeProcessorCount * 2))
        let batchSize = 16
        func dispatch(_ batch: [URL]) {
            slots.wait()
            group.enter()
            queue.async {
                defer { slots.signal(); group.leave() }
                for url in batch {
                    if isCancelled() || state.isFull(cap: maxTotalMatches) { return }
                    guard let text = readTextFile(url)?.text, mayMatch(text) else { continue }
                    let found = matches(in: text, query: query, caseSensitive: caseSensitive, regex: pattern)
                    guard !found.isEmpty else { continue }
                    let result = SearchFileResult(url: url, matches: found)
                    if state.add(result, cap: maxTotalMatches) { onFile.map { state.deliver(result, to: $0) } }
                }
            }
        }
        var batch: [URL] = []
        batch.reserveCapacity(batchSize)
        walkCandidates(in: root, isCancelled: isCancelled, include: include) { url, size in
            guard size <= maxFileBytes else { return true }
            batch.append(url)
            if batch.count == batchSize {
                dispatch(batch)
                batch.removeAll(keepingCapacity: true)
            }
            return !state.isFull(cap: maxTotalMatches)
        }
        if !batch.isEmpty { dispatch(batch) }
        group.wait()
        return state.results.sorted { $0.url.path.localizedCaseInsensitiveCompare($1.url.path) == .orderedAscending }
    }

    /// Every file a search would consider under `root`, in walk order — names and sizes only.
    static func candidateFiles(in root: URL, isCancelled: () -> Bool, include: ((URL) -> Bool)?, body: (URL) -> Void) {
        walkCandidates(in: root, isCancelled: isCancelled, include: include) { url, size in
            if size <= maxFileBytes { body(url) }
            return true
        }
    }
}
