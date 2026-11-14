import SwiftUI

/// Options stacked under the queue in narrow windows.
struct CompactOptionsBar: View {
    @Bindable var settings: ConversionSettings
    let queue: ConversionQueue
    @State private var showsMoreOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    Text("Format")
                    Text("Compression")
                    Text("Save to")
                }
                .accessibilityHidden(true)
                GridRow {
                    Picker("Format", selection: $settings.format) {
                        ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Compression", selection: $settings.compression) {
                        ForEach(Compression.presets, id: \.self) { Text($0.title).tag($0) }
                        if settings.compression == .custom {
                            Text(Compression.custom.title).tag(Compression.custom)
                        }
                        Divider()
                        Text(Compression.lossless.title).tag(Compression.lossless)
                    }
                    DestinationMenu(settings: settings, queue: queue, shortTitles: true)
                }
                .labelsHidden()
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    summary
                    Spacer()
                    moreOptionsButton
                }
                VStack(alignment: .leading, spacing: 4) {
                    summary
                    moreOptionsButton
                }
            }
        }
        .padding(16)
        .disabled(queue.isConverting)
    }

    private var summary: some View {
        Text("\(settings.metadataSummary) · Existing names get a number · Originals never replaced")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private var moreOptionsButton: some View {
        Button("More Options…") { showsMoreOptions = true }
            .buttonStyle(.link)
            .popover(isPresented: $showsMoreOptions, arrowEdge: .top) {
                OptionsForm(settings: settings, queue: queue)
                    .padding()
                    .frame(width: 360)
            }
    }
}
