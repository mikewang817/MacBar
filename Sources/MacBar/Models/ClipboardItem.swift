import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let imageTIFFData: Data?
    let imageStorageKey: String?
    let imageFingerprint: String?
    let fileURLStrings: [String]?
    let fileBookmarkDataByURLString: [String: Data]?
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        imageTIFFData: Data? = nil,
        imageStorageKey: String? = nil,
        imageFingerprint: String? = nil,
        fileURLStrings: [String]? = nil,
        fileBookmarkDataByURLString: [String: Data]? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.imageTIFFData = imageTIFFData
        self.imageStorageKey = imageStorageKey
        self.imageFingerprint = imageFingerprint
        self.fileURLStrings = fileURLStrings
        self.fileBookmarkDataByURLString = fileBookmarkDataByURLString
        self.capturedAt = capturedAt
    }

    var isImage: Bool {
        imageStorageKey != nil || imageTIFFData != nil
    }

    var isFile: Bool {
        fileURLStrings != nil && !fileURLStrings!.isEmpty
    }

    var fileURLs: [URL] {
        (fileURLStrings ?? []).compactMap { URL(string: $0) }
    }

    var primaryFileName: String? {
        fileURLs.first.map { $0.lastPathComponent }
    }

    var previewTitle: String {
        if isImage {
            return "Image"
        }

        let normalized = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if normalized.isEmpty {
            return content.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return normalized
    }

    var previewBody: String {
        if isImage {
            return ""
        }

        let compact = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return compact
    }

    var previewSubtitle: String {
        if isImage || isFile {
            return ""
        }

        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.count > 1 {
            let remainingText = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !remainingText.isEmpty {
                return remainingText
            }
        }

        let compact = previewBody
        return compact == previewTitle ? "" : compact
    }

    var characterCount: Int {
        if isImage {
            return 0
        }

        return content.count
    }

    var wordCount: Int {
        if isImage {
            return 0
        }

        var count = 0
        content.enumerateSubstrings(in: content.startIndex..., options: [.byWords, .localized]) { _, _, _, _ in
            count += 1
        }
        return count
    }

    func updatingCapturedAt(_ capturedAt: Date) -> ClipboardItem {
        ClipboardItem(
            id: id,
            content: content,
            imageTIFFData: imageTIFFData,
            imageStorageKey: imageStorageKey,
            imageFingerprint: imageFingerprint,
            fileURLStrings: fileURLStrings,
            fileBookmarkDataByURLString: fileBookmarkDataByURLString,
            capturedAt: capturedAt
        )
    }
}
