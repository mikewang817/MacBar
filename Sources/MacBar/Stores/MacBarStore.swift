import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

struct StoreFeedback {
    let title: String
    let message: String
}

enum ClipboardResolvedOCRSource: Equatable {
    case clipboardImageData
    case fileURL(URL)
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
            rebuildResolvedClipboardItemState()
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
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .unavailable
    @Published private(set) var pendingUpdateRelease: GitHubRelease? = nil
    @Published private(set) var isUpdateInstalling: Bool = false
    @Published private(set) var isCheckingForUpdates: Bool = false

    private let defaults: UserDefaults
    private let localizationManager: LocalizationManager
    private let clipboardMonitor: ClipboardMonitor
    private let clipboardImageStore: ClipboardImageStore
    private let launchAtLoginService: LaunchAtLoginService
    private let fileAccessService: SecurityScopedFileAccessService
    private let updateService = UpdateService()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingPersistenceTask: Task<Void, Never>?
    private var panelOpenCountSinceLastUpdateCheck: Int
    private var imageDataCache: [String: Data] = [:]
    private var imagePreviewCache: [String: NSImage] = [:]
    private var fileImageDataCache: [String: Data] = [:]
    private var fileImagePreviewCache: [String: NSImage] = [:]
    private var resolvedStateByItemID: [UUID: ClipboardItemResolvedState] = [:]
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

    private struct ClipboardItemResolvedState: Equatable {
        let fileReferences: [SecurityScopedResolvedFile]
        let firstFileReference: SecurityScopedResolvedFile?
        let availableFileReferences: [SecurityScopedResolvedFile]
        let missingFileReferences: [SecurityScopedResolvedFile]
        let availableImageFileReferences: [SecurityScopedResolvedFile]
        let fileHelpText: String
        let previewTitle: String
        let previewSubtitle: String
        let searchableText: String
        let isImageDataItem: Bool
        let hasStoredImageData: Bool

        var fileURLs: [URL] {
            fileReferences.map(\.resolvedURL)
        }

        var firstFileURL: URL? {
            firstFileReference?.resolvedURL
        }

        var availableFileURLs: [URL] {
            availableFileReferences.map(\.resolvedURL)
        }

        var missingFileURLs: [URL] {
            missingFileReferences.map(\.resolvedURL)
        }

        var availableImageFileURLs: [URL] {
            availableImageFileReferences.map(\.resolvedURL)
        }

        var isFileItem: Bool {
            !fileReferences.isEmpty
        }

        var isUnavailableFileItem: Bool {
            isFileItem && availableFileReferences.isEmpty
        }

        var previewImageFileReference: SecurityScopedResolvedFile? {
            availableImageFileReferences.first
        }

        var hasPreviewImage: Bool {
            hasStoredImageData || previewImageFileReference != nil
        }

        var ocrSources: [ClipboardResolvedOCRSource] {
            if hasStoredImageData {
                return [.clipboardImageData]
            }

            return availableImageFileReferences.map { .fileURL($0.resolvedURL) }
        }

        var canCopy: Bool {
            if isFileItem {
                return !availableFileReferences.isEmpty
            }

            if isImageDataItem {
                return hasStoredImageData
            }

            return true
        }
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
        clipboardImageStore: ClipboardImageStore = ClipboardImageStore(),
        launchAtLoginService: LaunchAtLoginService = LaunchAtLoginService(),
        fileAccessService: SecurityScopedFileAccessService = SecurityScopedFileAccessService()
    ) {
        self.defaults = defaults
        self.localizationManager = localizationManager
        self.clipboardMonitor = clipboardMonitor
        self.clipboardImageStore = clipboardImageStore
        self.launchAtLoginService = launchAtLoginService
        self.fileAccessService = fileAccessService
        self.settings = Self.loadAppSettings(defaults: defaults)
        self.clipboardHistory = Self.loadClipboardHistory(defaults: defaults)
        self.pinnedClipboardItemIDs = Self.loadPinnedClipboardIDs(defaults: defaults)
        self.isClipboardMonitoringEnabled = defaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool ?? true
        self.panelOpenCountSinceLastUpdateCheck = defaults.integer(forKey: Keys.updateCheckPanelOpenCount)

        normalizeClipboardState()
        migrateLegacyClipboardImagesIfNeeded()
        migrateLegacyFileBookmarksIfNeeded()
        enforceRetentionPolicies(persistChanges: true)
        purgeUnusedStoredImages()
        rebuildResolvedClipboardItemState()
        refreshLocalizedSearchLabels()
        rebuildDerivedClipboardCollections()
        configureClipboardMonitoring()
        syncLaunchAtLoginPreference()

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

    var launchesAtLogin: Bool {
        settings.launchesAtLogin
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

    func setLaunchesAtLogin(_ isEnabled: Bool) {
        updateSettings {
            $0.launchesAtLogin = isEnabled
        }
        syncLaunchAtLoginPreference()
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
        guard BuildInfo.supportsExternalUpdates, automaticallyChecksForUpdates else {
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
        let availableFileReferences = resolvedState(for: item).availableFileReferences
        if !availableFileReferences.isEmpty {
            withAccessibleFileURLs(availableFileReferences) { fileURLs in
                clipboardMonitor.copyFilesToPasteboard(fileURLs)
            }
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
                fileBookmarkDataByURLString: item.fileBookmarkDataByURLString,
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
        let resolvedState = resolvedState(for: item)
        guard resolvedState.isImageDataItem, resolvedState.hasStoredImageData else {
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
        resolvedState(for: item).hasPreviewImage
    }

    func clipboardIsFileItem(_ item: ClipboardItem) -> Bool {
        resolvedState(for: item).isFileItem
    }

    func clipboardPreviewImage(for item: ClipboardItem) -> NSImage? {
        let resolvedState = resolvedState(for: item)

        if resolvedState.isImageDataItem {
            return clipboardImage(for: item)
        }

        guard let imageFileReference = resolvedState.previewImageFileReference else {
            return nil
        }

        return previewImage(forFileReference: imageFileReference)
    }

    func clipboardImageFileURLs(for item: ClipboardItem) -> [URL] {
        resolvedState(for: item).availableImageFileURLs
    }

    func clipboardOCRSources(for item: ClipboardItem) -> [ClipboardResolvedOCRSource] {
        resolvedState(for: item).ocrSources
    }

    func clipboardOCRSource(for item: ClipboardItem, at index: Int) -> ClipboardResolvedOCRSource? {
        let ocrSources = resolvedState(for: item).ocrSources
        guard ocrSources.indices.contains(index) else {
            return nil
        }

        return ocrSources[index]
    }

    func clipboardOCRImageData(for item: ClipboardItem, at index: Int) -> Data? {
        let resolvedState = resolvedState(for: item)
        guard resolvedState.availableImageFileReferences.indices.contains(index) else {
            return nil
        }

        return loadImageDataFromFile(resolvedState.availableImageFileReferences[index])
    }

    func clipboardFileURLs(for item: ClipboardItem) -> [URL] {
        resolvedState(for: item).fileURLs
    }

    func clipboardAvailableFileURLs(for item: ClipboardItem) -> [URL] {
        resolvedState(for: item).availableFileURLs
    }

    func clipboardMissingFileURLs(for item: ClipboardItem) -> [URL] {
        resolvedState(for: item).missingFileURLs
    }

    func clipboardHasMissingFiles(_ item: ClipboardItem) -> Bool {
        !clipboardMissingFileURLs(for: item).isEmpty
    }

    func clipboardIsFileItemUnavailable(_ item: ClipboardItem) -> Bool {
        resolvedState(for: item).isUnavailableFileItem
    }

    func clipboardCanCopy(_ item: ClipboardItem) -> Bool {
        resolvedState(for: item).canCopy
    }

    func withClipboardFileAccess<Result>(
        for item: ClipboardItem,
        _ body: ([URL]) -> Result
    ) -> Result? {
        let availableFileReferences = resolvedState(for: item).availableFileReferences
        guard !availableFileReferences.isEmpty else {
            return nil
        }

        return withAccessibleFileURLs(availableFileReferences, body)
    }

    func refreshClipboardFileAvailability(force: Bool = false) {
        let now = Date()
        if !force,
           let lastFileAvailabilityRefreshAt,
           now.timeIntervalSince(lastFileAvailabilityRefreshAt) < Self.fileAvailabilityRefreshInterval {
            return
        }

        let updatedResolvedState = makeResolvedStateCache()
        lastFileAvailabilityRefreshAt = now

        guard updatedResolvedState != resolvedStateByItemID else {
            return
        }

        resolvedStateByItemID = updatedResolvedState
        objectWillChange.send()
    }

    func clipboardFirstFileURL(for item: ClipboardItem) -> URL? {
        resolvedState(for: item).firstFileURL
    }

    func clipboardFileHelpText(for item: ClipboardItem) -> String {
        resolvedState(for: item).fileHelpText
    }

    func clipboardDisplayTitle(for item: ClipboardItem) -> String {
        if clipboardIsImageDataItem(item) {
            return localized("ui.clipboard.item.image")
        }

        let previewTitle = resolvedState(for: item).previewTitle
        return previewTitle.isEmpty ? localized("ui.clipboard.item.empty") : previewTitle
    }

    func clipboardDisplaySubtitle(for item: ClipboardItem) -> String {
        let previewSubtitle = resolvedState(for: item).previewSubtitle
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
        let capturedBookmarks = mergedBookmarkDataByURLString(
            for: urls,
            existing: clipboardHistory.first?.fileBookmarkDataByURLString
        )

        if clipboardHistory.first?.fileURLStrings == urlStrings {
            if let firstItem = clipboardHistory.first,
               firstItem.fileBookmarkDataByURLString != capturedBookmarks {
                clipboardHistory[0] = ClipboardItem(
                    id: firstItem.id,
                    content: firstItem.content,
                    imageTIFFData: firstItem.imageTIFFData,
                    imageStorageKey: firstItem.imageStorageKey,
                    imageFingerprint: firstItem.imageFingerprint,
                    fileURLStrings: urlStrings,
                    fileBookmarkDataByURLString: capturedBookmarks,
                    capturedAt: firstItem.capturedAt
                )
                schedulePersistence()
            }
            return
        }

        if let existingIndex = clipboardHistory.firstIndex(where: { $0.fileURLStrings == urlStrings }) {
            let existing = clipboardHistory.remove(at: existingIndex)
            clipboardHistory.insert(
                ClipboardItem(
                    id: existing.id,
                    content: "",
                    fileURLStrings: urlStrings,
                    fileBookmarkDataByURLString: mergedBookmarkDataByURLString(
                        for: urls,
                        existing: existing.fileBookmarkDataByURLString
                    ),
                    capturedAt: Date()
                ),
                at: 0
            )
        } else {
            clipboardHistory.insert(
                ClipboardItem(
                    content: "",
                    fileURLStrings: urlStrings,
                    fileBookmarkDataByURLString: capturedBookmarks,
                    capturedAt: Date()
                ),
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

    private func syncLaunchAtLoginPreference() {
        launchAtLoginStatus = launchAtLoginService.setEnabled(settings.launchesAtLogin)
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLoginStatus = launchAtLoginService.currentStatus()
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
                fileBookmarkDataByURLString: item.fileBookmarkDataByURLString,
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

    private func migrateLegacyFileBookmarksIfNeeded() {
        var migratedHistory = clipboardHistory
        var didChange = false

        for index in migratedHistory.indices {
            let item = migratedHistory[index]
            guard item.isFile else {
                continue
            }

            let mergedBookmarks = mergedBookmarkDataByURLString(
                for: item.fileURLs,
                existing: item.fileBookmarkDataByURLString
            )

            guard mergedBookmarks != item.fileBookmarkDataByURLString else {
                continue
            }

            migratedHistory[index] = ClipboardItem(
                id: item.id,
                content: item.content,
                imageTIFFData: item.imageTIFFData,
                imageStorageKey: item.imageStorageKey,
                imageFingerprint: item.imageFingerprint,
                fileURLStrings: item.fileURLStrings,
                fileBookmarkDataByURLString: mergedBookmarks,
                capturedAt: item.capturedAt
            )
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

    private func mergedBookmarkDataByURLString(
        for urls: [URL],
        existing: [String: Data]?
    ) -> [String: Data]? {
        var mergedBookmarks = existing ?? [:]

        for url in urls {
            guard
                url.isFileURL,
                mergedBookmarks[url.absoluteString] == nil,
                let bookmarkData = fileAccessService.makeReadOnlyBookmark(for: url)
            else {
                continue
            }

            mergedBookmarks[url.absoluteString] = bookmarkData
        }

        return mergedBookmarks.isEmpty ? nil : mergedBookmarks
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

    private func rebuildResolvedClipboardItemState() {
        resolvedStateByItemID = Dictionary(
            uniqueKeysWithValues: clipboardHistory.map { item in
                (item.id, makeResolvedState(for: item))
            }
        )
        lastFileAvailabilityRefreshAt = Date()
    }

    private func makeResolvedStateCache() -> [UUID: ClipboardItemResolvedState] {
        Dictionary(
            uniqueKeysWithValues: clipboardHistory.map { item in
                (item.id, makeResolvedState(for: item))
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
                    let searchableText = resolvedStateByItemID[item.id]?.searchableText ?? ""
                    return fileLabelMatch
                        || searchableText.localizedCaseInsensitiveContains(query)
                        || ocrMatch
                }

                if item.isImage {
                    let imageLabelMatch = localizedImageSearchLabel.localizedCaseInsensitiveContains(query)
                    let ocrMatch = clipboardOCRCache[item.id]?.localizedCaseInsensitiveContains(query) ?? false
                    return imageLabelMatch || ocrMatch
                }

                let searchableText = resolvedStateByItemID[item.id]?.searchableText ?? item.content
                return searchableText.localizedCaseInsensitiveContains(query)
            }
        }

        pinnedClipboardItemsCache = filteredClipboardItemsCache.filter { pinnedClipboardItemIDs.contains($0.id) }
        recentClipboardItemsCache = filteredClipboardItemsCache.filter { !pinnedClipboardItemIDs.contains($0.id) }
    }

    private func resolvedState(for item: ClipboardItem) -> ClipboardItemResolvedState {
        if let cachedState = resolvedStateByItemID[item.id] {
            return cachedState
        }

        let state = makeResolvedState(for: item)
        resolvedStateByItemID[item.id] = state
        return state
    }

    private func makeResolvedState(for item: ClipboardItem) -> ClipboardItemResolvedState {
        let fileBookmarkDataByURLString = item.fileBookmarkDataByURLString ?? [:]
        let fileReferences = item.fileURLs.map { fileURL in
            fileAccessService.resolveFile(
                fileURL,
                bookmarkData: fileBookmarkDataByURLString[fileURL.absoluteString]
            )
        }
        var availableFileReferences: [SecurityScopedResolvedFile] = []
        var missingFileReferences: [SecurityScopedResolvedFile] = []
        var availableImageFileReferences: [SecurityScopedResolvedFile] = []

        for fileReference in fileReferences {
            if fileReferenceExists(fileReference) {
                availableFileReferences.append(fileReference)
                if isImageFileReference(fileReference) {
                    availableImageFileReferences.append(fileReference)
                }
            } else {
                missingFileReferences.append(fileReference)
            }
        }

        let previewTitle = item.previewTitle
        let previewSubtitle = item.previewSubtitle
        let searchableText: String
        let isImageDataItem = item.isImage && fileReferences.isEmpty
        let hasStoredImageData: Bool

        if item.isFile {
            let fileNames = fileReferences.map { $0.resolvedURL.lastPathComponent }.joined(separator: "\n")
            let filePaths = fileReferences.map { $0.resolvedURL.path }.joined(separator: "\n")
            searchableText = [fileNames, filePaths]
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        } else {
            searchableText = item.content
        }

        if isImageDataItem {
            if let storageKey = item.imageStorageKey {
                hasStoredImageData = clipboardImageStore.fileExists(for: storageKey)
            } else {
                hasStoredImageData = item.imageTIFFData != nil
            }
        } else {
            hasStoredImageData = false
        }

        return ClipboardItemResolvedState(
            fileReferences: fileReferences,
            firstFileReference: fileReferences.first,
            availableFileReferences: availableFileReferences,
            missingFileReferences: missingFileReferences,
            availableImageFileReferences: availableImageFileReferences,
            fileHelpText: fileReferences.map { $0.resolvedURL.path }.joined(separator: "\n"),
            previewTitle: previewTitle,
            previewSubtitle: previewSubtitle,
            searchableText: searchableText,
            isImageDataItem: isImageDataItem,
            hasStoredImageData: hasStoredImageData
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
                fileBookmarkDataByURLString: item.fileBookmarkDataByURLString,
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
                fileBookmarkDataByURLString: item.fileBookmarkDataByURLString,
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
            resolvedStateByItemID.values
                .flatMap(\.availableImageFileURLs)
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

    private func isImageFileReference(_ fileReference: SecurityScopedResolvedFile) -> Bool {
        fileAccessService.withAccess(to: fileReference) { accessibleURL in
            if let contentType = try? accessibleURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
                return contentType.conforms(to: .image)
            }

            return isImageFileURL(accessibleURL)
        }
    }

    private func fileImageCacheKey(for url: URL) -> String {
        "file:\(url.standardizedFileURL.absoluteString)"
    }

    private func fileImageCacheKey(for fileReference: SecurityScopedResolvedFile) -> String {
        fileImageCacheKey(for: fileReference.resolvedURL)
    }

    private func loadImageDataFromFile(_ fileReference: SecurityScopedResolvedFile) -> Data? {
        let cacheKey = fileImageCacheKey(for: fileReference)
        guard fileReferenceExists(fileReference) else {
            fileImageDataCache.removeValue(forKey: cacheKey)
            fileImagePreviewCache.removeValue(forKey: cacheKey)
            return nil
        }

        if let cachedData = fileImageDataCache[cacheKey] {
            return cachedData
        }

        let imageData = fileAccessService.withAccess(to: fileReference) { accessibleURL in
            try? Data(contentsOf: accessibleURL, options: [.mappedIfSafe])
        }
        guard let imageData else {
            return nil
        }

        fileImageDataCache[cacheKey] = imageData
        return imageData
    }

    private func previewImage(forFileReference fileReference: SecurityScopedResolvedFile) -> NSImage? {
        let cacheKey = fileImageCacheKey(for: fileReference)
        guard fileReferenceExists(fileReference) else {
            fileImageDataCache.removeValue(forKey: cacheKey)
            fileImagePreviewCache.removeValue(forKey: cacheKey)
            return nil
        }

        if let cachedImage = fileImagePreviewCache[cacheKey] {
            return cachedImage
        }

        guard let imageData = loadImageDataFromFile(fileReference), let image = NSImage(data: imageData) else {
            return nil
        }

        fileImagePreviewCache[cacheKey] = image
        return image
    }

    private func clipboardIsImageDataItem(_ item: ClipboardItem) -> Bool {
        resolvedState(for: item).isImageDataItem
    }

    private func fileReferenceExists(_ fileReference: SecurityScopedResolvedFile) -> Bool {
        fileAccessService.withAccess(to: fileReference) { accessibleURL in
            guard accessibleURL.isFileURL else {
                return false
            }

            return FileManager.default.fileExists(atPath: accessibleURL.path)
        }
    }

    private func fileReferenceExists(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private func withAccessibleFileURLs<Result>(
        _ fileReferences: [SecurityScopedResolvedFile],
        _ body: ([URL]) -> Result
    ) -> Result {
        var startedURLs: [URL] = []
        for fileReference in fileReferences {
            guard fileReference.bookmarkData != nil else {
                continue
            }

            if fileReference.resolvedURL.startAccessingSecurityScopedResource() {
                startedURLs.append(fileReference.resolvedURL)
            }
        }
        defer {
            for url in startedURLs {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return body(fileReferences.map(\.resolvedURL))
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
        guard BuildInfo.supportsExternalUpdates else {
            pendingUpdateRelease = nil
            isUpdateInstalling = false
            isCheckingForUpdates = false
            return
        }

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
        guard BuildInfo.supportsExternalUpdates else {
            pendingUpdateRelease = nil
            isUpdateInstalling = false
            return
        }

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
        guard BuildInfo.supportsExternalUpdates, automaticallyChecksForUpdates else {
            return
        }

        try? await Task.sleep(for: .seconds(5))
        await checkForUpdates(force: true)
    }

    func checkForUpdatesManually() async -> StoreFeedback {
        guard BuildInfo.supportsExternalUpdates else {
            pendingUpdateRelease = nil
            return makeFeedback(
                titleKey: "feedback.update.title",
                messageKey: "feedback.update.upToDate"
            )
        }

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
