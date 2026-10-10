//
//  ProjectFolderError.swift
//  FileTools
//
//  Why a new project folder was refused: something already holds that name.
//
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A folder ``ProjectFolder/create(at:)`` refused, named so a host can say why in its own words.
/// Nothing at the path is changed in either case.
public enum ProjectFolderError: Error, Equatable {
    /// A folder with that name exists and holds files.
    case notEmpty(URL)
    /// Something other than a folder (a file, a link) holds that name.
    case notAFolder(URL)
}
