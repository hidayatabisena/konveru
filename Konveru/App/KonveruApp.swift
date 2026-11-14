import SwiftUI

@main
struct KonveruApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: windowSize.width, height: windowSize.height)
        .commands { KonveruCommands() }
    }

    private var windowSize: CGSize {
        #if DEBUG
        let defaults = UserDefaults.standard
        if defaults.double(forKey: "uiWidth") > 0 {
            return CGSize(width: defaults.double(forKey: "uiWidth"), height: defaults.double(forKey: "uiHeight"))
        }
        #endif
        return CGSize(width: 900, height: 620)
    }
}
