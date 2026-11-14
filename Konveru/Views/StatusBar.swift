import SwiftUI

/// Batch summary, progress and the single primary action for the current state.
struct StatusBar: View {
    let queue: ConversionQueue

    var body: some View {
        HStack(spacing: 16) {
            switch queue.phase {
            case .empty:
                Text("Add files to start a batch")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Convert") {}
                    .disabled(true)
            case .ready:
                readySummary
                Spacer()
                Text(verbatim: "⌘↩")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Button("Convert") { queue.convert() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!queue.canConvert)
            case .converting:
                progress
                Button("Cancel", role: .cancel) { queue.cancel() }
                    .keyboardShortcut(.cancelAction)
            case .finished:
                Text(savedTo)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(savedTo)
                Spacer()
                if queue.failedCount > 0 {
                    Button("Retry Failed") { queue.retryFailed() }
                }
                Button("Reveal Results") { queue.revealResults() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!queue.canReveal)
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var readySummary: some View {
        let files = Text("\(queue.pendingCount) files → \(queue.settings.format.displayName)").bold()
        let text: Text
        if let problem = queue.destinationProblem {
            text = Text("\(files) · \(Text(problem).foregroundStyle(.red))")
        } else if queue.skipCount > 0 {
            text = Text("\(files) · \(queue.skipCount) already WebP will be skipped")
        } else {
            text = files
        }
        return text.lineLimit(2)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Converting “\(queue.currentName ?? "")”…")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(min(queue.completedCount + 1, queue.totalCount)) of \(queue.totalCount)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(queue.completedCount), total: Double(max(queue.totalCount, 1)))
                .accessibilityLabel("Conversion progress")
                .accessibilityValue("\(queue.completedCount) of \(queue.totalCount) files")
        }
    }

    private var savedTo: String {
        let directories = Set(queue.doneItems.compactMap { $0.outputURL?.deletingLastPathComponent() })
        let root = queue.destinationRoot ?? directories.first
        guard let root, !queue.doneItems.isEmpty else { return String(localized: "Nothing was converted") }
        return String(localized: "Saved to \((root.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)")
    }
}
