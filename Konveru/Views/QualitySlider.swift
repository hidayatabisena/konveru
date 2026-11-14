import SwiftUI

struct QualitySlider: View {
    @Binding var quality: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Quality")
                Spacer()
                Text(quality, format: .number.precision(.fractionLength(0)))
                    .monospacedDigit()
            }
            .accessibilityHidden(true)
            Slider(value: $quality, in: 0...100, step: 1) {
                Text("Quality")
            }
            .labelsHidden()
            .accessibilityValue(Text(quality, format: .number.precision(.fractionLength(0))))
            HStack {
                Text("Smaller file")
                Spacer()
                Text("Higher quality")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }
}
