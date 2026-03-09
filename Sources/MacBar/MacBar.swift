import Foundation

enum BuildInfo {
    static let appName = "MacBar"
    static let bundleIdentifier = "app.macbar.macbar"
    static let preferencesSuiteName = bundleIdentifier
    static let legacyPreferencesSuiteNames = [
        "com.mikewang817.MacBar",
        "MacBar"
    ]
    static let pasteboardMarkerType = "\(bundleIdentifier).pasteboard-source"
    static let isAppStoreDistribution = true
    static let supportsExternalUpdates = !isAppStoreDistribution
}
