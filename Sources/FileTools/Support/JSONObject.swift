//
//  JSONObject.swift
//  FileTools
//
//  JSON the way this package reads it: a top-level object, or nil.
//
//  Created by David Sherlock on 9/5/26.
//

import Foundation

/// JSON the way this package reads it: a top-level object, or nil.
enum JSONObject {
    /// The top-level object in `data`, or nil when it is not JSON or not an object.
    static func parse(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
