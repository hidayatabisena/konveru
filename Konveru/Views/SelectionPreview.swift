import QuickLookThumbnailing
import SwiftUI

/// Thumbnail of the single selected file, shown above the options in wide windows.
struct SelectionPreview: View {
    let item: QueueItem
    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 180)
            .accessibilityLabel(Text("Preview of \(item.name)"))
            Text(item.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("Press Space to open Quick Look")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // QuickLook decodes off the main thread and downsamples, so large HEICs stay cheap.
        .task(id: item.id) {
            thumbnail = nil
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: CGSize(width: 512, height: 512),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
        }
    }
}
