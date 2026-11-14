import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var queue = ConversionQueue()
    @State private var isCompact = false
    @State private var isDropTargeted = false
    @AppStorage("showsOptions") private var showsOptions = true
    @FocusState private var isTableFocused: Bool

    var body: some View {
        @Bindable var queue = queue

        VStack(spacing: 0) {
            if isCompact {
                VStack(spacing: 0) {
                    mainArea
                    if showsOptions {
                        Divider()
                        CompactOptionsBar(settings: queue.settings, queue: queue)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    mainArea
                    if showsOptions {
                        Divider()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                if let item = selectedItem {
                                    SelectionPreview(item: item)
                                }
                                OptionsForm(settings: queue.settings, queue: queue)
                            }
                            .padding(16)
                        }
                        .frame(width: 280)
                    }
                }
            }
            Divider()
            StatusBar(queue: queue)
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 820 } action: { isCompact = $0 }
        .frame(minWidth: 680, minHeight: 460)
        .navigationTitle("Konveru")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .dropDestination(for: URL.self) { urls, _ in
            queue.add(urls)
            return !urls.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .fileImporter(
            isPresented: $queue.isImporterPresented,
            allowedContentTypes: queue.importMode == .files ? FileScanner.acceptedTypes : [.folder],
            allowsMultipleSelection: queue.importMode != .destination,
            onCompletion: queue.handleImport
        )
        .fileDialogMessage(dialogMessage)
        .fileDialogConfirmationLabel(queue.importMode == .destination ? "Choose" : "Add")
        .onOpenURL { queue.add([$0]) }
        .focusedSceneValue(\.conversionQueue, queue)
        #if DEBUG
        .task { await DebugHarness.run(queue) }
        #endif
    }

    @ViewBuilder
    private var mainArea: some View {
        VStack(spacing: 0) {
            if queue.items.isEmpty {
                if let notice = queue.notices.first {
                    NoticeBanner(notice: notice, queue: queue)
                        .padding([.horizontal, .top], 16)
                }
                DropZoneView(queue: queue, isTargeted: isDropTargeted)
            } else {
                if queue.phase == .finished {
                    SummaryHeader(queue: queue)
                    Divider()
                }
                VStack(spacing: 8) {
                    ForEach(queue.notices) { NoticeBanner(notice: $0, queue: queue) }
                    if !queue.isConverting && queue.failedCount > 0 {
                        FailureList(queue: queue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, queue.notices.isEmpty && (queue.isConverting || queue.failedCount == 0) ? 0 : 8)

                QueueTable(queue: queue, isCompact: isCompact)
                    .focused($isTableFocused)
                    .onAppear { isTableFocused = true } // keyboard users can select and remove rows right away
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                .allowsHitTesting(false)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Add Files", systemImage: "doc.badge.plus") { queue.beginImport(.files) }
                .help("Add Files… (⌘O)")
                .labelStyle(ToolbarLabelStyle(showsTitle: !isCompact))
            Button("Add Folder", systemImage: "folder.badge.plus") { queue.beginImport(.folder) }
                .help("Add Folder… (⇧⌘O)")
                .labelStyle(ToolbarLabelStyle(showsTitle: !isCompact))
            if queue.hasCompleted {
                Button("Clear Completed", systemImage: "text.badge.xmark") { queue.clearCompleted() }
                    .help("Remove converted and skipped items from the list. Files stay on disk.")
                    .labelStyle(ToolbarLabelStyle(showsTitle: !isCompact))
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button(
                showsOptions ? "Hide Options" : "Show Options",
                systemImage: isCompact ? "rectangle.bottomthird.inset.filled" : "sidebar.right"
            ) {
                showsOptions.toggle()
            }
            .help("Show or hide options (⌥⌘O)")
            .labelStyle(.iconOnly)
        }
    }

    private var selectedItem: QueueItem? {
        guard queue.selection.count == 1 else { return nil }
        return queue.items.first { queue.selection.contains($0.id) }
    }

    private var subtitle: String {
        switch queue.phase {
        case .empty:
            return String(localized: "No files")
        case .ready:
            return String(localized: "\(queue.items.count) files · \(queue.totalSize.formatted(.byteCount(style: .file)))")
        case .converting:
            return String(localized: "Converting \(min(queue.completedCount + 1, queue.totalCount)) of \(queue.totalCount)")
        case .finished:
            return queue.failedCount > 0
                ? String(localized: "Finished · \(queue.failedCount) need attention")
                : String(localized: "Finished")
        }
    }

    private var dialogMessage: String {
        switch queue.importMode {
        case .files: String(localized: "Choose JPEG, PNG or HEIC images to convert.")
        case .folder: String(localized: "Choose folders. Images inside, including subfolders, are added.")
        case .destination: String(localized: "Choose where to save converted files.")
        }
    }
}
