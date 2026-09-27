//
//  IgnoreFileNamesTests.swift
//  FileToolsTests
//
//  A path names an ignore file by its last component only.
//
//  Created by David Sherlock on 9/27/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import FileTools

final class IgnoreFileNamesTests: XCTestCase {
    func testOnlyTheIgnoreFilesThemselvesMatch() {
        XCTAssertTrue(IgnoreFileNames.names("/p/.gitignore"))
        XCTAssertTrue(IgnoreFileNames.names("sub/.rgignore"))
        XCTAssertFalse(IgnoreFileNames.names("/p/.gitignore.bak"))
        XCTAssertFalse(IgnoreFileNames.names("/p/.gitignore/inside"), "a folder named like one is not the file")
        XCTAssertFalse(IgnoreFileNames.names("/p/gitignore"))
    }
}
