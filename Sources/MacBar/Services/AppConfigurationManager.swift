import AppKit
import Foundation
import UniformTypeIdentifiers

final class AppConfigurationManager {
    func makeConfiguration(
        favoriteIDs: Set<String>,
        selectedLanguageCode: String,
        clipboardItems: [ClipboardItem]? = nil,
        clipboardPinnedIDs: [String]? = nil,
        clipboardMonitoringEnabled: Bool? = nil,
        todoItems: [TodoItem]? = nil,
        todoPinnedIDs: [String]? = nil,
        todoAIModelSource: String? = nil,
        todoAIModelReference: String? = nil
    ) -> AppConfiguration {
        AppConfiguration(
            schemaVersion: AppConfiguration.currentSchemaVersion,
            favoriteIDs: Array(favoriteIDs).sorted(),
            selectedLanguageCode: selectedLanguageCode,
            clipboardItems: clipboardItems,
            clipboardPinnedIDs: clipboardPinnedIDs,
            clipboardMonitoringEnabled: clipboardMonitoringEnabled,
            todoItems: todoItems,
            todoPinnedIDs: todoPinnedIDs,
            todoAIModelSource: todoAIModelSource,
            todoAIModelReference: todoAIModelReference
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

        guard configuration.schemaVersion > 0,
              configuration.schemaVersion <= AppConfiguration.currentSchemaVersion else {
            throw AppConfigurationError.invalidPayload
        }

        return configuration
    }
}
