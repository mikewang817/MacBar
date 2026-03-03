import Foundation

struct SettingsQuickLink: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let keywords: [String]
    let urlCandidates: [String]

    func localizedTitle(using localizationManager: LocalizationManager) -> String {
        localizationManager.localized(titleKey)
    }
}

struct SettingsDestination: Identifiable, Hashable {
    let id: String
    let titleKey: String
    let subtitleKey: String
    let symbolName: String
    let category: SettingsCategory
    let keywords: [String]
    let urlCandidates: [String]
    let quickLinks: [SettingsQuickLink]

    init(
        id: String,
        titleKey: String,
        subtitleKey: String,
        symbolName: String,
        category: SettingsCategory,
        keywords: [String],
        urlCandidates: [String],
        quickLinks: [SettingsQuickLink] = []
    ) {
        self.id = id
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.symbolName = symbolName
        self.category = category
        self.keywords = keywords
        self.urlCandidates = urlCandidates
        self.quickLinks = quickLinks
    }

    func localizedTitle(using localizationManager: LocalizationManager) -> String {
        localizationManager.localized(titleKey)
    }

    func localizedSubtitle(using localizationManager: LocalizationManager) -> String {
        localizationManager.localized(subtitleKey)
    }

    func matches(query: String, localizationManager: LocalizationManager) -> Bool {
        relevanceScore(for: query, localizationManager: localizationManager) != nil
    }

    func relevanceScore(for query: String, localizationManager: LocalizationManager) -> Int? {
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedQuery.isEmpty else {
            return 0
        }

        let normalizedTitle = localizedTitle(using: localizationManager).lowercased()
        let normalizedSubtitle = localizedSubtitle(using: localizationManager).lowercased()

        if normalizedTitle == normalizedQuery {
            return 1000
        }

        if let index = normalizedTitle.range(of: normalizedQuery)?.lowerBound {
            let distance = normalizedTitle.distance(from: normalizedTitle.startIndex, to: index)
            return 800 - min(distance, 200)
        }

        if keywords.contains(where: { $0.lowercased() == normalizedQuery }) {
            return 700
        }

        if keywords.contains(where: { $0.lowercased().contains(normalizedQuery) }) {
            return 620
        }

        if quickLinks.contains(where: { $0.localizedTitle(using: localizationManager).lowercased() == normalizedQuery }) {
            return 610
        }

        if quickLinks.contains(where: { $0.localizedTitle(using: localizationManager).lowercased().contains(normalizedQuery) }) {
            return 600
        }

        if quickLinks.contains(where: { $0.keywords.contains(where: { $0.lowercased().contains(normalizedQuery) }) }) {
            return 580
        }

        if normalizedSubtitle.contains(normalizedQuery) {
            return 520
        }

        return nil
    }
}
