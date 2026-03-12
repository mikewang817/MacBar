import Foundation

enum AppVersion {
    // SwiftPM debug/app-package builds do not reliably expose our custom Info.plist
    // through Bundle.main, so keep a source-controlled fallback for in-app display
    // and update checks. Release packaging still copies Sources/MacBar/Info.plist.
    private static let fallbackShortVersion = "1.0.0"
    private static let fallbackBuildNumber = "2"

    static var shortVersion: String {
        bundleValue(for: "CFBundleShortVersionString") ?? fallbackShortVersion
    }

    static var buildNumber: String {
        bundleValue(for: "CFBundleVersion") ?? fallbackBuildNumber
    }

    static var displayString: String {
        "v\(shortVersion)"
    }

    private static func bundleValue(for key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
