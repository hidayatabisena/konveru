import SwiftUI

/// Status is always symbol + text; color only reinforces it.
struct StatusLabel: View {
    let item: QueueItem

    var body: some View {
        Label {
            Text(title)
        } icon: {
            if item.status == .converting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: LocalizedStringKey {
        switch item.status {
        case .ready: "Ready"
        case .alreadyWebP: item.reencode ? "Re-encode" : "Already WebP"
        case .queued: "Queued"
        case .converting: "Converting"
        case .done: "Done"
        case .skipped: "Skipped"
        case .canceled: "Canceled"
        case .failed: "Failed"
        }
    }

    private var symbol: String {
        switch item.status {
        case .ready: "arrow.right.circle"
        case .alreadyWebP: item.reencode ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle"
        case .queued: "clock"
        case .converting: "circle.dotted"
        case .done: "checkmark.circle"
        case .skipped: "minus.circle"
        case .canceled: "xmark.circle"
        case .failed: "xmark.octagon"
        }
    }

    private var tint: Color {
        switch item.status {
        case .done: .green
        case .failed: .red
        case .alreadyWebP: item.reencode ? .secondary : .orange
        default: .secondary
        }
    }
}
