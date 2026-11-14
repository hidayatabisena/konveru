import Foundation
import UniformTypeIdentifiers

/// Expands dropped or chosen files and folders into queue items off the main actor.
nonisolated enum FileScanner {
    struct Result: Sendable {
        var items: [QueueItem] = []
        var notices: [ImportNotice] = []
    }

    static let acceptedTypes: [UTType] = [.jpeg, .png, .heic, .heif, .webP]

    @concurrent
    static func scan(_ urls: [URL]) async -> Result {
        var result = Result()
        var looseSkipped: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentTypeKey, .fileSizeKey, .isRegularFileKey]

        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isPackage != true {
                scanFolder(url, keys: keys, into: &result)
            } else if let item = makeItem(url, base: url.deletingLastPathComponent(), relative: "", values: values) {
                result.items.append(item)
            } else {
                looseSkipped.append(url)
            }
        }
        if !looseSkipped.isEmpty {
            result.notices.append(ImportNotice(
                folderName: nil,
                skippedNames: looseSkipped.map(\.lastPathComponent),
                skippedKinds: kinds(of: looseSkipped),
                folderHadNoImages: false
            ))
        }
        return result
    }

    private static func scanFolder(_ folder: URL, keys: [URLResourceKey], into result: inout Result) {
        var found: [QueueItem] = []
        var skipped: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        let basePath = folder.standardizedFileURL.path
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, values?.isPackage != true {
                // Konveru's own output folder: re-adding a converted folder shouldn't re-import results.
                if url.lastPathComponent == Destination.subfolderName, url.deletingLastPathComponent().standardizedFileURL.path == basePath {
                    enumerator?.skipDescendants()
                }
                continue
            }
            let parentPath = url.deletingLastPathComponent().standardizedFileURL.path
            let relative = parentPath.count > basePath.count ? String(parentPath.dropFirst(basePath.count + 1)) : ""
            if let item = makeItem(url, base: folder, relative: relative, values: values) {
                found.append(item)
            } else {
                skipped.append(url)
            }
        }
        found.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        result.items += found
        if found.isEmpty || !skipped.isEmpty {
            result.notices.append(ImportNotice(
                folderName: folder.lastPathComponent,
                skippedNames: skipped.map(\.lastPathComponent),
                skippedKinds: kinds(of: skipped),
                folderHadNoImages: found.isEmpty
            ))
        }
    }

    private static func makeItem(_ url: URL, base: URL, relative: String, values: URLResourceValues?) -> QueueItem? {
        guard values?.isRegularFile == true, let type = values?.contentType, let kind = kind(of: type) else { return nil }
        return QueueItem(
            url: url,
            baseDirectory: base.standardizedFileURL,
            relativeDirectory: relative,
            kind: kind,
            size: Int64(values?.fileSize ?? 0),
            status: kind == "WEBP" ? .alreadyWebP : .ready
        )
    }

    static func kind(of type: UTType) -> String? {
        if type.conforms(to: .jpeg) { return "JPEG" }
        if type.conforms(to: .png) { return "PNG" }
        if type.conforms(to: .heic) { return "HEIC" }
        if type.conforms(to: .heif) { return "HEIF" }
        if type.conforms(to: .webP) { return "WEBP" }
        return nil
    }

    private static func kinds(of urls: [URL]) -> [String] {
        var seen: [String] = []
        for url in urls {
            let type = UTType(filenameExtension: url.pathExtension)
            let label = type?.conforms(to: .rawImage) == true ? "RAW" : (url.pathExtension.isEmpty ? String(localized: "no extension") : url.pathExtension.uppercased())
            if !seen.contains(label) { seen.append(label) }
        }
        return seen
    }
}
