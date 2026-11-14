import AppKit
import Observation
import SwiftUI

/// The current batch for one window: items, their status, and the running conversion.
@Observable
final class ConversionQueue {
    enum Phase { case empty, ready, converting, finished }
    enum ImportMode { case files, folder, destination }

    let settings: ConversionSettings
    private(set) var items: [QueueItem] = []
    var selection: Set<QueueItem.ID> = []
    private(set) var notices: [ImportNotice] = []

    var isImporterPresented = false
    private(set) var importMode = ImportMode.files

    private(set) var isConverting = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var currentName: String?

    @ObservationIgnored private var conversionTask: Task<Void, Never>?
    @ObservationIgnored private var convertAfterChoosingDestination = false

    init(settings: ConversionSettings = ConversionSettings()) {
        self.settings = settings
    }

    // MARK: State

    var phase: Phase {
        if isConverting { return .converting }
        if items.isEmpty { return .empty }
        if items.contains(where: { $0.status.isPending }) { return .ready }
        return .finished
    }

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var pendingCount: Int { items.count { $0.status.isPending } }
    var skipCount: Int { items.count { $0.status == .alreadyWebP && !$0.reencode } }
    var doneItems: [QueueItem] { items.filter { $0.status == .done } }
    var failedCount: Int { items.count { $0.status.isFailed } }
    var skippedCount: Int { items.count { $0.status == .skipped } }
    var canConvert: Bool { !isConverting && pendingCount > 0 && destinationProblem == nil }
    var canReveal: Bool { !doneItems.isEmpty }
    var canRemoveSelection: Bool { !isConverting && !selection.isEmpty }
    var hasCompleted: Bool { !isConverting && items.contains { $0.status == .done || $0.status == .skipped } }

    // MARK: Destination

    /// The folder every source shares, when there is exactly one.
    var commonBaseDirectory: URL? {
        let bases = Set(items.map(\.baseDirectory))
        return bases.count == 1 ? bases.first : nil
    }

    var destinationRoot: URL? {
        switch settings.destination {
        case .besideSources: commonBaseDirectory?.appending(path: Destination.subfolderName, directoryHint: .isDirectory)
        case .folder(let url): url
        }
    }

    /// Blocks Convert when a chosen folder has gone away.
    var destinationProblem: String? {
        guard case .folder(let url) = settings.destination else { return nil }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue { return nil }
        return String(localized: "“\(url.lastPathComponent)” is no longer available. Choose another destination.")
    }

    func outputDirectory(for item: QueueItem) -> URL? {
        guard let root = destinationRoot else { return nil }
        guard settings.keepFolderStructure, !item.relativeDirectory.isEmpty else { return root }
        return root.appending(path: item.relativeDirectory, directoryHint: .isDirectory)
    }

    /// Output filenames shown before and during conversion, with collisions against
    /// existing files and other queue items resolved the same way the writer does.
    // shortcut: one stat per pending item on each table render; fine for hundreds of files, cache per settings change if queues reach thousands.
    var outputNames: [QueueItem.ID: String] {
        let ext = settings.format.fileExtension
        var claimed = Set(items.compactMap(\.outputURL).map(FileNaming.key))
        var names: [QueueItem.ID: String] = [:]
        for item in items {
            if let url = item.outputURL {
                names[item.id] = url.lastPathComponent
                continue
            }
            guard item.willConvert else { continue }
            guard let directory = outputDirectory(for: item) else {
                names[item.id] = FileNaming.name(item.baseName, extension: ext, attempt: 1)
                continue
            }
            for attempt in 1... {
                let candidate = directory.appending(path: FileNaming.name(item.baseName, extension: ext, attempt: attempt))
                let key = FileNaming.key(candidate)
                if !claimed.contains(key), !FileManager.default.fileExists(atPath: candidate.path) {
                    claimed.insert(key)
                    names[item.id] = candidate.lastPathComponent
                    break
                }
            }
        }
        return names
    }

    // MARK: Adding and removing

    func beginImport(_ mode: ImportMode) {
        importMode = mode
        isImporterPresented = true
    }

    func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            convertAfterChoosingDestination = false
            return
        }
        switch importMode {
        case .files, .folder:
            add(urls)
        case .destination:
            settings.destination = .folder(urls[0])
            if convertAfterChoosingDestination {
                convertAfterChoosingDestination = false
                convert()
            }
        }
    }

    func add(_ urls: [URL]) {
        Task {
            let scan = await FileScanner.scan(urls)
            let existing = Set(items.map { FileNaming.key($0.url) })
            items += scan.items.filter { !existing.contains(FileNaming.key($0.url)) }
            notices = scan.notices
        }
    }

    func dismissNotice(_ notice: ImportNotice) {
        notices.removeAll { $0.id == notice.id }
    }

    func removeSelected() {
        guard canRemoveSelection else { return }
        items.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func remove(_ ids: Set<QueueItem.ID>) {
        guard !isConverting else { return }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    /// Removes finished entries from the queue; never touches files on disk.
    func clearCompleted() {
        guard !isConverting else { return }
        items.removeAll { $0.status == .done || $0.status == .skipped }
        selection = selection.filter { id in items.contains { $0.id == id } }
    }

    func setReencode(_ reencode: Bool, for ids: Set<QueueItem.ID>) {
        for index in items.indices where ids.contains(items[index].id) && items[index].isWebP {
            items[index].reencode = reencode
            if !isConverting, items[index].status == .skipped { items[index].status = .alreadyWebP }
        }
    }

    // MARK: Converting

    func convert() {
        convert(only: nil)
    }

    func retryFailed() {
        retry(Set(items.filter { $0.status.isFailed }.map(\.id)))
    }

    func retry(_ ids: Set<QueueItem.ID>) {
        guard !isConverting else { return }
        for index in items.indices where ids.contains(items[index].id) && items[index].status.isFailed {
            items[index].status = .ready
        }
        convert(only: ids)
    }

    private func convert(only ids: Set<QueueItem.ID>?) {
        guard !isConverting, destinationProblem == nil else { return }
        guard destinationRoot != nil else {
            // Sources live in different folders: ask for one destination.
            convertAfterChoosingDestination = true
            beginImport(.destination)
            return
        }

        var batch: [QueueItem.ID] = []
        for index in items.indices where ids?.contains(items[index].id) ?? true {
            switch items[index].status {
            case .ready, .canceled:
                items[index].status = .queued
                batch.append(items[index].id)
            case .alreadyWebP:
                if items[index].reencode {
                    items[index].status = .queued
                    batch.append(items[index].id)
                } else {
                    items[index].status = .skipped
                }
            default:
                break
            }
        }

        completedCount = 0
        totalCount = batch.count
        isConverting = true
        conversionTask = Task { await run(batch) }
    }

    func cancel() {
        conversionTask?.cancel()
    }

    // shortcut: items convert one at a time (accurate "n of N", simple cancel); run a small task group if batch speed matters.
    private func run(_ batch: [QueueItem.ID]) async {
        let options = settings.options
        for id in batch {
            if Task.isCancelled { break }
            guard let index = items.firstIndex(where: { $0.id == id }), let directory = outputDirectory(for: items[index]) else { continue }
            let item = items[index]
            items[index].status = .converting
            currentName = item.name

            let status: ItemStatus
            var output: ImageConverter.Output?
            do {
                output = try await ImageConverter.convert(item.url, into: directory, baseName: item.baseName, options: options)
                status = .done
            } catch is CancellationError {
                status = .canceled
            } catch let failure as ConversionFailure {
                status = .failed(failure)
            } catch {
                status = .failed(ConversionFailure(message: String(localized: "Couldn’t convert \(item.name)."), details: "\(error)"))
            }

            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].status = status
                items[index].outputURL = output?.url
                items[index].resultSize = output?.size
            }
            completedCount += 1
        }

        for index in items.indices where items[index].status == .queued {
            items[index].status = .canceled
        }
        isConverting = false
        currentName = nil
        AccessibilityNotification.Announcement(completionSummary).post()
    }

    var completionSummary: String {
        let canceled = items.count { $0.status == .canceled }
        var summary = String(localized: "Finished. \(doneItems.count) converted, \(skippedCount) skipped, \(failedCount) failed.")
        if canceled > 0 { summary += " " + String(localized: "\(canceled) canceled.") }
        return summary
    }

    func revealResults() {
        let urls = doneItems.compactMap(\.outputURL)
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func revealInFinder(_ ids: Set<QueueItem.ID>) {
        let urls = items.filter { ids.contains($0.id) }.map { $0.outputURL ?? $0.url }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}
