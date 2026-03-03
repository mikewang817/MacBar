import SwiftUI

@main
struct MacBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = MacBarStore()
    private let navigator = SettingsNavigator()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(store: store, navigator: navigator)
        } label: {
            Label(BuildInfo.appName, systemImage: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)
    }
}
