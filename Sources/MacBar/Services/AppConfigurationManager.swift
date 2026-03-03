import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppConfigurationManager: NSObject {
    static let didReceiveRemoteConfigurationNotification = Notification.Name("macbar.didReceiveRemoteConfiguration")

    private let cloudStore: NSUbiquitousKeyValueStore
    private let notificationCenter: NotificationCenter
    private let fileManager: FileManager
    private let cloudConfigurationKey = "macbar.configuration.v1"

    init(
        cloudStore: NSUbiquitousKeyValueStore = .default,
        notificationCenter: NotificationCenter = .default,
        fileManager: FileManager = .default
    ) {
        self.cloudStore = cloudStore
        self.notificationCenter = notificationCenter
        self.fileManager = fileManager
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(handleCloudStoreChanged(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
    }

    deinit {
        notificationCenter.removeObserver(
            self,
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloudStore
        )
    }

    func makeConfiguration(favoriteIDs: Set<String>, selectedLanguageCode: String) -> AppConfiguration {
        AppConfiguration(
            schemaVersion: AppConfiguration.currentSchemaVersion,
            favoriteIDs: Array(favoriteIDs).sorted(),
            selectedLanguageCode: selectedLanguageCode
        )
    }

    @MainActor
    func exportConfiguration(_ configuration: AppConfiguration) throws -> URL {
        let panel = NSSavePanel()
        panel.title = "Export MacBar Configuration"
        panel.nameFieldStringValue = "MacBar-Configuration.json"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType.json]

        guard panel.runModal() == .OK else {
            throw AppConfigurationError.cancelled
        }

        guard let destinationURL = panel.url else {
            throw AppConfigurationError.writeFailed
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(configuration) else {
            throw AppConfigurationError.encodeFailed
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
            return destinationURL
        } catch {
            throw AppConfigurationError.writeFailed
        }
    }

    @MainActor
    func importConfiguration() throws -> AppConfiguration {
        let panel = NSOpenPanel()
        panel.title = "Import MacBar Configuration"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType.json]

        guard panel.runModal() == .OK else {
            throw AppConfigurationError.cancelled
        }

        guard let sourceURL = panel.url else {
            throw AppConfigurationError.readFailed
        }

        let data: Data
        do {
            data = try Data(contentsOf: sourceURL)
        } catch {
            throw AppConfigurationError.readFailed
        }

        let decoder = JSONDecoder()
        guard let configuration = try? decoder.decode(AppConfiguration.self, from: data) else {
            throw AppConfigurationError.decodeFailed
        }

        guard configuration.schemaVersion == AppConfiguration.currentSchemaVersion else {
            throw AppConfigurationError.invalidPayload
        }

        return configuration
    }

    func syncToICloud(_ configuration: AppConfiguration) throws {
        guard isICloudAvailable else {
            throw AppConfigurationError.iCloudUnavailable
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(configuration) else {
            throw AppConfigurationError.encodeFailed
        }

        cloudStore.set(data, forKey: cloudConfigurationKey)
        _ = cloudStore.synchronize()
    }

    func syncFromICloud() throws -> AppConfiguration {
        guard isICloudAvailable else {
            throw AppConfigurationError.iCloudUnavailable
        }

        _ = cloudStore.synchronize()

        guard let data = cloudStore.data(forKey: cloudConfigurationKey) else {
            throw AppConfigurationError.noRemoteConfiguration
        }

        let decoder = JSONDecoder()
        guard let configuration = try? decoder.decode(AppConfiguration.self, from: data) else {
            throw AppConfigurationError.decodeFailed
        }

        guard configuration.schemaVersion == AppConfiguration.currentSchemaVersion else {
            throw AppConfigurationError.invalidPayload
        }

        return configuration
    }

    var isICloudAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    @objc
    private func handleCloudStoreChanged(_ notification: Notification) {
        guard let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
              changedKeys.contains(cloudConfigurationKey) else {
            return
        }

        notificationCenter.post(
            name: Self.didReceiveRemoteConfigurationNotification,
            object: self
        )
    }
}
