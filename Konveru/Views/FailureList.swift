import SwiftUI

/// Failed items with their reason and next action, kept above the list after a batch.
struct FailureList: View {
    let queue: ConversionQueue

    var body: some View {
        let failed = queue.items.filter { $0.status.isFailed }
        ScrollView {
            VStack(spacing: 1) {
                ForEach(failed) { item in
                    if case .failed(let failure) = item.status {
                        FailureRow(item: item, failure: failure, queue: queue)
                    }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 180)
        .fixedSize(horizontal: false, vertical: true)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Items that need attention")
    }
}

private struct FailureRow: View {
    let item: QueueItem
    let failure: ConversionFailure
    let queue: ConversionQueue
    @State private var showsDetails = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "xmark.octagon")
                .foregroundStyle(.red)
                .accessibilityLabel("Failed")
            Text(failure.message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show Details") { showsDetails = true }
                .popover(isPresented: $showsDetails) {
                    Text(failure.details)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: 420)
                }
            Button("Retry") { queue.retry([item.id]) }
                .disabled(queue.isConverting)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.red.opacity(0.08))
        .accessibilityElement(children: .contain)
    }
}
