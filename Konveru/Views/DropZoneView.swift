import SwiftUI

struct DropZoneView: View {
    let queue: ConversionQueue
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 4) {
                Text("Drop files to convert")
                    .font(.title2.bold())
                Text("Or add files and folders from your Mac.")
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Button("Add Files…") { queue.beginImport(.files) }
                    .buttonStyle(.borderedProminent)
                Button("Add Folder…") { queue.beginImport(.folder) }
            }
            .controlSize(.large)

            Text("Accepts JPEG, PNG and HEIC · Converts to WebP")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.5),
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 4])
                )
        }
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drop target. Drop JPEG, PNG or HEIC files or folders here.")
    }
}
