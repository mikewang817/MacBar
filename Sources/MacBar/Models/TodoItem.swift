import Foundation

enum TodoPriority: String, Codable, CaseIterable {
    case high
    case medium
    case low
}

struct TodoItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var notes: String?
    var priority: TodoPriority?
    var dueDate: Date?
    var isCompleted: Bool
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        priority: TodoPriority? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    var previewTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var previewBody: String {
        notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
