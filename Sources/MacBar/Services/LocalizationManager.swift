import Combine
import Foundation

struct LanguageOption: Identifiable, Hashable {
    let code: String
    let displayName: String
    let nativeName: String

    var id: String { code }

    var label: String {
        if nativeName.isEmpty || displayName == nativeName {
            return displayName
        }

        return "\(displayName) (\(nativeName))"
    }
}

final class LocalizationManager: ObservableObject {
    static let systemLanguageCode = "system"

    @Published private(set) var selectedLanguageCode: String
    @Published private(set) var effectiveLanguageIdentifier: String = "en"
    @Published private(set) var languageOptions: [LanguageOption] = []

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    private enum Keys {
        static let selectedLanguageCode = "macbar.selectedLanguageCode"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selectedLanguageCode = defaults.string(forKey: Keys.selectedLanguageCode) ?? Self.systemLanguageCode

        refreshEffectiveLanguage()
        refreshLanguageOptions()

        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshEffectiveLanguage()
                self?.refreshLanguageOptions()
            }
            .store(in: &cancellables)
    }

    var systemLanguageName: String {
        localizedLanguageDisplayName(for: preferredSystemLanguageIdentifier())
    }

    func selectLanguage(code: String) {
        guard selectedLanguageCode != code else {
            return
        }

        selectedLanguageCode = code
        defaults.set(code, forKey: Keys.selectedLanguageCode)
        refreshEffectiveLanguage()
        refreshLanguageOptions()
    }

    func localized(_ key: String) -> String {
        let localizedBundle = bundle(for: effectiveLanguageIdentifier)
        let resolved = localizedBundle.localizedString(forKey: key, value: nil, table: nil)

        if resolved != key {
            return resolved
        }

        let fallback = bundle(for: "en").localizedString(forKey: key, value: nil, table: nil)
        return fallback == key ? key : fallback
    }

    func localized(_ key: String, _ arguments: CVarArg...) -> String {
        localized(key, arguments: arguments)
    }

    func localized(_ key: String, arguments: [CVarArg]) -> String {
        let format = localized(key)
        return String(
            format: format,
            locale: Locale(identifier: effectiveLanguageIdentifier),
            arguments: arguments
        )
    }

    private func refreshLanguageOptions() {
        let codes = Set(availableLocalizationCodes())
        var selectionWasReset = false

        if selectedLanguageCode != Self.systemLanguageCode && !codes.contains(selectedLanguageCode) {
            selectedLanguageCode = Self.systemLanguageCode
            defaults.set(Self.systemLanguageCode, forKey: Keys.selectedLanguageCode)
            selectionWasReset = true
        }

        if selectionWasReset {
            refreshEffectiveLanguage()
        }

        let options = codes
            .map { code in
                LanguageOption(
                    code: code,
                    displayName: localizedLanguageDisplayName(for: code),
                    nativeName: nativeLanguageDisplayName(for: code)
                )
            }
            .sorted { lhs, rhs in
                lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        languageOptions = [
            LanguageOption(
                code: Self.systemLanguageCode,
                displayName: localized("ui.language.system"),
                nativeName: ""
            )
        ] + options
    }

    private func refreshEffectiveLanguage() {
        let requestedIdentifier: String

        if selectedLanguageCode == Self.systemLanguageCode {
            requestedIdentifier = preferredSystemLanguageIdentifier()
        } else {
            requestedIdentifier = selectedLanguageCode
        }

        effectiveLanguageIdentifier = resolvedLocalizationIdentifier(for: requestedIdentifier)
    }

    private func availableLocalizationCodes() -> [String] {
        Bundle.module.localizations.filter { $0.lowercased() != "base" }
    }

    private func preferredSystemLanguageIdentifier() -> String {
        Locale.preferredLanguages.first ?? "en"
    }

    private func localizedLanguageDisplayName(for identifier: String) -> String {
        let locale = Locale(identifier: effectiveLanguageIdentifier)

        if let localized = locale.localizedString(forIdentifier: identifier), !localized.isEmpty {
            return localized
        }

        if let code = Locale(identifier: identifier).language.languageCode?.identifier,
           let localized = locale.localizedString(forLanguageCode: code),
           !localized.isEmpty {
            return localized
        }

        return identifier
    }

    private func nativeLanguageDisplayName(for identifier: String) -> String {
        let locale = Locale(identifier: identifier)

        if let localized = locale.localizedString(forIdentifier: identifier), !localized.isEmpty {
            return localized
        }

        if let code = locale.language.languageCode?.identifier,
           let localized = locale.localizedString(forLanguageCode: code),
           !localized.isEmpty {
            return localized
        }

        return identifier
    }

    private func resolvedLocalizationIdentifier(for requestedIdentifier: String) -> String {
        let available = availableLocalizationCodes()
        guard !available.isEmpty else {
            return "en"
        }

        let lowercasedMap = Dictionary(uniqueKeysWithValues: available.map { ($0.lowercased(), $0) })
        let normalized = requestedIdentifier.replacingOccurrences(of: "_", with: "-")

        if let exact = lowercasedMap[normalized.lowercased()] {
            return exact
        }

        let locale = Locale(identifier: normalized)
        let languageCode = locale.language.languageCode?.identifier ?? normalized.split(separator: "-").first.map(String.init)

        if let languageCode, let directLanguageMatch = lowercasedMap[languageCode.lowercased()] {
            return directLanguageMatch
        }

        if let languageCode, languageCode.lowercased() == "zh" {
            let lower = normalized.lowercased()

            if lower.contains("hant"), let hant = lowercasedMap["zh-hant"] {
                return hant
            }

            if lower.contains("hans"), let hans = lowercasedMap["zh-hans"] {
                return hans
            }

            if let hans = lowercasedMap["zh-hans"] {
                return hans
            }
        }

        if let english = lowercasedMap["en"] {
            return english
        }

        return available[0]
    }

    private func bundle(for localizationIdentifier: String) -> Bundle {
        if let path = Bundle.module.path(forResource: localizationIdentifier, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle
        }

        return .module
    }
}
