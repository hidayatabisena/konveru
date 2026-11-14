import Foundation

/// A per-item failure: `message` is the actionable sentence shown in the list,
/// `details` is the raw system or encoder message shown only on request.
nonisolated struct ConversionFailure: Error, Equatable, Sendable {
    let message: String
    let details: String
}
