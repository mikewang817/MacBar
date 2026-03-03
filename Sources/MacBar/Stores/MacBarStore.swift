import Combine
import Foundation

struct StoreFeedback {
    let title: String
    let message: String
}

@MainActor
final class MacBarStore: ObservableObject {
    struct CategorySection: Identifiable {
        let category: SettingsCategory
        let items: [SettingsDestination]

        var id: String { category.rawValue }
    }

    @Published var activePanel: AppPanel = .settings
    @Published var searchText: String = ""
    @Published var clipboardSearchText: String = ""
    @Published var todoSearchText: String = ""
    @Published var todoInputText: String = ""
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var hasMouseDevice: Bool
    @Published private(set) var clipboardHistory: [ClipboardItem]
    @Published private(set) var pinnedClipboardItemIDs: Set<UUID>
    @Published private(set) var isClipboardMonitoringEnabled: Bool
    @Published private(set) var todoItems: [TodoItem]
    @Published private(set) var pinnedTodoItemIDs: Set<UUID>

    private let defaults: UserDefaults
    private let inputDeviceMonitor: InputDeviceMonitor
    private let localizationManager: LocalizationManager
    private let configurationManager: AppConfigurationManager
    private let clipboardMonitor: ClipboardMonitor
    private var cancellables: Set<AnyCancellable> = []

    private let maxUnpinnedClipboardItems = 200
    private let maxClipboardCharacterCount = 20_000
    private let maxClipboardImageBytes = 8_000_000

    private enum Keys {
        static let favorites = "macbar.favoriteIDs"
        static let clipboardHistoryData = "macbar.clipboardHistoryData"
        static let pinnedClipboardIDs = "macbar.pinnedClipboardIDs"
        static let clipboardMonitoringEnabled = "macbar.clipboardMonitoringEnabled"
        static let todoItemsData = "macbar.todoItemsData"
        static let pinnedTodoIDs = "macbar.pinnedTodoIDs"
    }

    init(
        defaults: UserDefaults = .standard,
        inputDeviceMonitor: InputDeviceMonitor = InputDeviceMonitor(),
        localizationManager: LocalizationManager = LocalizationManager(),
        configurationManager: AppConfigurationManager = AppConfigurationManager(),
        clipboardMonitor: ClipboardMonitor = ClipboardMonitor()
    ) {
        self.defaults = defaults
        self.favoriteIDs = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
        self.inputDeviceMonitor = inputDeviceMonitor
        self.localizationManager = localizationManager
        self.configurationManager = configurationManager
        self.clipboardMonitor = clipboardMonitor
        self.hasMouseDevice = inputDeviceMonitor.isMouseConnected
        self.clipboardHistory = Self.loadClipboardHistory(defaults: defaults)
        self.pinnedClipboardItemIDs = Self.loadPinnedClipboardIDs(defaults: defaults)
        self.isClipboardMonitoringEnabled = defaults.object(forKey: Keys.clipboardMonitoringEnabled) as? Bool ?? true
        self.todoItems = Self.loadTodoItems(defaults: defaults)
        self.pinnedTodoItemIDs = Self.loadPinnedTodoIDs(defaults: defaults)

        normalizeClipboardState()
        normalizeTodoState()
        configureClipboardMonitoring()

        inputDeviceMonitor.$isMouseConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnected in
                self?.hasMouseDevice = isConnected
            }
            .store(in: &cancellables)

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

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isClipboardSearching: Bool {
        !clipboardSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var visibleDestinations: [SettingsDestination] {
        SettingsCatalog.all.filter { destination in
            hasMouseDevice || destination.id != "mouse"
        }
    }

    var searchResults: [SettingsDestination] {
        let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return visibleDestinations
            .compactMap { destination -> (destination: SettingsDestination, relevance: Int)? in
                guard let relevance = destination.relevanceScore(
                    for: normalizedQuery,
                    localizationManager: localizationManager
                ) else {
                    return nil
                }

                return (destination: destination, relevance: relevance)
            }
            .sorted { lhs, rhs in
                if lhs.relevance != rhs.relevance {
                    return lhs.relevance > rhs.relevance
                }

                if isFavorite(lhs.destination.id) != isFavorite(rhs.destination.id) {
                    return isFavorite(lhs.destination.id)
                }

                return localizedTitle(for: lhs.destination) < localizedTitle(for: rhs.destination)
            }
            .map(\.destination)
    }

    var favoriteDestinations: [SettingsDestination] {
        orderedDestinations(fromIDs: Array(favoriteIDs))
            .sorted { localizedTitle(for: $0) < localizedTitle(for: $1) }
    }

    var groupedSearchResults: [CategorySection] {
        let source = isSearching
            ? searchResults
            : visibleDestinations.sorted { lhs, rhs in
                if isFavorite(lhs.id) != isFavorite(rhs.id) {
                    return isFavorite(lhs.id)
                }

                return localizedTitle(for: lhs) < localizedTitle(for: rhs)
            }

        return SettingsCategory.allCases.compactMap { category in
            let items = source.filter { $0.category == category }
            guard !items.isEmpty else {
                return nil
            }

            return CategorySection(category: category, items: items)
        }
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

    // MARK: - Todo Computed Properties

    var isTodoSearching: Bool {
        !todoSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var pinnedTodoItems: [TodoItem] {
        filteredTodoItems.filter { pinnedTodoItemIDs.contains($0.id) }
    }

    var recentTodoItems: [TodoItem] {
        filteredTodoItems.filter { !pinnedTodoItemIDs.contains($0.id) }
    }

    private var filteredTodoItems: [TodoItem] {
        let query = todoSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return todoItems }
        return todoItems.filter { item in
            item.title.localizedCaseInsensitiveContains(query)
                || (item.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    func localizedTitle(for destination: SettingsDestination) -> String {
        destination.localizedTitle(using: localizationManager)
    }

    func localizedSubtitle(for destination: SettingsDestination) -> String {
        destination.localizedSubtitle(using: localizationManager)
    }

    func localizedTitle(for category: SettingsCategory) -> String {
        category.localizedTitle(using: localizationManager)
    }

    func localized(_ key: String) -> String {
        localizationManager.localized(key)
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localizationManager.localized(key, arguments: arguments)
    }

    func isFavorite(_ destinationID: String) -> Bool {
        favoriteIDs.contains(destinationID)
    }

    func toggleFavorite(_ destinationID: String) {
        if favoriteIDs.contains(destinationID) {
            favoriteIDs.remove(destinationID)
        } else {
            favoriteIDs.insert(destinationID)
        }

        saveFavorites()
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
        if let imageData = item.imageTIFFData {
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

    func deleteClipboardItem(_ itemID: UUID) {
        clipboardHistory.removeAll { $0.id == itemID }
        pinnedClipboardItemIDs.remove(itemID)
        saveClipboardHistory()
        savePinnedClipboardIDs()
    }

    func clearUnpinnedClipboardItems() -> StoreFeedback? {
        let originalCount = clipboardHistory.count
        clipboardHistory.removeAll { !pinnedClipboardItemIDs.contains($0.id) }

        guard clipboardHistory.count != originalCount else {
            return nil
        }

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

    // MARK: - Todo Methods

    func isTodoItemPinned(_ itemID: UUID) -> Bool {
        pinnedTodoItemIDs.contains(itemID)
    }

    func toggleTodoItemPinned(_ itemID: UUID) {
        if pinnedTodoItemIDs.contains(itemID) {
            pinnedTodoItemIDs.remove(itemID)
        } else {
            pinnedTodoItemIDs.insert(itemID)
        }
        normalizeTodoState()
        saveTodoItems()
        savePinnedTodoIDs()
    }

    @discardableResult
    func addTodoItem(title: String) -> StoreFeedback? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let item = TodoItem(title: trimmed)
        todoItems.insert(item, at: 0)
        saveTodoItems()
        return makeFeedback(
            titleKey: "feedback.todo.title",
            messageKey: "feedback.todo.added"
        )
    }

    func toggleTodoItemCompleted(_ itemID: UUID) {
        guard let index = todoItems.firstIndex(where: { $0.id == itemID }) else { return }
        todoItems[index].isCompleted.toggle()
        saveTodoItems()
    }

    func updateTodoItem(
        _ itemID: UUID,
        title: String? = nil,
        notes: String? = nil,
        priority: TodoPriority?? = nil,
        dueDate: Date?? = nil
    ) {
        guard let index = todoItems.firstIndex(where: { $0.id == itemID }) else { return }
        if let title { todoItems[index].title = title }
        if let notes { todoItems[index].notes = notes }
        if let priority { todoItems[index].priority = priority }
        if let dueDate { todoItems[index].dueDate = dueDate }
        saveTodoItems()
    }

    func deleteTodoItem(_ itemID: UUID) {
        todoItems.removeAll { $0.id == itemID }
        pinnedTodoItemIDs.remove(itemID)
        saveTodoItems()
        savePinnedTodoIDs()
    }

    func clearCompletedTodoItems() -> StoreFeedback? {
        let originalCount = todoItems.count
        todoItems.removeAll { $0.isCompleted && !pinnedTodoItemIDs.contains($0.id) }
        guard todoItems.count != originalCount else { return nil }
        normalizeTodoState()
        saveTodoItems()
        savePinnedTodoIDs()
        return makeFeedback(
            titleKey: "feedback.todo.title",
            messageKey: "feedback.todo.clearedCompleted"
        )
    }

    func todoDueDateLabel(for item: TodoItem) -> String? {
        guard let dueDate = item.dueDate else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: localizationManager.effectiveLanguageIdentifier)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: dueDate, relativeTo: Date())
    }

    func todoCreatedAtLabel(for item: TodoItem) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: localizationManager.effectiveLanguageIdentifier)
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
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
            if item.isImage {
                return localized("ui.clipboard.item.image").localizedCaseInsensitiveContains(query)
            }

            return item.content.localizedCaseInsensitiveContains(query)
        }
    }

    private func orderedDestinations(fromIDs ids: [String]) -> [SettingsDestination] {
        var ordered: [SettingsDestination] = []

        for id in ids {
            guard let destination = SettingsCatalog.byID[id] else {
                continue
            }

            if !hasMouseDevice && destination.id == "mouse" {
                continue
            }

            ordered.append(destination)
        }

        return ordered
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

        let captured = String(trimmed.prefix(maxClipboardCharacterCount))
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

        guard !rawData.isEmpty, rawData.count <= maxClipboardImageBytes else {
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

    private func normalizeClipboardState() {
        let existingIDs = Set(clipboardHistory.map(\.id))
        pinnedClipboardItemIDs = pinnedClipboardItemIDs.intersection(existingIDs)

        var normalized: [ClipboardItem] = []
        var seenIDs: Set<UUID> = []
        var unpinnedCount = 0

        for item in clipboardHistory {
            guard !seenIDs.contains(item.id) else {
                continue
            }
            seenIDs.insert(item.id)

            if pinnedClipboardItemIDs.contains(item.id) {
                normalized.append(item)
                continue
            }

            guard unpinnedCount < maxUnpinnedClipboardItems else {
                continue
            }

            normalized.append(item)
            unpinnedCount += 1
        }

        clipboardHistory = normalized
    }

    private func saveFavorites() {
        defaults.set(Array(favoriteIDs).sorted(), forKey: Keys.favorites)
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

    private func saveTodoItems() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(todoItems) {
            defaults.set(data, forKey: Keys.todoItemsData)
        }
    }

    private func savePinnedTodoIDs() {
        defaults.set(
            Array(pinnedTodoItemIDs).map(\.uuidString).sorted(),
            forKey: Keys.pinnedTodoIDs
        )
    }

    private static func loadTodoItems(defaults: UserDefaults) -> [TodoItem] {
        guard let data = defaults.data(forKey: Keys.todoItemsData) else { return [] }
        return (try? JSONDecoder().decode([TodoItem].self, from: data)) ?? []
    }

    private static func loadPinnedTodoIDs(defaults: UserDefaults) -> Set<UUID> {
        let rawIDs = defaults.stringArray(forKey: Keys.pinnedTodoIDs) ?? []
        return Set(rawIDs.compactMap(UUID.init(uuidString:)))
    }

    private func normalizeTodoState() {
        let existingIDs = Set(todoItems.map(\.id))
        pinnedTodoItemIDs = pinnedTodoItemIDs.intersection(existingIDs)
    }

    private func currentConfiguration() -> AppConfiguration {
        configurationManager.makeConfiguration(
            favoriteIDs: favoriteIDs,
            selectedLanguageCode: localizationManager.selectedLanguageCode,
            clipboardItems: clipboardHistory,
            clipboardPinnedIDs: Array(pinnedClipboardItemIDs).map(\.uuidString).sorted(),
            clipboardMonitoringEnabled: isClipboardMonitoringEnabled,
            todoItems: todoItems,
            todoPinnedIDs: Array(pinnedTodoItemIDs).map(\.uuidString).sorted()
        )
    }

    private func apply(configuration: AppConfiguration) {
        let validDestinationIDs = Set(SettingsCatalog.byID.keys)
        favoriteIDs = Set(configuration.favoriteIDs.filter { validDestinationIDs.contains($0) })
        saveFavorites()
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

        if let importedTodoItems = configuration.todoItems {
            todoItems = importedTodoItems
        }
        if let importedTodoPinnedIDs = configuration.todoPinnedIDs {
            pinnedTodoItemIDs = Set(importedTodoPinnedIDs.compactMap(UUID.init(uuidString:)))
        }
        normalizeTodoState()
        saveTodoItems()
        savePinnedTodoIDs()
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
