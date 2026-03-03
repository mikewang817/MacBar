import Foundation

enum AppPanel: String, CaseIterable, Identifiable {
    case settings
    case clipboard
    case todo

    var id: String { rawValue }
}
