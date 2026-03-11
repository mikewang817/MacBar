import AppKit
import Foundation

@MainActor
final class AirDropService: NSObject, NSSharingServiceDelegate {
    private let fileManager = FileManager.default
    private var activeService: NSSharingService?
    private var stagedDirectoryURLs: [URL] = []

    func canSendFiles(_ fileURLs: [URL]) -> Bool {
        canPerform(with: fileURLs.map { $0 as Any })
    }

    func canSendImage(_ image: NSImage) -> Bool {
        canPerform(with: [image])
    }

    @discardableResult
    func sendFiles(_ fileURLs: [URL]) -> Bool {
        let stagedFileURLs = stageFilesForSharing(fileURLs)
        guard !stagedFileURLs.isEmpty else {
            return false
        }

        return perform(with: stagedFileURLs.map { $0 as Any })
    }

    @discardableResult
    func sendImage(_ image: NSImage) -> Bool {
        perform(with: [image])
    }

    private func makeService() -> NSSharingService? {
        let service = NSSharingService(named: .sendViaAirDrop)
        service?.delegate = self
        return service
    }

    private func canPerform(with items: [Any]) -> Bool {
        guard !items.isEmpty, let service = makeService() else {
            return false
        }

        return service.canPerform(withItems: items)
    }

    private func perform(with items: [Any]) -> Bool {
        guard !items.isEmpty, let service = makeService(), service.canPerform(withItems: items) else {
            cleanupStagedFilesIfNeeded()
            return false
        }

        activeService = service
        service.perform(withItems: items)
        return true
    }

    private func stageFilesForSharing(_ fileURLs: [URL]) -> [URL] {
        cleanupStagedFilesIfNeeded()

        guard !fileURLs.isEmpty else {
            return []
        }

        let stagingDirectoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("MacBar-AirDrop", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        do {
            try fileManager.createDirectory(at: stagingDirectoryURL, withIntermediateDirectories: true)
        } catch {
            return []
        }

        var stagedFileURLs: [URL] = []

        for fileURL in fileURLs {
            let destinationURL = uniqueDestinationURL(
                for: fileURL.lastPathComponent,
                in: stagingDirectoryURL
            )

            do {
                try fileManager.copyItem(at: fileURL, to: destinationURL)
                stagedFileURLs.append(destinationURL)
            } catch {
                cleanup(directoryURL: stagingDirectoryURL)
                return []
            }
        }

        stagedDirectoryURLs.append(stagingDirectoryURL)
        return stagedFileURLs
    }

    private func uniqueDestinationURL(for filename: String, in directoryURL: URL) -> URL {
        let baseURL = directoryURL.appendingPathComponent(filename)
        guard !fileManager.fileExists(atPath: baseURL.path) else {
            let stem = baseURL.deletingPathExtension().lastPathComponent
            let ext = baseURL.pathExtension
            var index = 2

            while true {
                let candidateFilename = ext.isEmpty
                    ? "\(stem)-\(index)"
                    : "\(stem)-\(index).\(ext)"
                let candidateURL = directoryURL.appendingPathComponent(candidateFilename)
                if !fileManager.fileExists(atPath: candidateURL.path) {
                    return candidateURL
                }
                index += 1
            }
        }

        return baseURL
    }

    private func cleanupStagedFilesIfNeeded() {
        let directoryURLs = stagedDirectoryURLs
        stagedDirectoryURLs.removeAll()

        for directoryURL in directoryURLs {
            cleanup(directoryURL: directoryURL)
        }
    }

    private func cleanup(directoryURL: URL) {
        try? fileManager.removeItem(at: directoryURL)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finishSharing(for: sharingService)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        finishSharing(for: sharingService)
    }

    private func finishSharing(for sharingService: NSSharingService) {
        guard activeService === sharingService else {
            return
        }

        activeService = nil
        cleanupStagedFilesIfNeeded()
    }
}
