import SwiftUI

/// Counts and size totals after a batch. Totals cover converted files only.
struct SummaryHeader: View {
    let queue: ConversionQueue

    var body: some View {
        let done = queue.doneItems
        let sourceTotal = done.reduce(0) { $0 + $1.size }
        let resultTotal = done.reduce(0) { $0 + ($1.resultSize ?? 0) }
        let largerCount = done.count { ($0.resultSize ?? 0) > $0.size }

        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 24) {
                counts
                Divider().frame(maxHeight: 48)
                totals(source: sourceTotal, result: resultTotal)
                Spacer(minLength: 0)
                largerNote(largerCount)
                    .frame(maxWidth: 260, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 24) {
                    counts
                    totals(source: sourceTotal, result: resultTotal)
                }
                largerNote(largerCount)
            }
        }
        .padding(16)
    }

    private var counts: some View {
        HStack(alignment: .top, spacing: 24) {
            stat(queue.doneItems.count, "Converted", symbol: "checkmark.circle", tint: .green)
            stat(queue.skippedCount, "Skipped", symbol: "minus.circle", tint: .secondary)
            stat(queue.failedCount, "Failed", symbol: "xmark.octagon", tint: .red)
        }
    }

    private func stat(_ count: Int, _ title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count, format: .number)
                .font(.title.bold())
                .monospacedDigit()
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol).foregroundStyle(tint)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    private func totals(source: Int64, result: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(source.formatted(.byteCount(style: .file))) → \(result.formatted(.byteCount(style: .file)))")
                .font(.title.bold())
                .monospacedDigit()
            Text("Converted files only · sources kept")
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func largerNote(_ count: Int) -> some View {
        if count > 0 {
            Text("\(count) results are larger than their source. They’re marked in the list.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
