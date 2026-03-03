import Foundation

enum SettingsCategory: String, CaseIterable, Hashable {
    case input
    case displayAndSound
    case connectivity
    case privacy
    case system

    var title: String {
        switch self {
        case .input:
            return "输入设备"
        case .displayAndSound:
            return "显示与声音"
        case .connectivity:
            return "连接"
        case .privacy:
            return "隐私与安全"
        case .system:
            return "系统"
        }
    }
}
