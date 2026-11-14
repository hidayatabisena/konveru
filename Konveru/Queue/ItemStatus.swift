import Foundation

nonisolated enum ItemStatus: Equatable, Sendable {
    case ready
    case alreadyWebP
    case queued
    case converting
    case done
    case skipped
    case canceled
    case failed(ConversionFailure)

    /// Items that Convert will pick up.
    var isPending: Bool {
        switch self {
        case .ready, .alreadyWebP, .canceled: true
        default: false
        }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}
