import Foundation
import Observation

/// Output settings, remembered between batches and launches.
@Observable
final class ConversionSettings {
    var format = OutputFormat.webp
    var lossless: Bool { didSet { defaults.set(lossless, forKey: "lossless") } }
    var quality: Double { didSet { defaults.set(quality, forKey: "quality") } }
    var removeLocation: Bool { didSet { defaults.set(removeLocation, forKey: "removeLocation") } }
    var keepMetadata: Bool { didSet { defaults.set(keepMetadata, forKey: "keepMetadata") } }
    var keepFolderStructure: Bool { didSet { defaults.set(keepFolderStructure, forKey: "keepFolderStructure") } }
    var destination: Destination {
        didSet {
            if case .folder(let url) = destination {
                recentFolder = url
                defaults.set(url.path, forKey: "destinationFolder")
            } else {
                defaults.removeObject(forKey: "destinationFolder")
            }
        }
    }
    /// Last chosen folder, kept in the destination menu after switching back.
    private(set) var recentFolder: URL?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "lossless": false, "quality": 80.0, "removeLocation": true,
            "keepMetadata": true, "keepFolderStructure": true,
        ])
        lossless = defaults.bool(forKey: "lossless")
        quality = defaults.double(forKey: "quality")
        removeLocation = defaults.bool(forKey: "removeLocation")
        keepMetadata = defaults.bool(forKey: "keepMetadata")
        keepFolderStructure = defaults.bool(forKey: "keepFolderStructure")
        if let path = defaults.string(forKey: "destinationFolder") {
            let url = URL(filePath: path, directoryHint: .isDirectory)
            destination = .folder(url)
            recentFolder = url
        } else {
            destination = .besideSources
        }
    }

    /// Switching to lossless keeps the chosen lossy quality for later.
    var compression: Compression {
        get {
            if lossless { return .lossless }
            return Compression.presets.first { $0.quality == quality } ?? .custom
        }
        set {
            lossless = newValue == .lossless
            if let preset = newValue.quality { quality = preset }
        }
    }

    var options: ConversionOptions {
        ConversionOptions(lossless: lossless, quality: quality, removeLocation: removeLocation || !keepMetadata, keepMetadata: keepMetadata)
    }

    var metadataSummary: String {
        if !keepMetadata { return String(localized: "Metadata removed") }
        return removeLocation ? String(localized: "Location data removed") : String(localized: "Metadata kept")
    }
}
