import Foundation

enum ClipboardOCRMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case selectedOnly
    case disabled

    var id: String { rawValue }
}

struct AppSettings: Codable, Equatable {
    static let minimumHistoryItemLimit = 25
    static let maximumHistoryItemLimit = 500
    static let historyItemStep = 25

    static let minimumImageStorageLimitMB = 50
    static let maximumImageStorageLimitMB = 2_048
    static let imageStorageStepMB = 50

    var closesPanelAfterCopy: Bool = true
    var restoresPreviousAppAfterCopy: Bool = true
    var showsPreviewPane: Bool = true
    var maxHistoryItems: Int = 150
    var maxStoredImageCacheSizeMB: Int = 300
    var ocrMode: ClipboardOCRMode = .automatic
    var automaticallyChecksForUpdates: Bool = true

    mutating func normalize() {
        maxHistoryItems = max(
            Self.minimumHistoryItemLimit,
            min(Self.maximumHistoryItemLimit, maxHistoryItems)
        )
        maxStoredImageCacheSizeMB = max(
            Self.minimumImageStorageLimitMB,
            min(Self.maximumImageStorageLimitMB, maxStoredImageCacheSizeMB)
        )
    }
}
