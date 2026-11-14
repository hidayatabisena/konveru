import SwiftUI

/// Icon and title in wide windows, icon only in the compact layout.
struct ToolbarLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        if showsTitle {
            Label(configuration).labelStyle(.titleAndIcon)
        } else {
            Label(configuration).labelStyle(.iconOnly)
        }
    }
}
