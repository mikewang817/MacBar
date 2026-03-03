import SwiftUI

@main
struct MacBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var localizationManager: LocalizationManager
    @StateObject private var store: MacBarStore
    private let navigator: SettingsNavigator

    init() {
        let localizationManager = LocalizationManager()
        let inputDeviceMonitor = InputDeviceMonitor()

        _localizationManager = StateObject(wrappedValue: localizationManager)
        _store = StateObject(
            wrappedValue: MacBarStore(
                inputDeviceMonitor: inputDeviceMonitor,
                localizationManager: localizationManager
            )
        )
        navigator = SettingsNavigator(
            inputDeviceDetector: inputDeviceMonitor,
            localizationManager: localizationManager
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView(
                store: store,
                localizationManager: localizationManager,
                navigator: navigator
            )
        } label: {
            Label(BuildInfo.appName, systemImage: "slider.horizontal.3")
        }
        .menuBarExtraStyle(.window)
    }
}
