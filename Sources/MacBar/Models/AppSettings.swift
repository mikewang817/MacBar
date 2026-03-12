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
    var launchesAtLogin: Bool = true
    var maxHistoryItems: Int = 150
    var maxStoredImageCacheSizeMB: Int = 300
    var ocrMode: ClipboardOCRMode = .automatic
    var automaticallyChecksForUpdates: Bool = true
    var hasSeenImageCopyModeTip: Bool = false

    private enum CodingKeys: String, CodingKey {
        case closesPanelAfterCopy
        case restoresPreviousAppAfterCopy
        case showsPreviewPane
        case launchesAtLogin
        case maxHistoryItems
        case maxStoredImageCacheSizeMB
        case ocrMode
        case automaticallyChecksForUpdates
        case hasSeenImageCopyModeTip
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        closesPanelAfterCopy = try container.decodeIfPresent(Bool.self, forKey: .closesPanelAfterCopy) ?? true
        restoresPreviousAppAfterCopy = try container.decodeIfPresent(Bool.self, forKey: .restoresPreviousAppAfterCopy) ?? true
        showsPreviewPane = try container.decodeIfPresent(Bool.self, forKey: .showsPreviewPane) ?? true
        launchesAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchesAtLogin) ?? true
        maxHistoryItems = try container.decodeIfPresent(Int.self, forKey: .maxHistoryItems) ?? 150
        maxStoredImageCacheSizeMB = try container.decodeIfPresent(Int.self, forKey: .maxStoredImageCacheSizeMB) ?? 300
        ocrMode = try container.decodeIfPresent(ClipboardOCRMode.self, forKey: .ocrMode) ?? .automatic
        automaticallyChecksForUpdates = try container.decodeIfPresent(Bool.self, forKey: .automaticallyChecksForUpdates) ?? true
        hasSeenImageCopyModeTip = try container.decodeIfPresent(Bool.self, forKey: .hasSeenImageCopyModeTip) ?? false
        normalize()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(closesPanelAfterCopy, forKey: .closesPanelAfterCopy)
        try container.encode(restoresPreviousAppAfterCopy, forKey: .restoresPreviousAppAfterCopy)
        try container.encode(showsPreviewPane, forKey: .showsPreviewPane)
        try container.encode(launchesAtLogin, forKey: .launchesAtLogin)
        try container.encode(maxHistoryItems, forKey: .maxHistoryItems)
        try container.encode(maxStoredImageCacheSizeMB, forKey: .maxStoredImageCacheSizeMB)
        try container.encode(ocrMode, forKey: .ocrMode)
        try container.encode(automaticallyChecksForUpdates, forKey: .automaticallyChecksForUpdates)
        try container.encode(hasSeenImageCopyModeTip, forKey: .hasSeenImageCopyModeTip)
    }

    mutating func normalize() {
        maxHistoryItems = max(
            Self.minimumHistoryItemLimit,
            min(Self.maximumHistoryItemLimit, maxHistoryItems)
        )
        maxStoredImageCacheSizeMB = max(
            Self.minimumImageStorageLimitMB,
            min(Self.maximumImageStorageLimitMB, maxStoredImageCacheSizeMB)
        )
        if !BuildInfo.supportsExternalUpdates {
            automaticallyChecksForUpdates = false
        }
    }
}
