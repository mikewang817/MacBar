import SwiftUI

@main
struct MacBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var hiddenMenu: Bool = false
    @StateObject private var localizationManager = AppServices.shared.localizationManager

    var body: some Scene {
        MenuBarExtra("", isInserted: $hiddenMenu) {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(localizationManager.localized("ui.settings.button.open")) {
                    appDelegate.showSettingsWindow(nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
