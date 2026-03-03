import Foundation

enum SettingsCategory: String, CaseIterable, Hashable {
    case input
    case displayAndSound
    case connectivity
    case privacy
    case system

    func localizedTitle(using localizationManager: LocalizationManager) -> String {
        switch self {
        case .input:
            return localizationManager.localized("category.input")
        case .displayAndSound:
            return localizationManager.localized("category.displayAndSound")
        case .connectivity:
            return localizationManager.localized("category.connectivity")
        case .privacy:
            return localizationManager.localized("category.privacy")
        case .system:
            return localizationManager.localized("category.system")
        }
    }
}
