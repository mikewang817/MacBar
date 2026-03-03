import Foundation

struct AppConfiguration: Codable {
    let schemaVersion: Int
    let favoriteIDs: [String]
    let selectedLanguageCode: String

    static let currentSchemaVersion = 1
}

enum AppConfigurationError: Error {
    case cancelled
    case iCloudUnavailable
    case noRemoteConfiguration
    case invalidPayload
    case encodeFailed
    case decodeFailed
    case writeFailed
    case readFailed
}
