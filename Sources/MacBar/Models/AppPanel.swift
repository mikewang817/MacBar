import Foundation

enum AppPanel: String, CaseIterable, Identifiable {
    case settings
    case clipboard

    var id: String { rawValue }
}
