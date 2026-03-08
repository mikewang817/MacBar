import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let localizationManager: LocalizationManager
    let store: MacBarStore
    let airDropService: AirDropService
    let ocrService: OCRService

    private init() {
        let sharedDefaults = MacBarStore.sharedDefaults()
        let localizationManager = LocalizationManager(defaults: sharedDefaults)
        let clipboardMonitor = ClipboardMonitor()

        self.localizationManager = localizationManager
        self.store = MacBarStore(
            defaults: sharedDefaults,
            localizationManager: localizationManager,
            clipboardMonitor: clipboardMonitor
        )
        self.airDropService = AirDropService()
        self.ocrService = OCRService()
    }
}
