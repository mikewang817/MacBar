import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let imageTIFFData: Data?
    let fileURLStrings: [String]?
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        imageTIFFData: Data? = nil,
        fileURLStrings: [String]? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.imageTIFFData = imageTIFFData
        self.fileURLStrings = fileURLStrings
        self.capturedAt = capturedAt
    }

    var isImage: Bool {
        imageTIFFData != nil
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
}
