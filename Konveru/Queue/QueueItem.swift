import Foundation

nonisolated struct QueueItem: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    /// The folder the item was imported from, or its parent for individually added files.
    let baseDirectory: URL
    /// Subfolder path inside `baseDirectory`; empty for individually added files.
    let relativeDirectory: String
    /// Short type label shown in the Type column, e.g. "JPEG".
    let kind: String
    let size: Int64
    var status: ItemStatus
    /// WebP sources are skipped unless the person chooses to re-encode them.
    var reencode = false
    var outputURL: URL?
    var resultSize: Int64?

    var name: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var isWebP: Bool { kind == "WEBP" }
    var willConvert: Bool {
        switch status {
        case .alreadyWebP: reencode
        case .ready, .queued, .converting, .canceled, .failed: true
        case .done, .skipped: false
        }
    }
}
