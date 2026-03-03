import Foundation

final class SystemSettingsTerminology {
    static let supportedHighPopulationLanguageCodes: Set<String> = [
        "ar", "ca", "cs", "da", "de", "el", "en", "es", "fi", "fr",
        "he", "hi", "hr", "hu", "id", "it", "ja", "ko", "ms", "nl",
        "no", "pl", "pt", "ro", "ru", "sk", "sv", "th", "tr", "uk",
        "vi", "zh-Hans", "zh-Hant"
    ]

    private let fileManager: FileManager
    private let extensionsRootPath = "/System/Library/ExtensionKit/Extensions"
    private var cacheByLocalizationKey: [String: [String: String]] = [:]

    private struct Source {
        let extensionBundleName: String
        let tableFileName: String
        let tableKey: String

        func filePath(root: String) -> String {
            "\(root)/\(extensionBundleName)/Contents/Resources/\(tableFileName)"
        }
    }

    private let sourceByLocalizationKey: [String: Source] = [
        "destination.mouse.title": Source(
            extensionBundleName: "MouseExtension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.trackpad.title": Source(
            extensionBundleName: "TrackpadExtension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.keyboard.title": Source(
            extensionBundleName: "KeyboardSettings.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.displays.title": Source(
            extensionBundleName: "DisplaysExt.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.sound.title": Source(
            extensionBundleName: "Sound.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.wifi.title": Source(
            extensionBundleName: "Wi-Fi.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.bluetooth.title": Source(
            extensionBundleName: "Bluetooth.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.network.title": Source(
            extensionBundleName: "Network.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.notifications.title": Source(
            extensionBundleName: "NotificationsSettings.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.privacySecurity.title": Source(
            extensionBundleName: "SecurityPrivacyExtension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.accessibility.title": Source(
            extensionBundleName: "AccessibilitySettingsExtension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.controlCenter.title": Source(
            extensionBundleName: "ControlCenterSettings.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.battery.title": Source(
            extensionBundleName: "PowerPreferences.appex",
            tableFileName: "BatteryUI.loctable",
            tableKey: "BATTERY_PREF_TITLE"
        ),
        "destination.loginItems.title": Source(
            extensionBundleName: "LoginItems.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.dateTime.title": Source(
            extensionBundleName: "DateAndTime Extension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        ),
        "destination.softwareUpdate.title": Source(
            extensionBundleName: "SoftwareUpdateSettingsExtension.appex",
            tableFileName: "InfoPlist.loctable",
            tableKey: "CFBundleDisplayName"
        )
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func localizedValue(for key: String, languageIdentifier: String) -> String? {
        guard let source = sourceByLocalizationKey[key] else {
            return nil
        }

        let values = localizedValues(for: key, source: source)
        guard !values.isEmpty else {
            return nil
        }

        for candidate in languageCandidates(for: languageIdentifier) {
            if let matched = values[candidate], !matched.isEmpty {
                return matched
            }
        }

        return values["en"] ?? values.values.first
    }

    private func localizedValues(for key: String, source: Source) -> [String: String] {
        if let cached = cacheByLocalizationKey[key] {
            return cached
        }

        let path = source.filePath(root: extensionsRootPath)
        guard fileManager.fileExists(atPath: path),
              let data = fileManager.contents(atPath: path),
              let rawTable = try? PropertyListSerialization.propertyList(
                  from: data,
                  options: [],
                  format: nil
              ) as? [String: Any] else {
            cacheByLocalizationKey[key] = [:]
            return [:]
        }

        var valuesByLanguageCode: [String: String] = [:]
        for (localeCode, rawEntry) in rawTable {
            guard let appLanguageCode = normalizedLanguageCode(fromSystemLocaleCode: localeCode),
                  let entry = rawEntry as? [String: Any],
                  let value = entry[source.tableKey] as? String,
                  !value.isEmpty else {
                continue
            }

            valuesByLanguageCode[appLanguageCode] = value
        }

        cacheByLocalizationKey[key] = valuesByLanguageCode
        return valuesByLanguageCode
    }

    private func normalizedLanguageCode(fromSystemLocaleCode code: String) -> String? {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        let lower = normalized.lowercased()

        if lower == "locprovenance" {
            return nil
        }

        switch lower {
        case "zh-cn":
            return "zh-Hans"
        case "zh-hk", "zh-tw":
            return "zh-Hant"
        default:
            break
        }

        if lower.hasPrefix("en-") {
            return "en"
        }
        if lower.hasPrefix("es-") {
            return "es"
        }
        if lower.hasPrefix("fr-") {
            return "fr"
        }
        if lower.hasPrefix("pt-") {
            return "pt"
        }

        return lower
    }

    private func languageCandidates(for identifier: String) -> [String] {
        var candidates: [String] = []

        let normalized = normalizeAppLanguageCode(identifier)
        appendCandidate(normalized, to: &candidates)

        let locale = Locale(identifier: normalized)
        if let base = locale.language.languageCode?.identifier {
            appendCandidate(normalizeAppLanguageCode(base), to: &candidates)
        }

        if normalized == "zh" {
            appendCandidate("zh-Hans", to: &candidates)
            appendCandidate("zh-Hant", to: &candidates)
        }

        let lowerNormalized = normalized.lowercased()
        if lowerNormalized.contains("zh-hant") {
            appendCandidate("zh-Hant", to: &candidates)
        }
        if lowerNormalized.contains("zh-hans") {
            appendCandidate("zh-Hans", to: &candidates)
        }

        appendCandidate("en", to: &candidates)
        return candidates
    }

    private func appendCandidate(_ candidate: String, to candidates: inout [String]) {
        let normalized = normalizeAppLanguageCode(candidate)
        guard !normalized.isEmpty, !candidates.contains(normalized) else {
            return
        }

        candidates.append(normalized)
    }

    private func normalizeAppLanguageCode(_ code: String) -> String {
        let normalized = code.replacingOccurrences(of: "_", with: "-").lowercased()

        switch normalized {
        case "zh-hans":
            return "zh-Hans"
        case "zh-hant":
            return "zh-Hant"
        default:
            return normalized
        }
    }
}
