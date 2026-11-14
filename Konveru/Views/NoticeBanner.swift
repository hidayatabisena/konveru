import SwiftUI

/// Explains unsupported items found while adding, with a way to see them.
struct NoticeBanner: View {
    let notice: ImportNotice
    let queue: ConversionQueue
    @State private var showsItems = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(notice.message)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if notice.folderHadNoImages {
                Button("Add Files…") { queue.beginImport(.files) }
            }
            if !notice.skippedNames.isEmpty {
                Button("Show Items") { showsItems = true }
                    .popover(isPresented: $showsItems) {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(notice.skippedNames, id: \.self) { Text($0) }
                            }
                            .padding()
                            .textSelection(.enabled)
                        }
                        .frame(minWidth: 240, maxHeight: 320)
                    }
            }
            Button("Dismiss", systemImage: "xmark") { queue.dismissNotice(notice) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
