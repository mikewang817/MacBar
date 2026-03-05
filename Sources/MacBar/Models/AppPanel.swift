import Foundation

enum AppPanel: String, CaseIterable, Identifiable {
    case clipboard

    var id: String { rawValue }
}
