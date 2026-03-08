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
    @Published var clipboardSearchText: String = "" {
        didSet { rebuildDerivedClipboardCollections() }
    }
    @Published private(set) var clipboardHistory: [ClipboardItem] {
        didSet {
            rebuildClipboardMetadataCache()
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

    private let defaults: UserDefaults
    private let localizationManager: LocalizationManager
    private let clipboardMonitor: ClipboardMonitor
    private let clipboardImageStore: ClipboardImageStore
    private let updateService = UpdateService()
    private var cancellables: Set<AnyCancellable> = []
    private var pendingPersistenceTask: Task<Void, Never>?
    private var panelOpenCountSinceLastUpdateCheck: Int
    private var isCheckingForUpdates = false
    private var imageDataCache: [String: Data] = [:]
    private var imagePreviewCache: [String: NSImage] = [:]
    private var fileImageDataCache: [String: Data] = [:]
    private var fileImagePreviewCache: [String: NSImage] = [:]
    private var metadataByItemID: [UUID: ClipboardItemMetadata] = [:]
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
        static let clipboardHistoryData = "macbar.clipboardHistoryData"
        static let pinnedClipboardIDs = "macbar.pinnedClipboardIDs"
        static let clipboardMonitoringEnabled = "macbar.clipboardMonitoringEnabled"
        static let updateCheckPanelOpenCount = "macbar.updateCheckPanelOpenCount"
    }

    private static let updateCheckPanelOpenThreshold = 20

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
        self.clipboardHistory = Self.loadClipboardHistory(defaults: defaults)
        self.pinnedClipboardItemIDs = Self.loadPinnedClipboardIDs(defaults: defaults)
        self.isClipboardMonitoringEnabled = defaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool ?? true
        self.panelOpenCountSinceLastUpdateCheck = defaults.integer(forKey: Keys.updateCheckPanelOpenCount)

        normalizeClipboardState()
        migrateLegacyClipboardImagesIfNeeded()
        purgeUnusedStoredImages()
        rebuildClipboardMetadataCache()
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

    func localized(_ key: String) -> String {
        localizationManager.localized(key)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localizationManager.localized(key, arguments: arguments)
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
        schedulePersistence()
    }

    func copyClipboardItem(_ itemID: UUID, persistHistoryImmediately: Bool = true) -> StoreFeedback? {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let item = clipboardHistory[index]
        if item.isFile {
            clipboardMonitor.copyFilesToPasteboard(item.fileURLs)
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

    func clipboardCapturedAtLabel(for item: ClipboardItem) -> String {
        relativeDateTimeFormatter.locale = Locale(identifier: localizationManager.effectiveLanguageIdentifier)
        return relativeDateTimeFormatter.localizedString(for: item.capturedAt, relativeTo: Date())
    }

    func clipboardImageData(for item: ClipboardItem) -> Data? {
        guard item.isImage else {
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
        guard item.isImage else {
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
        if item.isImage {
            return true
        }

        return metadataByItemID[item.id]?.firstImageFileURL != nil
    }

    func clipboardPreviewImage(for item: ClipboardItem) -> NSImage? {
        if item.isImage {
            return clipboardImage(for: item)
        }

        guard let imageFileURL = metadataByItemID[item.id]?.firstImageFileURL else {
            return nil
        }

        return previewImage(forFileURL: imageFileURL)
    }

    func clipboardOCRImageDataList(for item: ClipboardItem) -> [Data] {
        if let imageData = clipboardImageData(for: item) {
            return [imageData]
        }

        let imageFileURLs = metadataByItemID[item.id]?.imageFileURLs ?? []
        return imageFileURLs.compactMap(loadImageDataFromFile)
    }

    func clipboardFileURLs(for item: ClipboardItem) -> [URL] {
        metadataByItemID[item.id]?.fileURLs ?? item.fileURLs
    }

    func clipboardFirstFileURL(for item: ClipboardItem) -> URL? {
        metadataByItemID[item.id]?.firstFileURL ?? clipboardFileURLs(for: item).first
    }

    func clipboardFileHelpText(for item: ClipboardItem) -> String {
        metadataByItemID[item.id]?.fileHelpText ?? ""
    }

    func clipboardDisplayTitle(for item: ClipboardItem) -> String {
        if item.isImage {
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

    private func setClipboardMonitoringEnabled(_ isEnabled: Bool) {
        guard isClipboardMonitoringEnabled != isEnabled else {
            return
        }

        isClipboardMonitoringEnabled = isEnabled
        defaults.set(isEnabled, forKey: Keys.clipboardMonitoringEnabled)
        configureClipboardMonitoring()
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
        if let cachedImage = fileImagePreviewCache[cacheKey] {
            return cachedImage
        }

        guard let imageData = loadImageDataFromFile(url), let image = NSImage(data: imageData) else {
            return nil
        }

        fileImagePreviewCache[cacheKey] = image
        return image
    }

    private func purgeUnusedStoredImages() {
        clipboardImageStore.purgeUnusedImages(keeping: Set(clipboardHistory.compactMap(\.imageStorageKey)))
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

    private func resetUpdateCheckPanelOpenCount() {
        panelOpenCountSinceLastUpdateCheck = 0
        defaults.set(0, forKey: Keys.updateCheckPanelOpenCount)
    }
}
