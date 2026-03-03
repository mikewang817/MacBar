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
    private let localizationManager: LocalizationManager

    init(
        workspace: NSWorkspace = .shared,
        inputDeviceDetector: InputDeviceDetecting = InputDeviceDetector(),
        localizationManager: LocalizationManager = LocalizationManager()
    ) {
        self.workspace = workspace
        self.inputDeviceDetector = inputDeviceDetector
        self.localizationManager = localizationManager
    }

    func open(_ destination: SettingsDestination) -> SettingsOpenResult {
        if destination.id == "mouse", !inputDeviceDetector.hasMouseDevice() {
            if let trackpad = SettingsCatalog.byID["trackpad"], openFirstAvailableURL(trackpad.urlCandidates) {
                return SettingsOpenResult(
                    status: .fallback,
                    message: localizationManager.localized("status.mouseNotDetected.trackpad")
                )
            }

            if let bluetooth = SettingsCatalog.byID["bluetooth"], openFirstAvailableURL(bluetooth.urlCandidates) {
                return SettingsOpenResult(
                    status: .fallback,
                    message: localizationManager.localized("status.mouseNotDetected.bluetooth")
                )
            }
        }

        if openFirstAvailableURL(destination.urlCandidates) {
            return SettingsOpenResult(
                status: .success,
                message: localizationManager.localized(
                    "status.openedDestination",
                    destination.localizedTitle(using: localizationManager)
                )
            )
        }

        guard let homeURL = URL(string: "x-apple.systempreferences:") else {
            return SettingsOpenResult(
                status: .failure,
                message: localizationManager.localized("status.invalidSettingsURL")
            )
        }

        if workspace.open(homeURL) {
            return SettingsOpenResult(
                status: .fallback,
                message: localizationManager.localized(
                    "status.openedSettingsHomeFallback",
                    destination.localizedTitle(using: localizationManager)
                )
            )
        }

        return SettingsOpenResult(
            status: .failure,
            message: localizationManager.localized("status.openFailed")
        )
    }

    func openSystemSettingsHome() -> SettingsOpenResult {
        guard let homeURL = URL(string: "x-apple.systempreferences:") else {
            return SettingsOpenResult(
                status: .failure,
                message: localizationManager.localized("status.invalidHomeURL")
            )
        }

        if workspace.open(homeURL) {
            return SettingsOpenResult(
                status: .success,
                message: localizationManager.localized("status.openedHome")
            )
        }

        return SettingsOpenResult(
            status: .failure,
            message: localizationManager.localized("status.openHomeFailed")
        )
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
