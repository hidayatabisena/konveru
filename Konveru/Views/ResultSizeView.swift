import SwiftUI

/// Output size; a result larger than its source is marked with an arrow and text, not color alone.
struct ResultSizeView: View {
    let item: QueueItem

    var body: some View {
        if let size = item.resultSize {
            let formatted = size.formatted(.byteCount(style: .file))
            if size > item.size {
                Label(formatted, systemImage: "arrow.up")
                    .labelStyle(TrailingIconLabelStyle())
                    .foregroundStyle(.orange)
                    .monospacedDigit()
                    .help("Larger than the source")
                    .accessibilityLabel("\(formatted), larger than the source")
            } else {
                Text(formatted)
                    .monospacedDigit()
            }
        } else {
            Text("—")
                .foregroundStyle(.secondary)
                .accessibilityLabel("No result")
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.title
            configuration.icon
        }
    }
}
