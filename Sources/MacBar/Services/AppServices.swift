import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let localizationManager: LocalizationManager
    let store: MacBarStore
    let airDropService: AirDropService
    let ocrService: OCRService

    private init() {
        let localizationManager = LocalizationManager()
        let clipboardMonitor = ClipboardMonitor()

        self.localizationManager = localizationManager
        self.store = MacBarStore(
            localizationManager: localizationManager,
            clipboardMonitor: clipboardMonitor
        )
        self.airDropService = AirDropService()
        self.ocrService = OCRService()
    }
}
