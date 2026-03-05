import Foundation

struct AppConfiguration: Codable {
    let schemaVersion: Int
    let selectedLanguageCode: String
    let clipboardItems: [ClipboardItem]?
    let clipboardPinnedIDs: [String]?
    let clipboardMonitoringEnabled: Bool?

    static let currentSchemaVersion = 7

    init(
        schemaVersion: Int,
        selectedLanguageCode: String,
        clipboardItems: [ClipboardItem]? = nil,
        clipboardPinnedIDs: [String]? = nil,
        clipboardMonitoringEnabled: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.selectedLanguageCode = selectedLanguageCode
        self.clipboardItems = clipboardItems
        self.clipboardPinnedIDs = clipboardPinnedIDs
        self.clipboardMonitoringEnabled = clipboardMonitoringEnabled
    }
}

enum AppConfigurationError: Error {
    case cancelled
    case invalidPayload
    case encodeFailed
    case decodeFailed
    case writeFailed
    case readFailed
}
