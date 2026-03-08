import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

@MainActor
final class LaunchAtLoginService {
    private let appService = SMAppService.mainApp

    func currentStatus() -> LaunchAtLoginStatus {
        guard Bundle.main.bundleURL.pathExtension.lowercased() == "app" else {
            return .unavailable
        }

        switch appService.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    @discardableResult
    func setEnabled(_ isEnabled: Bool) -> LaunchAtLoginStatus {
        let statusBeforeChange = currentStatus()

        guard statusBeforeChange != .unavailable else {
            return .unavailable
        }

        do {
            if isEnabled {
                if statusBeforeChange != .enabled {
                    try appService.register()
                }
            } else if statusBeforeChange == .enabled || statusBeforeChange == .requiresApproval {
                try appService.unregister()
            }
        } catch {
            return currentStatus()
        }

        return currentStatus()
    }
}
