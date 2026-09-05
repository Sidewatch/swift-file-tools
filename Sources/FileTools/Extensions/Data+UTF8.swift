//
//  Data+UTF8.swift
//  FileTools
//
//  The bytes as a UTF-8 string, or nil when they are not valid UTF-8.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

extension Data {
    /// The bytes as a UTF-8 string, or nil when they are not valid UTF-8.
    var utf8String: String? { String(data: self, encoding: .utf8) }
}
