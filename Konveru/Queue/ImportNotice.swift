import Foundation

/// Reported after adding files, so unsupported items are never silently discarded.
nonisolated struct ImportNotice: Identifiable, Sendable {
    let id = UUID()
    /// Name of the imported folder, or nil for loose files.
    let folderName: String?
    let skippedNames: [String]
    let skippedKinds: [String]
    /// True when a folder contained nothing Konveru can convert.
    let folderHadNoImages: Bool

    var message: String {
        let kinds = skippedKinds.formatted(.list(type: .and, width: .narrow))
        if folderHadNoImages, let folderName {
            return String(localized: "“\(folderName)” has no JPEG, PNG or HEIC images, so nothing was added.")
        }
        if let folderName {
            return String(localized: "\(skippedNames.count) items in “\(folderName)” can’t be converted (\(kinds)) and weren’t added.")
        }
        return String(localized: "\(skippedNames.count) items can’t be converted (\(kinds)) and weren’t added.")
    }
}
