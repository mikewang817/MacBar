import AppKit
import Combine
import Foundation

struct StoreFeedback {
    let title: String
    let message: String
}

@MainActor
final class MacBarStore: ObservableObject {
    @Published var activePanel: AppPanel = .clipboard
    @Published var clipboardSearchText: String = ""
    @Published private(set) var clipboardHistory: [ClipboardItem]
    @Published private(set) var pinnedClipboardItemIDs: Set<UUID>
    @Published private(set) var isClipboardMonitoringEnabled: Bool
    @Published private(set) var clipboardOCRCache: [UUID: String] = [:]
    @Published private(set) var pendingUpdateRelease: GitHubRelease? = nil
    @Published private(set) var isUpdateInstalling: Bool = false

    private let defaults: UserDefaults
    private let localizationManager: LocalizationManager
    private let configurationManager: AppConfigurationManager
    private let clipboardMonitor: ClipboardMonitor
    private let updateService = UpdateService()
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let clipboardHistoryData = "macbar.clipboardHistoryData"
        static let pinnedClipboardIDs = "macbar.pinnedClipboardIDs"
        static let clipboardMonitoringEnabled = "macbar.clipboardMonitoringEnabled"
    }

    init(
        defaults: UserDefaults = .standard,
        localizationManager: LocalizationManager = LocalizationManager(),
        configurationManager: AppConfigurationManager = AppConfigurationManager(),
        clipboardMonitor: ClipboardMonitor = ClipboardMonitor()
    ) {
        self.defaults = defaults
        self.localizationManager = localizationManager
        self.configurationManager = configurationManager
        self.clipboardMonitor = clipboardMonitor
        self.clipboardHistory = Self.loadClipboardHistory(defaults: defaults)
        self.pinnedClipboardItemIDs = Self.loadPinnedClipboardIDs(defaults: defaults)
        self.isClipboardMonitoringEnabled = defaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool ?? true

        normalizeClipboardState()
        configureClipboardMonitoring()

        localizationManager.$effectiveLanguageIdentifier
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
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
        filteredClipboardItems.filter { pinnedClipboardItemIDs.contains($0.id) }
    }

    var recentClipboardItems: [ClipboardItem] {
        filteredClipboardItems.filter { !pinnedClipboardItemIDs.contains($0.id) }
    }

    var visibleClipboardItems: [ClipboardItem] {
        filteredClipboardItems
    }

    func localized(_ key: String) -> String {
        localizationManager.localized(key)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localizationManager.localized(key, arguments: arguments)
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
        saveClipboardHistory()
        savePinnedClipboardIDs()
    }

    func copyClipboardItem(_ itemID: UUID) -> StoreFeedback? {
        guard let index = clipboardHistory.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let item = clipboardHistory[index]
        if item.isFile {
            clipboardMonitor.copyFilesToPasteboard(item.fileURLs)
        } else if let imageData = item.imageTIFFData {
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
                fileURLStrings: item.fileURLStrings,
                capturedAt: Date()
            ),
            at: 0
        )

        saveClipboardHistory()
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.copied"
        )
    }

    func setClipboardOCRText(for id: UUID, text: String) {
        clipboardOCRCache[id] = text
    }

    func deleteClipboardItem(_ itemID: UUID) {
        clipboardHistory.removeAll { $0.id == itemID }
        pinnedClipboardItemIDs.remove(itemID)
        clipboardOCRCache.removeValue(forKey: itemID)
        saveClipboardHistory()
        savePinnedClipboardIDs()
    }

    func clearUnpinnedClipboardItems() -> StoreFeedback? {
        let originalCount = clipboardHistory.count
        let removedIDs = Set(clipboardHistory.filter { !pinnedClipboardItemIDs.contains($0.id) }.map(\.id))
        clipboardHistory.removeAll { !pinnedClipboardItemIDs.contains($0.id) }

        guard clipboardHistory.count != originalCount else {
            return nil
        }

        removedIDs.forEach { clipboardOCRCache.removeValue(forKey: $0) }
        saveClipboardHistory()
        return makeFeedback(
            titleKey: "feedback.clipboard.title",
            messageKey: "feedback.clipboard.clearedUnpinned"
        )
    }

    func clearClipboardHistory() -> StoreFeedback? {
        guard !clipboardHistory.isEmpty else {
            return nil
        }

        clipboardHistory.removeAll()
        pinnedClipboardItemIDs.removeAll()
        clipboardOCRCache.removeAll()
        saveClipboardHistory()
        savePinnedClipboardIDs()

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
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: localizationManager.effectiveLanguageIdentifier)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.capturedAt, relativeTo: Date())
    }

    // MARK: - Configuration

    func exportConfiguration() -> StoreFeedback? {
        do {
            let url = try configurationManager.exportConfiguration(currentConfiguration())
            return makeFeedback(
                titleKey: "feedback.configuration.title",
                messageKey: "feedback.configuration.exported",
                arguments: [url.path]
            )
        } catch AppConfigurationError.cancelled {
            return nil
        } catch {
            return feedbackForConfigurationError(error)
        }
    }

    func importConfiguration() -> StoreFeedback? {
        do {
            let importedConfiguration = try configurationManager.importConfiguration()
            apply(configuration: importedConfiguration)
            return makeFeedback(
                titleKey: "feedback.configuration.title",
                messageKey: "feedback.configuration.imported"
            )
        } catch AppConfigurationError.cancelled {
            return nil
        } catch {
            return feedbackForConfigurationError(error)
        }
    }

    private var filteredClipboardItems: [ClipboardItem] {
        let query = clipboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return clipboardHistory
        }

        return clipboardHistory.filter { item in
            if item.isFile {
                let fileLabel = localized("ui.clipboard.item.file").localizedCaseInsensitiveContains(query)
                let fileNameMatch = item.fileURLs.contains { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
                return fileLabel || fileNameMatch
            }

            if item.isImage {
                let imageLabel = localized("ui.clipboard.item.image").localizedCaseInsensitiveContains(query)
                let ocrMatch = clipboardOCRCache[item.id]?.localizedCaseInsensitiveContains(query) ?? false
                return imageLabel || ocrMatch
            }

            return item.content.localizedCaseInsensitiveContains(query)
        }
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
        saveClipboardHistory()
        savePinnedClipboardIDs()
    }

    private func captureClipboardImage(_ rawData: Data) {
        guard isClipboardMonitoringEnabled else {
            return
        }

        guard !rawData.isEmpty else {
            return
        }

        if clipboardHistory.first?.imageTIFFData == rawData {
            return
        }

        if let existingIndex = clipboardHistory.firstIndex(where: { $0.imageTIFFData == rawData }) {
            let existing = clipboardHistory.remove(at: existingIndex)
            clipboardHistory.insert(
                ClipboardItem(
                    id: existing.id,
                    content: "",
                    imageTIFFData: rawData,
                    capturedAt: Date()
                ),
                at: 0
            )
        } else {
            clipboardHistory.insert(
                ClipboardItem(content: "", imageTIFFData: rawData, capturedAt: Date()),
                at: 0
            )
        }

        normalizeClipboardState()
        saveClipboardHistory()
        savePinnedClipboardIDs()
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
        saveClipboardHistory()
        savePinnedClipboardIDs()
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

    private func saveClipboardHistory() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(clipboardHistory) {
            defaults.set(data, forKey: Keys.clipboardHistoryData)
        }
    }

    private func savePinnedClipboardIDs() {
        defaults.set(
            Array(pinnedClipboardItemIDs).map(\.uuidString).sorted(),
            forKey: Keys.pinnedClipboardIDs
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

    private func currentConfiguration() -> AppConfiguration {
        configurationManager.makeConfiguration(
            selectedLanguageCode: localizationManager.selectedLanguageCode,
            clipboardItems: clipboardHistory,
            clipboardPinnedIDs: Array(pinnedClipboardItemIDs).map(\.uuidString).sorted(),
            clipboardMonitoringEnabled: isClipboardMonitoringEnabled
        )
    }

    private func apply(configuration: AppConfiguration) {
        localizationManager.selectLanguage(code: configuration.selectedLanguageCode)

        if let importedClipboardItems = configuration.clipboardItems {
            clipboardHistory = importedClipboardItems
        }

        if let importedPinnedIDs = configuration.clipboardPinnedIDs {
            pinnedClipboardItemIDs = Set(importedPinnedIDs.compactMap(UUID.init(uuidString:)))
        }

        if let importedMonitoringEnabled = configuration.clipboardMonitoringEnabled {
            isClipboardMonitoringEnabled = importedMonitoringEnabled
            defaults.set(importedMonitoringEnabled, forKey: Keys.clipboardMonitoringEnabled)
        }

        normalizeClipboardState()
        saveClipboardHistory()
        savePinnedClipboardIDs()
        configureClipboardMonitoring()
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

    // MARK: - Update

    func checkForUpdates() async {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return
        }
        do {
            let release = try await updateService.fetchLatestRelease()
            if updateService.isNewerVersion(release.versionNumber, than: currentVersion) {
                pendingUpdateRelease = release
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
            // Fall back to opening the releases page
            if let url = URL(string: "https://github.com/mikewang817/MacBar/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func feedbackForConfigurationError(_ error: Error) -> StoreFeedback {
        let messageKey: String

        switch error {
        case AppConfigurationError.decodeFailed, AppConfigurationError.invalidPayload:
            messageKey = "feedback.configuration.error.invalidFile"
        case AppConfigurationError.writeFailed:
            messageKey = "feedback.configuration.error.writeFailed"
        case AppConfigurationError.readFailed:
            messageKey = "feedback.configuration.error.readFailed"
        default:
            messageKey = "feedback.configuration.error.generic"
        }

        return makeFeedback(
            titleKey: "feedback.configuration.title",
            messageKey: messageKey
        )
    }
}
