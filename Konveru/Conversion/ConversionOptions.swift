import Foundation

nonisolated struct ConversionOptions: Sendable, Equatable {
    var lossless = false
    var quality = 80.0
    var removeLocation = true
    var keepMetadata = true
}
