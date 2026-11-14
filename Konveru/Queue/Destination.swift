import Foundation

nonisolated enum Destination: Hashable, Sendable {
    /// A "Konveru" folder inside the shared source folder.
    case besideSources
    case folder(URL)

    static let subfolderName = "Konveru"
}
