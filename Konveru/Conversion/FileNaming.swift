import Foundation

nonisolated enum FileNaming {
    /// `IMG_2041.webp`, then `IMG_2041 2.webp`, `IMG_2041 3.webp`, …
    static func name(_ baseName: String, extension ext: String, attempt: Int) -> String {
        attempt == 1 ? "\(baseName).\(ext)" : "\(baseName) \(attempt).\(ext)"
    }

    /// Paths are compared case-insensitively because the default APFS volume is.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.lowercased()
    }
}
