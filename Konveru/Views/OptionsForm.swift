import SwiftUI

/// Output, metadata and destination settings. Shown beside the queue in wide windows
/// and in a popover from the compact options bar.
struct OptionsForm: View {
    @Bindable var settings: ConversionSettings
    let queue: ConversionQueue
    @AppStorage("showsMoreOptions") private var showsMoreOptions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if queue.isConverting {
                Label("Options are locked while converting.", systemImage: "lock")
                    .foregroundStyle(.secondary)
            }

            section("Output") {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 12) {
                    GridRow {
                        rowLabel("Format")
                        Picker("Format", selection: $settings.format) {
                            ForEach(OutputFormat.allCases) { Text($0.displayName).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        rowLabel("Compression")
                        Picker("Compression", selection: $settings.compression) {
                            ForEach(Compression.presets, id: \.self) { Text($0.title).tag($0) }
                            if settings.compression == .custom {
                                Text(Compression.custom.title).tag(Compression.custom)
                            }
                            if settings.lossless {
                                Text(Compression.lossless.title).tag(Compression.lossless)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .disabled(settings.lossless)
                    }
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Toggle("Lossless", isOn: $settings.lossless)
                    }
                }
                DisclosureGroup("More Options", isExpanded: $showsMoreOptions) {
                    QualitySlider(quality: $settings.quality)
                        .disabled(settings.lossless)
                        .padding(.top, 8)
                }
            }

            section("Metadata") {
                Toggle("Remove location data", isOn: $settings.removeLocation)
                    .disabled(!settings.keepMetadata)
                Toggle("Keep other metadata", isOn: $settings.keepMetadata)
                note(String(localized: "What can be kept depends on the source format. The color profile is always kept."))
            }

            section("Destination") {
                DestinationMenu(settings: settings, queue: queue)
                note(destinationNote)
                    .foregroundStyle(queue.destinationProblem == nil ? Color.secondary : Color.red)
                    .textSelection(.enabled)
                Toggle("Keep subfolder structure", isOn: $settings.keepFolderStructure)
                    .help("Files from added folders keep their subfolders inside the destination.")
                note(String(localized: "If a file already exists, a number is added — e.g. “IMG_2041 2.webp”. Originals are never replaced."))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(queue.isConverting)
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func rowLabel(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .gridColumnAlignment(.trailing)
            .accessibilityHidden(true) // the picker carries the same label
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var destinationNote: String {
        if let problem = queue.destinationProblem { return problem }
        if let root = queue.destinationRoot {
            return (root.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
        if queue.items.isEmpty {
            return String(localized: "Used when all files share one folder. Otherwise you’ll be asked to choose one.")
        }
        return String(localized: "These files are in different folders, so you’ll be asked to choose a destination.")
    }
}
