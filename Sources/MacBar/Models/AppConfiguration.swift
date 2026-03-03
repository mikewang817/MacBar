import Foundation

struct AppConfiguration: Codable {
    let schemaVersion: Int
    let favoriteIDs: [String]
    let selectedLanguageCode: String
    let clipboardItems: [ClipboardItem]?
    let clipboardPinnedIDs: [String]?
    let clipboardMonitoringEnabled: Bool?
    let todoItems: [TodoItem]?
    let todoPinnedIDs: [String]?

    static let currentSchemaVersion = 3

    init(
        schemaVersion: Int,
        favoriteIDs: [String],
        selectedLanguageCode: String,
        clipboardItems: [ClipboardItem]? = nil,
        clipboardPinnedIDs: [String]? = nil,
        clipboardMonitoringEnabled: Bool? = nil,
        todoItems: [TodoItem]? = nil,
        todoPinnedIDs: [String]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.favoriteIDs = favoriteIDs
        self.selectedLanguageCode = selectedLanguageCode
        self.clipboardItems = clipboardItems
        self.clipboardPinnedIDs = clipboardPinnedIDs
        self.clipboardMonitoringEnabled = clipboardMonitoringEnabled
        self.todoItems = todoItems
        self.todoPinnedIDs = todoPinnedIDs
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
