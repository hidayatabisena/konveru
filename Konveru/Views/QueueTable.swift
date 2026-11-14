import QuickLook
import SwiftUI

struct QueueTable: View {
    @Bindable var queue: ConversionQueue
    let isCompact: Bool
    @State private var quickLookURL: URL?

    var body: some View {
        let outputNames = queue.outputNames
        let showsResult = !queue.isConverting && !queue.doneItems.isEmpty

        Table(queue.items, selection: $queue.selection) {
            TableColumn("Name") { item in
                Label {
                    Text(item.name)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } icon: {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                .labelStyle(NameLabelStyle(showsIcon: !isCompact))
                .help(item.url.path(percentEncoded: false))
            }
            .width(min: 100, ideal: 140)

            if !isCompact {
                TableColumn("Type") { item in
                    Text(item.kind)
                }
                .width(min: 40, ideal: 44)
            }

            TableColumn("Size") { item in
                Text(item.size.formatted(.byteCount(style: .file)))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 52, ideal: 60)

            TableColumn("Output") { item in
                Text(outputNames[item.id] ?? "—")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.outputURL?.path(percentEncoded: false) ?? outputNames[item.id] ?? "")
                    .accessibilityLabel(outputNames[item.id].map { Text($0) } ?? Text("No output"))
            }
            .width(min: 90, ideal: 120)

            if showsResult {
                TableColumn("Result") { item in
                    ResultSizeView(item: item)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 72, ideal: 76)
            }

            TableColumn("Status") { item in
                StatusLabel(item: item)
                    .help(failureMessage(item) ?? "")
            }
            .width(min: 96, ideal: 110)
        }
        .contextMenu(forSelectionType: QueueItem.ID.self) { ids in
            rowMenu(ids)
        } primaryAction: { ids in
            queue.revealInFinder(ids)
        }
        .onKeyPress(.space) {
            guard let url = selectedURLs.first else { return .ignored }
            quickLookURL = quickLookURL == nil ? url : nil
            return .handled
        }
        .quickLookPreview($quickLookURL, in: selectedURLs)
    }

    /// Selected files in table order, so Quick Look's arrows follow the list.
    private var selectedURLs: [URL] {
        queue.items.filter { queue.selection.contains($0.id) }.map(\.url)
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<QueueItem.ID>) -> some View {
        if !ids.isEmpty {
            let rows = queue.items.filter { ids.contains($0.id) }
            Button("Quick Look") { quickLookURL = rows.first?.url }
            Button("Reveal in Finder") { queue.revealInFinder(ids) }
            if rows.contains(where: { $0.status.isFailed }) {
                Button("Retry") { queue.retry(ids) }
                    .disabled(queue.isConverting)
            }
            if rows.contains(where: { $0.isWebP && !$0.reencode && $0.status != .done }) {
                Button("Re-encode as WebP") { queue.setReencode(true, for: ids) }
            }
            if rows.contains(where: { $0.isWebP && $0.reencode && $0.status != .done }) {
                Button("Skip Already WebP") { queue.setReencode(false, for: ids) }
            }
            Divider()
            Button("Remove from Queue") { queue.remove(ids) }
                .disabled(queue.isConverting)
        }
    }

    private func failureMessage(_ item: QueueItem) -> String? {
        if case .failed(let failure) = item.status { failure.message } else { nil }
    }
}

/// Hides the file icon in the compact layout, matching the narrow-window reference.
private struct NameLabelStyle: LabelStyle {
    let showsIcon: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            if showsIcon { configuration.icon.accessibilityHidden(true) }
            configuration.title
        }
    }
}
