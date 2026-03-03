import Foundation

struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String
    let imageTIFFData: Data?
    let capturedAt: Date

    init(
        id: UUID = UUID(),
        content: String,
        imageTIFFData: Data? = nil,
        capturedAt: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.imageTIFFData = imageTIFFData
        self.capturedAt = capturedAt
    }

    var isImage: Bool {
        imageTIFFData != nil
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
}
