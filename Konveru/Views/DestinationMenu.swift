import SwiftUI

/// "Konveru" beside sources, a remembered folder, or Choose Folder…
struct DestinationMenu: View {
    @Bindable var settings: ConversionSettings
    let queue: ConversionQueue
    var shortTitles = false

    var body: some View {
        Menu {
            Picker("Destination", selection: $settings.destination) {
                Text(besideTitle).tag(Destination.besideSources)
                if let folder = settings.recentFolder {
                    Text(folder.lastPathComponent).tag(Destination.folder(folder))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Divider()
            Button("Choose Folder…") { queue.beginImport(.destination) }
        } label: {
            Text(title)
        }
        .accessibilityLabel("Destination")
        .accessibilityValue(title)
    }

    private var besideTitle: String {
        shortTitles ? String(localized: "“Konveru” beside sources") : String(localized: "“Konveru” folder beside sources")
    }

    private var title: String {
        switch settings.destination {
        case .besideSources: besideTitle
        case .folder(let url): url.lastPathComponent
        }
    }
}
