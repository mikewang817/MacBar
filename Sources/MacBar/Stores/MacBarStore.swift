import Combine
import Foundation

@MainActor
final class MacBarStore: ObservableObject {
    struct CategorySection: Identifiable {
        let category: SettingsCategory
        let items: [SettingsDestination]

        var id: String { category.rawValue }
    }

    @Published var searchText: String = ""
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var hasMouseDevice: Bool

    private let defaults: UserDefaults
    private let inputDeviceMonitor: InputDeviceMonitor
    private let localizationManager: LocalizationManager
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let favorites = "macbar.favoriteIDs"
    }

    init(
        defaults: UserDefaults = .standard,
        inputDeviceMonitor: InputDeviceMonitor = InputDeviceMonitor(),
        localizationManager: LocalizationManager = LocalizationManager()
    ) {
        self.defaults = defaults
        self.favoriteIDs = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
        self.inputDeviceMonitor = inputDeviceMonitor
        self.localizationManager = localizationManager
        self.hasMouseDevice = inputDeviceMonitor.isMouseConnected

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
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private func saveFavorites() {
        defaults.set(Array(favoriteIDs).sorted(), forKey: Keys.favorites)
    }
}
