//
//  FSEvent.swift
//  FileTools
//
//  The kinds of file-system change reported by ``DirectoryEventStream``.
//
//  Created by David Sherlock on 7/9/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A single kind of file-system change surfaced by ``DirectoryEventStream``.
///
/// The FSEvents API can report several of these for one raw flag value, so a
/// single change may map to more than one case.
public enum FSEvent: String {

    /// A generic change occurred somewhere in the watched directory.
    case changeInDirectory

    /// The watched root itself changed (moved, renamed or deleted).
    case rootChanged

    /// An item's owner changed.
    case itemChangedOwner

    /// An item was created.
    case itemCreated

    /// An item was cloned.
    case itemCloned

    /// An item's contents were modified.
    case itemModified

    /// An item was removed.
    case itemRemoved

    /// An item was renamed.
    case itemRenamed
}
