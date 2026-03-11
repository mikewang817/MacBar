import CryptoKit
import Foundation

final class ClipboardImageStore {
    private let fileManager: FileManager
    private let directoryURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.directoryURL = baseDirectory
            .appendingPathComponent(BuildInfo.appName, isDirectory: true)
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    func storageKey(for itemID: UUID) -> String {
        itemID.uuidString.lowercased()
    }

    func imageFingerprint(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    func loadImageData(for storageKey: String) -> Data? {
        try? Data(contentsOf: imageURL(for: storageKey), options: [.mappedIfSafe])
    }

    func saveImageData(_ data: Data, for storageKey: String) throws {
        try ensureDirectoryExists()
        try data.write(to: imageURL(for: storageKey), options: [.atomic])
    }

    func removeImage(for storageKey: String) {
        try? fileManager.removeItem(at: imageURL(for: storageKey))
    }

    func purgeUnusedImages(keeping storageKeys: Set<String>) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for url in urls where url.pathExtension.lowercased() == "tiff" {
            let storageKey = url.deletingPathExtension().lastPathComponent.lowercased()
            guard !storageKeys.contains(storageKey) else {
                continue
            }

            try? fileManager.removeItem(at: url)
        }
    }

    func fileExists(for storageKey: String) -> Bool {
        fileManager.fileExists(atPath: imageURL(for: storageKey).path)
    }

    func fileURL(for storageKey: String) -> URL {
        imageURL(for: storageKey)
    }

    func fileSize(for storageKey: String) -> Int64 {
        let imagePath = imageURL(for: storageKey).path
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: imagePath),
            let fileSize = attributes[.size] as? NSNumber
        else {
            return 0
        }

        return fileSize.int64Value
    }

    private func ensureDirectoryExists() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func imageURL(for storageKey: String) -> URL {
        directoryURL
            .appendingPathComponent(storageKey.lowercased(), isDirectory: false)
            .appendingPathExtension("tiff")
    }
}
