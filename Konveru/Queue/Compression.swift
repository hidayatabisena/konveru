import Foundation

/// Understandable presets over the WebP quality value. `custom` appears only when the
/// More Options slider is set to a value no preset uses.
nonisolated enum Compression: Hashable, CaseIterable, Sendable {
    case smaller, balanced, higherQuality, custom, lossless

    static let presets: [Compression] = [.smaller, .balanced, .higherQuality]

    var quality: Double? {
        switch self {
        case .smaller: 65
        case .balanced: 80
        case .higherQuality: 92
        case .custom, .lossless: nil
        }
    }

    var title: String {
        switch self {
        case .smaller: String(localized: "Smaller File")
        case .balanced: String(localized: "Balanced")
        case .higherQuality: String(localized: "Higher Quality")
        case .custom: String(localized: "Custom")
        case .lossless: String(localized: "Lossless")
        }
    }
}
