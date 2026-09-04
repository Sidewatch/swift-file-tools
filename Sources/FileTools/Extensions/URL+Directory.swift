import Foundation

extension URL {
    /// Whether the URL names a directory, per the file system (false when unreadable).
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }
}
