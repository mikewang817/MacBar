import AppKit
import Foundation

struct SettingsOpenResult {
    enum Status {
        case success
        case fallback
        case failure
    }

    let status: Status
    let message: String
}

final class SettingsNavigator {
    private let workspace: NSWorkspace
    private let inputDeviceDetector: InputDeviceDetecting

    init(
        workspace: NSWorkspace = .shared,
        inputDeviceDetector: InputDeviceDetecting = InputDeviceDetector()
    ) {
        self.workspace = workspace
        self.inputDeviceDetector = inputDeviceDetector
    }

    func open(_ destination: SettingsDestination) -> SettingsOpenResult {
        if destination.id == "mouse", !inputDeviceDetector.hasMouseDevice() {
            if let trackpad = SettingsCatalog.byID["trackpad"], openFirstAvailableURL(trackpad.urlCandidates) {
                return SettingsOpenResult(
                    status: .fallback,
                    message: "未检测到鼠标设备，已打开触控板设置"
                )
            }

            if let bluetooth = SettingsCatalog.byID["bluetooth"], openFirstAvailableURL(bluetooth.urlCandidates) {
                return SettingsOpenResult(
                    status: .fallback,
                    message: "未检测到鼠标设备，已打开蓝牙设置"
                )
            }
        }

        if openFirstAvailableURL(destination.urlCandidates) {
            return SettingsOpenResult(
                status: .success,
                message: "已打开 \(destination.title)"
            )
        }

        guard let homeURL = URL(string: "x-apple.systempreferences:") else {
            return SettingsOpenResult(
                status: .failure,
                message: "无法构造系统设置链接"
            )
        }

        if workspace.open(homeURL) {
            return SettingsOpenResult(
                status: .fallback,
                message: "已打开系统设置主页，请手动进入“\(destination.title)”"
            )
        }

        return SettingsOpenResult(
            status: .failure,
            message: "打开失败，请检查系统设置是否可用"
        )
    }

    func openSystemSettingsHome() -> SettingsOpenResult {
        guard let homeURL = URL(string: "x-apple.systempreferences:") else {
            return SettingsOpenResult(status: .failure, message: "系统设置链接无效")
        }

        if workspace.open(homeURL) {
            return SettingsOpenResult(status: .success, message: "已打开系统设置主页")
        }

        return SettingsOpenResult(status: .failure, message: "无法打开系统设置主页")
    }

    private func openFirstAvailableURL(_ candidates: [String]) -> Bool {
        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                continue
            }

            if workspace.open(url) {
                return true
            }
        }

        return false
    }
}
