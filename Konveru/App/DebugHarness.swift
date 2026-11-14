#if DEBUG
import AppKit
import SwiftUI

/// Debug-only launch arguments used to put the running app into each reference state
/// for screenshots and menu checks without UI scripting permissions.
///   -uiAdd <path>          add a file or folder at launch
///   -uiConvert YES         start converting once items are loaded
///   -uiCancelAfter <s>     cancel the running conversion after s seconds
///   -uiAppearance dark|light  force an appearance
///   -uiMenu <title>        choose a menu item by title
///   -uiDump <path>         write the menu bar (titles, shortcuts, enabled state) to path
enum DebugHarness {
    static var defaults: UserDefaults { .standard }

    static func run(_ queue: ConversionQueue) async {
        if let appearance = defaults.string(forKey: "uiAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        guard let path = defaults.string(forKey: "uiAdd") else { return }
        queue.add([URL(filePath: path)])
        for _ in 0..<100 where queue.items.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .milliseconds(500))
        if defaults.bool(forKey: "uiConvert") {
            queue.convert()
            let cancelAfter = defaults.double(forKey: "uiCancelAfter")
            if cancelAfter > 0 {
                try? await Task.sleep(for: .seconds(cancelAfter))
                queue.cancel()
            }
        }
        if let title = defaults.string(forKey: "uiMenu") {
            try? await Task.sleep(for: .seconds(2))
            for menu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
                menu.delegate?.menuNeedsUpdate?(menu)
                menu.update()
                if let index = menu.items.firstIndex(where: { $0.title == title }) {
                    menu.performActionForItem(at: index)
                }
            }
        }
        if let dump = defaults.string(forKey: "uiDump") {
            try? await Task.sleep(for: .seconds(2))
            try? report().write(toFile: dump, atomically: true, encoding: .utf8)
        }
    }

    static func report() -> String {
        var lines = ["# Menus (app active: \(NSApp.isActive), key window: \(NSApp.keyWindow != nil))"]
        for item in NSApp.mainMenu?.items ?? [] {
            lines.append(item.title)
            if let menu = item.submenu { menu.delegate?.menuNeedsUpdate?(menu) }
            item.submenu?.update()
            for sub in item.submenu?.items ?? [] where !sub.isSeparatorItem {
                var key = sub.keyEquivalent
                if key == "\r" { key = "↩" } else if key == "\u{8}" || key == "\u{7f}" { key = "⌫" }
                let mods = sub.keyEquivalentModifierMask
                let shortcut = key.isEmpty ? "" : (mods.contains(.option) ? "⌥" : "") + (mods.contains(.shift) ? "⇧" : "") + (mods.contains(.command) ? "⌘" : "") + key.uppercased()
                lines.append("  \(sub.title)\t\(shortcut)\(sub.isEnabled ? "" : "\t(disabled)")")
            }
        }
        return lines.joined(separator: "\n")
    }
}
#endif
