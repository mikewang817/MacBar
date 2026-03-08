import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct StoreFeedback {
    let title: String
    let message: String
}

@MainActor
final class MacBarStore: ObservableObject {
    @Published var activePanel: AppPanel = .clipboard
    @Published private(set) var settings: AppSettings
    @Published var clipboardSearchText: String = "" {
        didSet { rebuildDerivedClipboardCollections() }
    }
    @Published private(set) var clipboardHistory: [ClipboardItem] {
        didSet {
            rebuildClipboardMetadataCache()
            rebuildFileAvailabilityCache()
            rebuildDerivedClipboardCollections()
        }
    }
    @Published private(set) var pinnedClipboardItemIDs: Set<UUID> {
        didSet { rebuildDerivedClipboardCollections() }
    }
    @Published private(set) var isClipboardMonitoringEnabled: Bool
    @Published private(set) var clipboardOCRCache: [UUID: String] = [:] {
        didSet { rebuildDerivedClipboardCollections() }
    }
    @Published private(set) var pendingUpdateRelease: GitHubRelease? = nil
    @Published private(set) var isUpdateInstalling: Bool = false
    @Published private(set) var isCheckingForUpdates: Bool = false

    private let defaults: UserDefaults
    private let localizationManager: LocalizationManager
    private let clipboardMonitor: ClipboardMonitor
    private let clipboardImageStore: ClipboardImageStore
    private let updateService = UpdateService()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingPersistenceTask: Task<Void, Never>?
    private var panelOpenCountSinceLastUpdateCheck: Int
    private var imageDataCache: [String: Data] = [:]
    private var imagePreviewCache: [String: NSImage] = [:]
    private var fileImageDataCache: [String: Data] = [:]
    private var fileImagePreviewCache: [String: NSImage] = [:]
    private var metadataByItemID: [UUID: ClipboardItemMetadata] = [:]
    private var fileAvailabilityByItemID: [UUID: ClipboardFileAvailability] = [:]
    private var lastFileAvailabilityRefreshAt: Date?
    private var filteredClipboardItemsCache: [ClipboardItem] = []
    private var pinnedClipboardItemsCache: [ClipboardItem] = []
    private var recentClipboardItemsCache: [ClipboardItem] = []
    private var localizedFileSearchLabel: String = ""
    private var localizedImageSearchLabel: String = ""
    private let relativeDateTimeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private enum Keys {
        static let appSettingsData = "macbar.appSettingsData"
        static let clipboardHistoryData = "macbar.clipboardHistoryData"
        static let pinnedClipboardIDs = "macbar.pinnedClipboardIDs"
        static let clipboardMonitoringEnabled = "macbar.clipboardMonitoringEnabled"
        static let updateCheckPanelOpenCount = "macbar.updateCheckPanelOpenCount"
    }

    private static let updateCheckPanelOpenThreshold = 20
    private static let fileAvailabilityRefreshInterval: TimeInterval = 1.0

    private struct ClipboardItemMetadata {
        let fileURLs: [URL]
        let firstFileURL: URL?
        let imageFileURLs: [URL]
        let firstImageFileURL: URL?
        let fileHelpText: String
        let previewTitle: String
        let previewSubtitle: String
        let searchableText: String
    }

    private struct ClipboardFileAvailability: Equatable {
        let availableFileURLs: [URL]
        let missingFileURLs: [URL]
        let availableImageFileURLs: [URL]
    }

    static func sharedDefaults() -> UserDefaults {
        let sharedDefaults = UserDefaults(suiteName: BuildInfo.preferencesSuiteName) ?? .standard
        migrateLegacyDefaultsIfNeeded(into: sharedDefaults)
        return sharedDefaults
    }

    init(
        defaults: UserDefaults = .standard,
        localizationManager: LocalizationManager = LocalizationManager(),
        clipboardMonitor: ClipboardMonitor = ClipboardMonitor(),
        clipboardImageStore: ClipboardImageStore = ClipboardImageStore()
    ) {
        self.defaults = defaults
        self.localizationManager = localizationManager
        self.clipboardMonitor = clipboardMonitor
        self.clipboardImageStore = clipboardImageStore
        self.settings = Self.loadAppSettings(defaults: defaults)
        self.clipboardHistory = Self.loadClipboardHistory(defaults: defaults)
        self.pinnedClipboardItemIDs = Self.loadPinnedClipboardIDs(defaults: defaults)
        self.isClipboardMonitoringEnabled = defaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool ?? true
        self.panelOpenCountSinceLastUpdateCheck = defaults.integer(forKey: Keys.updateCheckPanelOpenCount)

        normalizeClipboardState()
        migrateLegacyClipboardImagesIfNeeded()
        enforceRetentionPolicies(persistChanges: true)
        purgeUnusedStoredImages()
        rebuildClipboardMetadataCache()
        rebuildFileAvailabilityCache()
        refreshLocalizedSearchLabels()
        rebuildDerivedClipboardCollections()
        configureClipboardMonitoring()

        localizationManager.$effectiveLanguageIdentifier
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshLocalizedSearchLabels()
                self?.rebuildDerivedClipboardCollections()
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        clipboardMonitor.$latestCapturedItem
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] capturedItem in
                self?.captureClipboardItem(capturedItem)
            }
            .store(in: &cancellables)
    }

    var isClipboardSearching: Bool {
        !clipboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pinnedClipboardItems: [ClipboardItem] {
        pinnedClipboardItemsCache
    }

    var recentClipboardItems: [ClipboardItem] {
        recentClipboardItemsCache
    }

    var visibleClipboardItems: [ClipboardItem] {
        filteredClipboardItemsCache
    }

    var closesPanelAfterCopy: Bool {
        settings.closesPanelAfterCopy
    }

    var restoresPreviousAppAfterCopy: Bool {
        settings.restoresPreviousAppAfterCopy
    }

    var showsPreviewPane: Bool {
        settings.showsPreviewPane
    }

    var ocrMode: ClipboardOCRMode {
        settings.ocrMode
    }

    var automaticallyChecksForUpdates: Bool {
        settings.automaticallyChecksForUpdates
    }

    func localized(_ key: String) -> String {
        localizationManager.localized(key)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localizationManager.localized(key, arguments: arguments)
    }

    func setClosesPanelAfterCopy(_ isEnabled: Bool) {
        updateSettings {
            $0.closesPanelAfterCopy = isEnabled
        }
    }

    func setRestoresPreviousAppAfterCopy(_ isEnabled: Bool) {
        updateSettings {
            $0.restoresPreviousAppAfterCopy = isEnabled
        }
    }

    func setShowsPreviewPane(_ isEnabled: Bool) {
        updateSettings {
            $0.showsPreviewPane = isEnabled
        }
    }

    func setMaxHistoryItems(_ value: Int) {
        updateSettings {
            $0.maxHistoryItems = value
        }
        enforceRetentionPolicies(persistChanges: true)
    }

    func setMaxStoredImageCacheSizeMB(_ value: Int) {
        updateSettings {
            $0.maxStoredImageCacheSizeMB = value
        }
        enforceRetentionPolicies(persistChanges: true)
    }

    func setOCRMode(_ mode: ClipboardOCRMode) {
        updateSettings {
            $0.ocrMode = mode
        }
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updateSettings {
            $0.automaticallyChecksForUpdates = isEnabled
        }

        if !isEnabled {
            resetUpdateCheckPanelOpenCount()
        }
    }

    func clipboardCopyShortcutHint() -> String {
        switch shortcutHintStyle {
        case .chineseSimplified, .chineseTraditional:
            return "Enter：\(localized("ui.clipboard.button.copy"))"
        case .defaultStyle:
            return "Enter → \(localized("ui.clipboard.button.copy"))"
        }
    }

    func clipboardDeleteShortcutHint() -> String {
        let deleteAction = localized("ui.clipboard.help.delete")

        switch shortcutHintStyle {
        case .chineseSimplified:
            return "CMD + 删除键：\(deleteAction)"
        case .chineseTraditional:
            return "CMD + 刪除鍵：\(deleteAction)"
        case .defaultStyle:
            return "⌘Delete → \(deleteAction)"
        }
    }

    func registerPanelOpenForUpdateCheck() async {
        guard automaticallyChecksForUpdates else {
            return
        }

        panelOpenCountSinceLastUpdateCheck += 1
        defaults.set(panelOpenCountSinceLastUpdateCheck, forKey: Keys.updateCheckPanelOpenCount)

        guard panelOpenCountSinceLastUpdateCheck >= Self.updateCheckPanelOpenThreshold else {
            return
        }

        await checkForUpdates(force: true)
    }

    func isClipboardItemPinned(_ itemID: UUID) -> Bool {
        pinnedClipboardItemIDs.contains(itemID)
    }

    func toggleClipboardItemPinned(_ itemID: UUID) {
        if pinnedClipboardItemIDs.contains(itemID) {
            pinnedClipboardItemIDs.remove(itemID)
        } else {
            pinnedClipboardItemIDs.insert(itemID)
        }

        normalizeClipboardState()
        enforceRetentionPolicies(persistChanges: false)
        schedulePersistence()
    }

    func copyClipboardItem(_ itemID: UUID, persistHistoryImmediately: Bool = true) -> StoreFeedback? {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let item = clipboardHistory[index]
        if clipboardIsFileItem(item) {
            refreshClipboardFileAvailability(force: true)
        }
        let fileURLs = clipboardAvailableFileURLs(for: item)
        if !fileURLs.isEmpty {
            clipboardMonitor.copyFilesToPasteboard(fileURLs)
        } else if clipboardIsFileItem(item) {
            return nil
        } else if let imageData = clipboardImageData(for: item) {
            clipboardMonitor.copyImageToPasteboard(imageData)
        } else {
            clipboardMonitor.copyTextToPasteboard(item.content)
        }

        clipboardHistory.remove(at: index)
        clipboardHistory.insert(
            ClipboardItem(
                id: item.id,
                content: item.content,
                imageTIFFData: item.imageTIFFData,
                imageStorageKey: item.imageStorageKey,
                imageFingerprint: item.imageFingerprint,
                fileURLStrings: item.fileURLStrings,
                capturedAt: Date()
            ),
            at: 0
        )

        if persistHistoryImmediately {
            schedulePersistence()
        }
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.copied"
        )
    }

    func setClipboardOCRText(for id: UUID, text: String) {
        guard clipboardHistory.contains(where: { $0.id == id }) else {
            return
        }
        clipboardOCRCache[id] = text
    }

    func copyTextToClipboard(_ text: String) -> StoreFeedback {
        clipboardMonitor.copyTextToPasteboard(text)
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.copied"
        )
    }

    func scheduleClipboardPersistence() {
        schedulePersistence()
    }

    func flushPendingPersistence() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        persistClipboardState(
            history: clipboardHistory,
            pinnedIDs: serializedPinnedClipboardIDs()
        )
    }

    func deleteClipboardItem(_ itemID: UUID) {
        let removedItems = clipboardHistory.filter { $0.id == itemID }
        clipboardHistory.removeAll { $0.id == itemID }
        pinnedClipboardItemIDs.remove(itemID)
        clipboardOCRCache.removeValue(forKey: itemID)
        removeStoredImages(for: removedItems)
        schedulePersistence()
    }

    func clearUnpinnedClipboardItems() -> StoreFeedback? {
        let originalCount = clipboardHistory.count
        let removedItems = clipboardHistory.filter { !pinnedClipboardItemIDs.contains($0.id) }
        let removedIDs = Set(removedItems.map(\.id))
        clipboardHistory.removeAll { !pinnedClipboardItemIDs.contains($0.id) }

        guard clipboardHistory.count != originalCount else {
            return nil
        }

        removedIDs.forEach { clipboardOCRCache.removeValue(forKey: $0) }
        removeStoredImages(for: removedItems)
        schedulePersistence()
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.clearedUnpinned"
        )
    }

    func clearClipboardHistory() -> StoreFeedback? {
        guard !clipboardHistory.isEmpty else {
            return nil
        }

        let removedItems = clipboardHistory
        clipboardHistory.removeAll()
        pinnedClipboardItemIDs.removeAll()
        clipboardOCRCache.removeAll()
        removeStoredImages(for: removedItems)
        schedulePersistence()

        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.clearedAll"
        )
    }

    func toggleClipboardMonitoring() -> StoreFeedback {
        setClipboardMonitoringEnabled(!isClipboardMonitoringEnabled)
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: isClipboardMonitoringEnabled
                ? "feedback.clipboard.monitoringResumed"
                : "feedback.clipboard.monitoringPaused"
        )
    }

    func setClipboardMonitoringEnabled(_ isEnabled: Bool) {
        guard isClipboardMonitoringEnabled != isEnabled else {
            return
        }

        isClipboardMonitoringEnabled = isEnabled
        defaults.set(isEnabled, forKey: Keys.clipboardMonitoringEnabled)
        configureClipboardMonitoring()
    }

    func clipboardCapturedAtLabel(for item: ClipboardItem) -> String {
        relativeDateTimeFormatter.locale = Locale(identifier: localizationManager.effectiveLanguageIdentifier)
        return relativeDateTimeFormatter.localizedString(for: item.capturedAt, relativeTo: Date())
    }

    func clipboardImageData(for item: ClipboardItem) -> Data? {
        guard clipboardIsImageDataItem(item) else {
            return nil
        }

        if let cacheKey = imageCacheKey(for: item), let cachedData = imageDataCache[cacheKey] {
            return cachedData
        }

        let resolvedData: Data?
        if let storageKey = item.imageStorageKey {
            resolvedData = clipboardImageStore.loadImageData(for: storageKey)
        } else {
            resolvedData = item.imageTIFFData
        }

        guard let resolvedData else {
            return nil
        }

        cacheClipboardImageData(resolvedData, for: item)
        return resolvedData
    }

    func clipboardImage(for item: ClipboardItem) -> NSImage? {
        guard clipboardIsImageDataItem(item) else {
            return nil
        }

        if let cacheKey = imageCacheKey(for: item), let cachedImage = imagePreviewCache[cacheKey] {
            return cachedImage
        }

        guard let imageData = clipboardImageData(for: item), let image = NSImage(data: imageData) else {
            return nil
        }

        if let cacheKey = imageCacheKey(for: item) {
            imagePreviewCache[cacheKey] = image
        }
        return image
    }

    func clipboardHasPreviewImage(for item: ClipboardItem) -> Bool {
        if clipboardIsImageDataItem(item) {
            return true
        }

        return !clipboardImageFileURLs(for: item).isEmpty
    }

    func clipboardIsFileItem(_ item: ClipboardItem) -> Bool {
        !clipboardFileURLs(for: item).isEmpty
    }

    func clipboardPreviewImage(for item: ClipboardItem) -> NSImage? {
        if clipboardIsImageDataItem(item) {
            return clipboardImage(for: item)
        }

        guard let imageFileURL = clipboardImageFileURLs(for: item).first else {
            return nil
        }

        return previewImage(forFileURL: imageFileURL)
    }

    func clipboardImageFileURLs(for item: ClipboardItem) -> [URL] {
        fileAvailability(for: item).availableImageFileURLs
    }

    func clipboardOCRSourceCount(for item: ClipboardItem) -> Int {
        if clipboardIsImageDataItem(item) {
            return 1
        }

        return clipboardImageFileURLs(for: item).count
    }

    func clipboardOCRFileURL(for item: ClipboardItem, at index: Int) -> URL? {
        let imageFileURLs = clipboardImageFileURLs(for: item)
        guard imageFileURLs.indices.contains(index) else {
            return nil
        }

        return imageFileURLs[index]
    }

    func clipboardFileURLs(for item: ClipboardItem) -> [URL] {
        metadataByItemID[item.id]?.fileURLs ?? item.fileURLs
    }

    func clipboardAvailableFileURLs(for item: ClipboardItem) -> [URL] {
        fileAvailability(for: item).availableFileURLs
    }

    func clipboardMissingFileURLs(for item: ClipboardItem) -> [URL] {
        fileAvailability(for: item).missingFileURLs
    }

    func clipboardHasMissingFiles(_ item: ClipboardItem) -> Bool {
        !clipboardMissingFileURLs(for: item).isEmpty
    }

    func clipboardIsFileItemUnavailable(_ item: ClipboardItem) -> Bool {
        clipboardIsFileItem(item) && clipboardAvailableFileURLs(for: item).isEmpty
    }

    func clipboardCanCopy(_ item: ClipboardItem) -> Bool {
        if clipboardIsFileItem(item) {
            return !clipboardAvailableFileURLs(for: item).isEmpty
        }

        if clipboardIsImageDataItem(item) {
            return clipboardImageData(for: item) != nil
        }

        return true
    }

    func refreshClipboardFileAvailability(force: Bool = false) {
        let now = Date()
        if !force,
           let lastFileAvailabilityRefreshAt,
           now.timeIntervalSince(lastFileAvailabilityRefreshAt) < Self.fileAvailabilityRefreshInterval {
            return
        }

        let updatedAvailability = makeFileAvailabilityCache()
        lastFileAvailabilityRefreshAt = now

        guard updatedAvailability != fileAvailabilityByItemID else {
            return
        }

        fileAvailabilityByItemID = updatedAvailability
        objectWillChange.send()
    }

    func clipboardFirstFileURL(for item: ClipboardItem) -> URL? {
        metadataByItemID[item.id]?.firstFileURL ?? clipboardFileURLs(for: item).first
    }

    func clipboardFileHelpText(for item: ClipboardItem) -> String {
        metadataByItemID[item.id]?.fileHelpText ?? ""
    }

    func clipboardDisplayTitle(for item: ClipboardItem) -> String {
        if clipboardIsImageDataItem(item) {
            return localized("ui.clipboard.item.image")
        }

        let previewTitle = metadataByItemID[item.id]?.previewTitle ?? item.previewTitle
        return previewTitle.isEmpty ? localized("ui.clipboard.item.empty") : previewTitle
    }

    func clipboardDisplaySubtitle(for item: ClipboardItem) -> String {
        let previewSubtitle = metadataByItemID[item.id]?.previewSubtitle ?? item.previewSubtitle
        return previewSubtitle.isEmpty ? clipboardCapturedAtLabel(for: item) : previewSubtitle
    }

    private func configureClipboardMonitoring() {
        if isClipboardMonitoringEnabled {
            clipboardMonitor.startMonitoring()
        } else {
            clipboardMonitor.stopMonitoring()
        }
    }

    private func captureClipboardItem(_ capturedItem: ClipboardCapture) {
        switch capturedItem {
        case let .text(rawText):
            captureClipboardText(rawText)
        case let .image(rawData):
            captureClipboardImage(rawData)
        case let .files(urls):
            captureClipboardFiles(urls)
        }
    }

    private func captureClipboardText(_ rawText: String) {
        guard isClipboardMonitoringEnabled else {
            return
        }

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        let captured = trimmed
        if clipboardHistory.first?.content == captured {
            return
        }

        if let existingIndex = clipboardHistory.firstIndex(where: { $0.content == captured }) {
            let existing = clipboardHistory.remove(at: existingIndex)
            clipboardHistory.insert(
                ClipboardItem(id: existing.id, content: captured, capturedAt: Date()),
                at: 0
            )
        } else {
            clipboardHistory.insert(
                ClipboardItem(content: captured, capturedAt: Date()),
                at: 0
            )
        }

        normalizeClipboardState()
        enforceRetentionPolicies(persistChanges: false)
        schedulePersistence()
    }

    private func captureClipboardImage(_ rawData: Data) {
        guard isClipboardMonitoringEnabled else {
            return
        }

        guard !rawData.isEmpty else {
            return
        }

        let fingerprint = clipboardImageStore.imageFingerprint(for: rawData)

        if clipboardHistory.first?.imageFingerprint == fingerprint {
            return
        }

        if let existingIndex = clipboardHistory.firstIndex(where: { $0.imageFingerprint == fingerprint }) {
            let existing = clipboardHistory.remove(at: existingIndex)
            clipboardHistory.insert(
                storedImageClipboardItem(
                    from: existing,
                    rawData: rawData,
                    fingerprint: fingerprint,
                    capturedAt: Date()
                ),
                at: 0
            )
        } else {
            let itemID = UUID()
            let newItem = storedImageClipboardItem(
                from: ClipboardItem(id: itemID, content: "", capturedAt: Date()),
                rawData: rawData,
                fingerprint: fingerprint,
                capturedAt: Date()
            )
            clipboardHistory.insert(newItem, at: 0)
        }

        normalizeClipboardState()
        enforceRetentionPolicies(persistChanges: false)
        schedulePersistence()
    }

    private func captureClipboardFiles(_ urls: [URL]) {
        guard isClipboardMonitoringEnabled else {
            return
        }

        guard !urls.isEmpty else {
            return
        }

        let urlStrings = urls.map(\.absoluteString)

        if clipboardHistory.first?.fileURLStrings == urlStrings {
            return
        }

        if let existingIndex = clipboardHistory.firstIndex(where: { $0.fileURLStrings == urlStrings }) {
            let existing = clipboardHistory.remove(at: existingIndex)
            clipboardHistory.insert(
                ClipboardItem(
                    id: existing.id,
                    content: "",
                    fileURLStrings: urlStrings,
                    capturedAt: Date()
                ),
                at: 0
            )
        } else {
            clipboardHistory.insert(
                ClipboardItem(content: "", fileURLStrings: urlStrings, capturedAt: Date()),
                at: 0
            )
        }

        normalizeClipboardState()
        enforceRetentionPolicies(persistChanges: false)
        schedulePersistence()
    }

    private func normalizeClipboardState() {
        let existingIDs = Set(clipboardHistory.map(\.id))
        pinnedClipboardItemIDs = pinnedClipboardItemIDs.intersection(existingIDs)

        var normalized: [ClipboardItem] = []
        var seenIDs: Set<UUID> = []

        for item in clipboardHistory {
            guard !seenIDs.contains(item.id) else {
                continue
            }
            seenIDs.insert(item.id)
            normalized.append(item)
        }

        clipboardHistory = normalized
    }

    private func schedulePersistence() {
        pendingPersistenceTask?.cancel()

        let historySnapshot = clipboardHistory
        let pinnedSnapshot = serializedPinnedClipboardIDs()

        pendingPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self else {
                return
            }

            self.persistClipboardState(
                history: historySnapshot,
                pinnedIDs: pinnedSnapshot
            )
            self.pendingPersistenceTask = nil
        }
    }

    private func persistSettings() {
        var normalizedSettings = settings
        normalizedSettings.normalize()

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(normalizedSettings) {
            defaults.set(data, forKey: Keys.appSettingsData)
        }
    }

    private func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        var updatedSettings = settings
        mutate(&updatedSettings)
        updatedSettings.normalize()

        guard updatedSettings != settings else {
            return
        }

        settings = updatedSettings
        persistSettings()
    }

    private func serializedPinnedClipboardIDs() -> [String] {
        Array(pinnedClipboardItemIDs).map(\.uuidString).sorted()
    }

    private func persistClipboardState(
        history: [ClipboardItem],
        pinnedIDs: [String]
    ) {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Keys.clipboardHistoryData)
        }
        defaults.set(pinnedIDs, forKey: Keys.pinnedClipboardIDs)
    }

    private func enforceRetentionPolicies(persistChanges: Bool) {
        var removedItems: [ClipboardItem] = []

        removedItems += trimHistoryToMaximumItemLimit()
        removedItems += trimStoredImageHistoryToCacheLimit()

        guard !removedItems.isEmpty else {
            return
        }

        let removedIDs = Set(removedItems.map(\.id))
        removedIDs.forEach { clipboardOCRCache.removeValue(forKey: $0) }
        removeStoredImages(for: removedItems)

        if persistChanges {
            pendingPersistenceTask?.cancel()
            pendingPersistenceTask = nil
            persistClipboardState(
                history: clipboardHistory,
                pinnedIDs: serializedPinnedClipboardIDs()
            )
        }
    }

    private func trimHistoryToMaximumItemLimit() -> [ClipboardItem] {
        let pinnedIDs = pinnedClipboardItemIDs
        let pinnedCount = clipboardHistory.reduce(into: 0) { count, item in
            if pinnedIDs.contains(item.id) {
                count += 1
            }
        }
        let allowedUnpinnedCount = max(0, settings.maxHistoryItems - pinnedCount)

        var keptItems: [ClipboardItem] = []
        var removedItems: [ClipboardItem] = []
        var keptUnpinnedCount = 0

        for item in clipboardHistory {
            if pinnedIDs.contains(item.id) {
                keptItems.append(item)
                continue
            }

            if keptUnpinnedCount < allowedUnpinnedCount {
                keptItems.append(item)
                keptUnpinnedCount += 1
            } else {
                removedItems.append(item)
            }
        }

        guard !removedItems.isEmpty else {
            return []
        }

        clipboardHistory = keptItems
        return removedItems
    }

    private func trimStoredImageHistoryToCacheLimit() -> [ClipboardItem] {
        let limitBytes = Int64(settings.maxStoredImageCacheSizeMB) * 1_048_576
        guard limitBytes >= 0 else {
            return []
        }

        let storedImageItems = clipboardHistory.filter {
            clipboardIsImageDataItem($0) && $0.imageStorageKey != nil
        }
        var totalBytes = storedImageItems.reduce(into: Int64(0)) { total, item in
            guard let storageKey = item.imageStorageKey else {
                return
            }
            total += clipboardImageStore.fileSize(for: storageKey)
        }

        guard totalBytes > limitBytes else {
            return []
        }

        let pinnedIDs = pinnedClipboardItemIDs
        var removableIDs: Set<UUID> = []
        var removedItems: [ClipboardItem] = []

        for item in clipboardHistory.reversed() {
            guard totalBytes > limitBytes else {
                break
            }
            guard
                !pinnedIDs.contains(item.id),
                clipboardIsImageDataItem(item),
                let storageKey = item.imageStorageKey
            else {
                continue
            }

            totalBytes -= clipboardImageStore.fileSize(for: storageKey)
            removableIDs.insert(item.id)
            removedItems.append(item)
        }

        guard !removedItems.isEmpty else {
            return []
        }

        clipboardHistory.removeAll { removableIDs.contains($0.id) }
        return removedItems
    }

    private func migrateLegacyClipboardImagesIfNeeded() {
        var migratedHistory = clipboardHistory
        var didChange = false

        for index in migratedHistory.indices {
            let item = migratedHistory[index]

            if let legacyImageData = item.imageTIFFData {
                let fingerprint = item.imageFingerprint ?? clipboardImageStore.imageFingerprint(for: legacyImageData)
                let migratedItem = storedImageClipboardItem(
                    from: item,
                    rawData: legacyImageData,
                    fingerprint: fingerprint,
                    capturedAt: item.capturedAt
                )

                if migratedItem != item {
                    migratedHistory[index] = migratedItem
                    didChange = true
                }
                continue
            }

            guard
                item.isImage,
                let storageKey = item.imageStorageKey,
                item.imageFingerprint == nil,
                let storedImageData = clipboardImageStore.loadImageData(for: storageKey)
            else {
                continue
            }

            let migratedItem = ClipboardItem(
                id: item.id,
                content: item.content,
                imageStorageKey: storageKey,
                imageFingerprint: clipboardImageStore.imageFingerprint(for: storedImageData),
                fileURLStrings: item.fileURLStrings,
                capturedAt: item.capturedAt
            )
            cacheClipboardImageData(storedImageData, for: migratedItem)
            migratedHistory[index] = migratedItem
            didChange = true
        }

        guard didChange else {
            return
        }

        clipboardHistory = migratedHistory
        persistClipboardState(
            history: migratedHistory,
            pinnedIDs: serializedPinnedClipboardIDs()
        )
    }

    private static func loadClipboardHistory(defaults: UserDefaults) -> [ClipboardItem] {
        guard let data = defaults.data(forKey: Keys.clipboardHistoryData) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([ClipboardItem].self, from: data)) ?? []
    }

    private static func loadPinnedClipboardIDs(defaults: UserDefaults) -> Set<UUID> {
        let rawIDs = defaults.stringArray(forKey: Keys.pinnedClipboardIDs) ?? []
        return Set(rawIDs.compactMap(UUID.init(uuidString:)))
    }

    private static func loadAppSettings(defaults: UserDefaults) -> AppSettings {
        guard let data = defaults.data(forKey: Keys.appSettingsData) else {
            return AppSettings()
        }

        let decoder = JSONDecoder()
        var settings = (try? decoder.decode(AppSettings.self, from: data)) ?? AppSettings()
        settings.normalize()
        return settings
    }

    private static func migrateLegacyDefaultsIfNeeded(into sharedDefaults: UserDefaults) {
        let needsAppSettings = sharedDefaults.data(forKey: Keys.appSettingsData) == nil
        let needsClipboardState = !hasPersistedClipboardState(in: sharedDefaults)

        guard needsAppSettings || needsClipboardState else {
            return
        }

        for legacyDefaults in legacyDefaultsCandidates() where
            needsAppSettings && legacyDefaults.data(forKey: Keys.appSettingsData) != nil
                || needsClipboardState && hasPersistedClipboardState(in: legacyDefaults)
        {
            if needsAppSettings, let appSettingsData = legacyDefaults.data(forKey: Keys.appSettingsData) {
                sharedDefaults.set(appSettingsData, forKey: Keys.appSettingsData)
            }

            if needsClipboardState, let historyData = legacyDefaults.data(forKey: Keys.clipboardHistoryData) {
                sharedDefaults.set(historyData, forKey: Keys.clipboardHistoryData)
            }

            if needsClipboardState, let pinnedIDs = legacyDefaults.stringArray(forKey: Keys.pinnedClipboardIDs) {
                sharedDefaults.set(pinnedIDs, forKey: Keys.pinnedClipboardIDs)
            }

            if needsClipboardState,
               let monitoringEnabled = legacyDefaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool {
                sharedDefaults.set(monitoringEnabled, forKey: Keys.clipboardMonitoringEnabled)
            }

            if needsClipboardState,
               let updateCheckPanelOpenCount = legacyDefaults.object(forKey: Keys.updateCheckPanelOpenCount) {
                sharedDefaults.set(updateCheckPanelOpenCount, forKey: Keys.updateCheckPanelOpenCount)
            }

            break
        }
    }

    private static func hasPersistedClipboardState(in defaults: UserDefaults) -> Bool {
        if defaults.data(forKey: Keys.clipboardHistoryData) != nil {
            return true
        }

        if defaults.object(forKey: Keys.pinnedClipboardIDs) != nil {
            return true
        }

        if defaults.object(forKey: Keys.clipboardMonitoringEnabled) != nil {
            return true
        }

        return defaults.object(forKey: Keys.updateCheckPanelOpenCount) != nil
    }

    private static func legacyDefaultsCandidates() -> [UserDefaults] {
        var candidates: [UserDefaults] = [.standard]

        for suiteName in BuildInfo.legacyPreferencesSuiteNames {
            if let defaults = UserDefaults(suiteName: suiteName) {
                candidates.append(defaults)
            }
        }

        return candidates
    }

    private static func allPersistedImageStorageKeys(currentDefaults: UserDefaults) -> Set<String> {
        // ClipboardImages is shared across launch modes, so cleanup must keep
        // storage keys referenced by every known defaults domain, not just the current one.
        let defaultsCandidates = [currentDefaults]
            + legacyDefaultsCandidates()
            + (UserDefaults(suiteName: BuildInfo.preferencesSuiteName).map { [$0] } ?? [])

        return Set(
            defaultsCandidates
                .flatMap { loadClipboardHistory(defaults: $0) }
                .compactMap(\.imageStorageKey)
        )
    }

    private func makeFeedback(
        titleKey: String,
        messageKey: String,
        arguments: [CVarArg] = []
    ) -> StoreFeedback {
        StoreFeedback(
            title: localized(titleKey),
            message: arguments.isEmpty
                ? localized(messageKey)
                : localizationManager.localized(messageKey, arguments: arguments)
        )
    }

    private func rebuildClipboardMetadataCache() {
        metadataByItemID = Dictionary(
            uniqueKeysWithValues: clipboardHistory.map { item in
                (item.id, makeMetadata(for: item))
            }
        )
    }

    private func rebuildFileAvailabilityCache() {
        fileAvailabilityByItemID = makeFileAvailabilityCache()
        lastFileAvailabilityRefreshAt = Date()
    }

    private func makeFileAvailabilityCache() -> [UUID: ClipboardFileAvailability] {
        Dictionary(
            uniqueKeysWithValues: clipboardHistory.map { item in
                (item.id, makeFileAvailability(for: item))
            }
        )
    }

    private func refreshLocalizedSearchLabels() {
        localizedFileSearchLabel = localized("ui.clipboard.item.file")
        localizedImageSearchLabel = localized("ui.clipboard.item.image")
    }

    private func rebuildDerivedClipboardCollections() {
        let query = clipboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines)

        if query.isEmpty {
            filteredClipboardItemsCache = clipboardHistory
        } else {
            filteredClipboardItemsCache = clipboardHistory.filter { item in
                if item.isFile {
                    let fileLabelMatch = localizedFileSearchLabel.localizedCaseInsensitiveContains(query)
                    let ocrMatch = clipboardOCRCache[item.id]?.localizedCaseInsensitiveContains(query) ?? false
                    let searchableText = metadataByItemID[item.id]?.searchableText ?? ""
                    return fileLabelMatch
                        || searchableText.localizedCaseInsensitiveContains(query)
                        || ocrMatch
                }

                if item.isImage {
                    let imageLabelMatch = localizedImageSearchLabel.localizedCaseInsensitiveContains(query)
                    let ocrMatch = clipboardOCRCache[item.id]?.localizedCaseInsensitiveContains(query) ?? false
                    return imageLabelMatch || ocrMatch
                }

                let searchableText = metadataByItemID[item.id]?.searchableText ?? item.content
                return searchableText.localizedCaseInsensitiveContains(query)
            }
        }

        pinnedClipboardItemsCache = filteredClipboardItemsCache.filter { pinnedClipboardItemIDs.contains($0.id) }
        recentClipboardItemsCache = filteredClipboardItemsCache.filter { !pinnedClipboardItemIDs.contains($0.id) }
    }

    private func makeMetadata(for item: ClipboardItem) -> ClipboardItemMetadata {
        let fileURLs = (item.fileURLStrings ?? []).compactMap(URL.init(string:))
        let imageFileURLs = fileURLs.filter(isImageFileURL)
        let previewTitle = item.previewTitle
        let previewSubtitle = item.previewSubtitle
        let searchableText: String

        if item.isFile {
            let fileNames = fileURLs.map(\.lastPathComponent).joined(separator: "\n")
            let filePaths = fileURLs.map(\.path).joined(separator: "\n")
            searchableText = [fileNames, filePaths]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } else {
            searchableText = item.content
        }

        return ClipboardItemMetadata(
            fileURLs: fileURLs,
            firstFileURL: fileURLs.first,
            imageFileURLs: imageFileURLs,
            firstImageFileURL: imageFileURLs.first,
            fileHelpText: fileURLs.map(\.path).joined(separator: "\n"),
            previewTitle: previewTitle,
            previewSubtitle: previewSubtitle,
            searchableText: searchableText
        )
    }

    private func fileAvailability(for item: ClipboardItem) -> ClipboardFileAvailability {
        if let cachedAvailability = fileAvailabilityByItemID[item.id] {
            return cachedAvailability
        }

        let availability = makeFileAvailability(for: item)
        fileAvailabilityByItemID[item.id] = availability
        return availability
    }

    private func makeFileAvailability(for item: ClipboardItem) -> ClipboardFileAvailability {
        let metadata = metadataByItemID[item.id]
        let fileURLs = metadata?.fileURLs ?? item.fileURLs
        let imageFileURLSet = Set((metadata?.imageFileURLs ?? []).map(\.standardizedFileURL))
        var availableFileURLs: [URL] = []
        var missingFileURLs: [URL] = []
        var availableImageFileURLs: [URL] = []

        for fileURL in fileURLs {
            let standardizedURL = fileURL.standardizedFileURL

            if fileReferenceExists(standardizedURL) {
                availableFileURLs.append(standardizedURL)
                if imageFileURLSet.contains(standardizedURL) {
                    availableImageFileURLs.append(standardizedURL)
                }
            } else {
                missingFileURLs.append(standardizedURL)
            }
        }

        return ClipboardFileAvailability(
            availableFileURLs: availableFileURLs,
            missingFileURLs: missingFileURLs,
            availableImageFileURLs: availableImageFileURLs
        )
    }

    private func storedImageClipboardItem(
        from item: ClipboardItem,
        rawData: Data,
        fingerprint: String,
        capturedAt: Date
    ) -> ClipboardItem {
        let storageKey = item.imageStorageKey ?? clipboardImageStore.storageKey(for: item.id)

        do {
            if !clipboardImageStore.fileExists(for: storageKey) || item.imageStorageKey == nil || item.imageTIFFData != nil {
                try clipboardImageStore.saveImageData(rawData, for: storageKey)
            }

            let storedItem = ClipboardItem(
                id: item.id,
                content: item.content,
                imageStorageKey: storageKey,
                imageFingerprint: fingerprint,
                fileURLStrings: item.fileURLStrings,
                capturedAt: capturedAt
            )
            cacheClipboardImageData(rawData, for: storedItem)
            return storedItem
        } catch {
            let fallbackItem = ClipboardItem(
                id: item.id,
                content: item.content,
                imageTIFFData: rawData,
                imageFingerprint: fingerprint,
                fileURLStrings: item.fileURLStrings,
                capturedAt: capturedAt
            )
            cacheClipboardImageData(rawData, for: fallbackItem)
            return fallbackItem
        }
    }

    private func imageCacheKey(for item: ClipboardItem) -> String? {
        if let storageKey = item.imageStorageKey {
            return storageKey
        }

        guard item.imageTIFFData != nil else {
            return nil
        }
        return item.id.uuidString.lowercased()
    }

    private func cacheClipboardImageData(_ data: Data, for item: ClipboardItem) {
        guard let cacheKey = imageCacheKey(for: item) else {
            return
        }

        imageDataCache[cacheKey] = data
    }

    private func removeStoredImages(for removedItems: [ClipboardItem]) {
        let remainingStorageKeys = Set(clipboardHistory.compactMap(\.imageStorageKey))
        let removedStorageKeys = Set(removedItems.compactMap(\.imageStorageKey))
        let remainingFileImageCacheKeys = Set(
            metadataByItemID.values
                .flatMap(\.imageFileURLs)
                .map(fileImageCacheKey(for:))
        )
        let removedFileImageCacheKeys = Set(
            removedItems
                .flatMap(\.fileURLs)
                .filter(isImageFileURL)
                .map(fileImageCacheKey(for:))
        )

        for storageKey in removedStorageKeys where !remainingStorageKeys.contains(storageKey) {
            clipboardImageStore.removeImage(for: storageKey)
            imageDataCache.removeValue(forKey: storageKey)
            imagePreviewCache.removeValue(forKey: storageKey)
        }

        for item in removedItems where item.imageStorageKey == nil {
            guard let cacheKey = imageCacheKey(for: item) else {
                continue
            }
            imageDataCache.removeValue(forKey: cacheKey)
            imagePreviewCache.removeValue(forKey: cacheKey)
        }

        for cacheKey in removedFileImageCacheKeys where !remainingFileImageCacheKeys.contains(cacheKey) {
            fileImageDataCache.removeValue(forKey: cacheKey)
            fileImagePreviewCache.removeValue(forKey: cacheKey)
        }
    }

    private func isImageFileURL(_ url: URL) -> Bool {
        if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return contentType.conforms(to: .image)
        }

        guard let fileType = UTType(filenameExtension: url.pathExtension) else {
            return false
        }

        return fileType.conforms(to: .image)
    }

    private func fileImageCacheKey(for url: URL) -> String {
        "file:\(url.standardizedFileURL.absoluteString)"
    }

    private func loadImageDataFromFile(_ url: URL) -> Data? {
        let cacheKey = fileImageCacheKey(for: url)
        guard fileReferenceExists(url) else {
            fileImageDataCache.removeValue(forKey: cacheKey)
            fileImagePreviewCache.removeValue(forKey: cacheKey)
            return nil
        }

        if let cachedData = fileImageDataCache[cacheKey] {
            return cachedData
        }

        guard let imageData = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            return nil
        }

        fileImageDataCache[cacheKey] = imageData
        return imageData
    }

    private func previewImage(forFileURL url: URL) -> NSImage? {
        let cacheKey = fileImageCacheKey(for: url)
        guard fileReferenceExists(url) else {
            fileImageDataCache.removeValue(forKey: cacheKey)
            fileImagePreviewCache.removeValue(forKey: cacheKey)
            return nil
        }

        if let cachedImage = fileImagePreviewCache[cacheKey] {
            return cachedImage
        }

        guard let imageData = loadImageDataFromFile(url), let image = NSImage(data: imageData) else {
            return nil
        }

        fileImagePreviewCache[cacheKey] = image
        return image
    }

    private func clipboardIsImageDataItem(_ item: ClipboardItem) -> Bool {
        item.isImage && !clipboardIsFileItem(item)
    }

    private func fileReferenceExists(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private func purgeUnusedStoredImages() {
        clipboardImageStore.purgeUnusedImages(
            keeping: Self.allPersistedImageStorageKeys(currentDefaults: defaults)
        )
    }

    private enum ShortcutHintStyle {
        case defaultStyle
        case chineseSimplified
        case chineseTraditional
    }

    private var shortcutHintStyle: ShortcutHintStyle {
        let identifier = localizationManager.effectiveLanguageIdentifier.lowercased()

        if identifier.hasPrefix("zh") {
            if identifier.contains("hant") || identifier.contains("tw") || identifier.contains("hk") || identifier.contains("mo") {
                return .chineseTraditional
            }
            return .chineseSimplified
        }

        if ["yue", "nan", "hak"].contains(where: { identifier.hasPrefix($0) }) {
            return .chineseTraditional
        }

        if identifier.hasPrefix("wuu") {
            return .chineseSimplified
        }

        return .defaultStyle
    }

    // MARK: - Update

    func checkForUpdates(force: Bool = false) async {
        if !force && !automaticallyChecksForUpdates {
            return
        }

        if isCheckingForUpdates {
            return
        }

        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
        }

        if force {
            resetUpdateCheckPanelOpenCount()
        }

        let currentVersion = AppVersion.shortVersion
        do {
            let release = try await updateService.fetchLatestRelease()
            if updateService.isNewerVersion(release.versionNumber, than: currentVersion) {
                pendingUpdateRelease = release
            } else {
                pendingUpdateRelease = nil
            }
        } catch {
            // Silent fail — update check is best-effort
        }
    }

    func installUpdate() async {
        guard let release = pendingUpdateRelease else { return }
        isUpdateInstalling = true
        do {
            try await updateService.downloadAndInstall(release: release)
        } catch {
            isUpdateInstalling = false
            NSWorkspace.shared.open(updateService.manualDownloadURL(for: release))
        }
    }

    func startupUpdateCheckIfNeeded() async {
        guard automaticallyChecksForUpdates else {
            return
        }

        try? await Task.sleep(for: .seconds(5))
        await checkForUpdates(force: true)
    }

    func checkForUpdatesManually() async -> StoreFeedback {
        if isCheckingForUpdates {
            return makeFeedback(
                titleKey: "feedback.update.title",
                messageKey: "feedback.update.checking"
            )
        }

        isCheckingForUpdates = true
        defer {
            isCheckingForUpdates = false
        }

        resetUpdateCheckPanelOpenCount()

        let currentVersion = AppVersion.shortVersion

        do {
            let release = try await updateService.fetchLatestRelease()
            if updateService.isNewerVersion(release.versionNumber, than: currentVersion) {
                pendingUpdateRelease = release
                return makeFeedback(
                    titleKey: "feedback.update.title",
                    messageKey: "feedback.update.available",
                    arguments: [release.versionNumber]
                )
            }

            pendingUpdateRelease = nil
            return makeFeedback(
                titleKey: "feedback.update.title",
                messageKey: "feedback.update.upToDate"
            )
        } catch {
            return makeFeedback(
                titleKey: "feedback.update.title",
                messageKey: "feedback.update.failed"
            )
        }
    }

    private func resetUpdateCheckPanelOpenCount() {
        panelOpenCountSinceLastUpdateCheck = 0
        defaults.set(0, forKey: Keys.updateCheckPanelOpenCount)
    }
}
