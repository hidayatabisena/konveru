import SwiftUI

/// Menu bar twins for every toolbar command.
struct KonveruCommands: Commands {
    @FocusedValue(\.conversionQueue) private var queue
    @AppStorage("showsOptions") private var showsOptions = true

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Files…") { queue?.beginImport(.files) }
                .keyboardShortcut("o")
                .disabled(queue == nil)
            Button("Add Folder…") { queue?.beginImport(.folder) }
                .keyboardShortcut("o", modifiers: [.command, .shift])
                .disabled(queue == nil)
            Divider()
            Button("Convert") { queue?.convert() }
                .keyboardShortcut(.return)
                .disabled(!(queue?.canConvert ?? false))
            Button("Reveal Results") { queue?.revealResults() }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!(queue?.canReveal ?? false))
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Remove from Queue") { queue?.removeSelected() }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(!(queue?.canRemoveSelection ?? false))
            Button("Clear Completed") { queue?.clearCompleted() }
                .disabled(!(queue?.hasCompleted ?? false))
        }
        CommandGroup(replacing: .sidebar) {}
        CommandGroup(before: .toolbar) {
            Button(showsOptions ? "Hide Options" : "Show Options") { showsOptions.toggle() }
                .keyboardShortcut("o", modifiers: [.command, .option])
            Divider()
        }
    }
}
