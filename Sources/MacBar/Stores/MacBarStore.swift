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
    @Published var statusMessage: String = ""

    private let defaults: UserDefaults
    private let inputDeviceMonitor: InputDeviceMonitor
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let favorites = "macbar.favoriteIDs"
    }

    init(
        defaults: UserDefaults = .standard,
        inputDeviceMonitor: InputDeviceMonitor = InputDeviceMonitor()
    ) {
        self.defaults = defaults
        self.favoriteIDs = Set(defaults.stringArray(forKey: Keys.favorites) ?? [])
        self.inputDeviceMonitor = inputDeviceMonitor
        self.hasMouseDevice = inputDeviceMonitor.isMouseConnected

        inputDeviceMonitor.$isMouseConnected
            .receive(on: RunLoop.main)
            .sink { [weak self] isConnected in
                self?.hasMouseDevice = isConnected
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
                guard let relevance = destination.relevanceScore(for: normalizedQuery) else {
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

                return lhs.destination.title < rhs.destination.title
            }
            .map(\.destination)
    }

    var favoriteDestinations: [SettingsDestination] {
        orderedDestinations(fromIDs: Array(favoriteIDs))
            .sorted { $0.title < $1.title }
    }

    var groupedSearchResults: [CategorySection] {
        let source = isSearching
            ? searchResults
            : visibleDestinations.sorted { lhs, rhs in
                if isFavorite(lhs.id) != isFavorite(rhs.id) {
                    return isFavorite(lhs.id)
                }

                return lhs.title < rhs.title
            }

        return SettingsCategory.allCases.compactMap { category in
            let items = source.filter { $0.category == category }
            guard !items.isEmpty else {
                return nil
            }

            return CategorySection(category: category, items: items)
        }
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

    func setStatus(_ message: String) {
        statusMessage = message
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
