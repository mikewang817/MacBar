import Foundation

enum AppPanel: String, CaseIterable, Identifiable {
    case clipboard
    case settings

    var id: String { rawValue }
}
