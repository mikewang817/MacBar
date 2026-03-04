import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let localizationManager: LocalizationManager
    let store: MacBarStore
    let navigator: SettingsNavigator
    let todoAIService: TodoIntentAIService

    private init() {
        let localizationManager = LocalizationManager()
        let inputDeviceMonitor = InputDeviceMonitor()
        let clipboardMonitor = ClipboardMonitor()

        self.localizationManager = localizationManager
        self.store = MacBarStore(
            inputDeviceMonitor: inputDeviceMonitor,
            localizationManager: localizationManager,
            clipboardMonitor: clipboardMonitor
        )
        self.navigator = SettingsNavigator(
            inputDeviceDetector: inputDeviceMonitor,
            localizationManager: localizationManager
        )
        self.todoAIService = LocalMLXTodoIntentService()
    }
}
