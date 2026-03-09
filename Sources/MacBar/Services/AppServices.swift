import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let localizationManager: LocalizationManager
    let store: MacBarStore
    let airDropService: AirDropService
    let ocrService: OCRService
    let launchAtLoginService: LaunchAtLoginService

    private init() {
        let sharedDefaults = MacBarStore.sharedDefaults()
        let localizationManager = LocalizationManager(defaults: sharedDefaults)
        let clipboardMonitor = ClipboardMonitor()
        let launchAtLoginService = LaunchAtLoginService()
        let fileAccessService = SecurityScopedFileAccessService()

        self.localizationManager = localizationManager
        self.store = MacBarStore(
            defaults: sharedDefaults,
            localizationManager: localizationManager,
            clipboardMonitor: clipboardMonitor,
            launchAtLoginService: launchAtLoginService,
            fileAccessService: fileAccessService
        )
        self.airDropService = AirDropService()
        self.ocrService = OCRService()
        self.launchAtLoginService = launchAtLoginService
    }
}
