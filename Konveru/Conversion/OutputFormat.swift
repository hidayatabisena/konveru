import Foundation

/// Output formats the bundled encoders can actually write. Future audio, video and
/// document converters add their own families; v1 only writes WebP.
nonisolated enum OutputFormat: String, CaseIterable, Identifiable, Sendable {
    case webp

    var id: Self { self }
    var displayName: String { "WebP" }
    var fileExtension: String { "webp" }
}
