import Foundation

enum SettingsCatalog {
    static let all: [SettingsDestination] = [
        SettingsDestination(
            id: "mouse",
            titleKey: "destination.mouse.title",
            subtitleKey: "destination.mouse.subtitle",
            symbolName: "computermouse",
            category: .input,
            keywords: ["mouse", "滚轮", "灵敏度", "pointer"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Mouse",
                "x-apple.systempreferences:com.apple.Mouse-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.mouse"
            ]
        ),
        SettingsDestination(
            id: "trackpad",
            titleKey: "destination.trackpad.title",
            subtitleKey: "destination.trackpad.subtitle",
            symbolName: "rectangle.and.hand.point.up.left.filled",
            category: .input,
            keywords: ["trackpad", "手势", "三指", "点击"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.trackpad"
            ]
        ),
        SettingsDestination(
            id: "keyboard",
            titleKey: "destination.keyboard.title",
            subtitleKey: "destination.keyboard.subtitle",
            symbolName: "keyboard",
            category: .input,
            keywords: ["keyboard", "快捷键", "输入法", "key repeat"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Keyboard-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.keyboard"
            ]
        ),
        SettingsDestination(
            id: "displays",
            titleKey: "destination.displays.title",
            subtitleKey: "destination.displays.subtitle",
            symbolName: "display.2",
            category: .displayAndSound,
            keywords: ["display", "resolution", "hdr", "屏幕"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Displays-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.displays"
            ]
        ),
        SettingsDestination(
            id: "sound",
            titleKey: "destination.sound.title",
            subtitleKey: "destination.sound.subtitle",
            symbolName: "speaker.wave.2.fill",
            category: .displayAndSound,
            keywords: ["sound", "audio", "麦克风", "扬声器"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Sound-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.sound"
            ]
        ),
        SettingsDestination(
            id: "wifi",
            titleKey: "destination.wifi.title",
            subtitleKey: "destination.wifi.subtitle",
            symbolName: "wifi",
            category: .connectivity,
            keywords: ["wifi", "wireless", "ssid", "网络"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.wifi-settings-extension",
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        ),
        SettingsDestination(
            id: "bluetooth",
            titleKey: "destination.bluetooth.title",
            subtitleKey: "destination.bluetooth.subtitle",
            symbolName: "bolt.horizontal.circle.fill",
            category: .connectivity,
            keywords: ["bluetooth", "airpods", "配对", "连接"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.BluetoothSettings",
                "x-apple.systempreferences:com.apple.preferences.Bluetooth"
            ]
        ),
        SettingsDestination(
            id: "network",
            titleKey: "destination.network.title",
            subtitleKey: "destination.network.subtitle",
            symbolName: "network",
            category: .connectivity,
            keywords: ["network", "dns", "vpn", "proxy"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Network-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.network"
            ]
        ),
        SettingsDestination(
            id: "notifications",
            titleKey: "destination.notifications.title",
            subtitleKey: "destination.notifications.subtitle",
            symbolName: "bell.badge.fill",
            category: .privacy,
            keywords: ["notification", "提醒", "横幅", "推送"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.notifications"
            ]
        ),
        SettingsDestination(
            id: "privacy-security",
            titleKey: "destination.privacySecurity.title",
            subtitleKey: "destination.privacySecurity.subtitle",
            symbolName: "hand.raised.fill",
            category: .privacy,
            keywords: ["privacy", "security", "权限", "firewall"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
                "x-apple.systempreferences:com.apple.preference.security"
            ]
        ),
        SettingsDestination(
            id: "accessibility",
            titleKey: "destination.accessibility.title",
            subtitleKey: "destination.accessibility.subtitle",
            symbolName: "figure.roll",
            category: .privacy,
            keywords: ["accessibility", "voiceover", "zoom", "辅助"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Accessibility-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.universalaccess"
            ]
        ),
        SettingsDestination(
            id: "control-center",
            titleKey: "destination.controlCenter.title",
            subtitleKey: "destination.controlCenter.subtitle",
            symbolName: "switch.2",
            category: .system,
            keywords: ["control center", "菜单栏", "status bar", "组件"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
            ]
        ),
        SettingsDestination(
            id: "battery",
            titleKey: "destination.battery.title",
            subtitleKey: "destination.battery.subtitle",
            symbolName: "battery.100percent",
            category: .system,
            keywords: ["battery", "power", "充电", "省电"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Battery-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.battery"
            ]
        ),
        SettingsDestination(
            id: "login-items",
            titleKey: "destination.loginItems.title",
            subtitleKey: "destination.loginItems.subtitle",
            symbolName: "person.crop.circle.badge.checkmark",
            category: .system,
            keywords: ["login items", "开机启动", "background", "后台"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            ]
        ),
        SettingsDestination(
            id: "date-time",
            titleKey: "destination.dateTime.title",
            subtitleKey: "destination.dateTime.subtitle",
            symbolName: "clock.arrow.circlepath",
            category: .system,
            keywords: ["date", "time", "timezone", "时间"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Date-Time-Settings.extension",
                "x-apple.systempreferences:com.apple.preference.datetime"
            ]
        ),
        SettingsDestination(
            id: "software-update",
            titleKey: "destination.softwareUpdate.title",
            subtitleKey: "destination.softwareUpdate.subtitle",
            symbolName: "arrow.triangle.2.circlepath.circle.fill",
            category: .system,
            keywords: ["update", "升级", "os", "patch"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.Software-Update-Settings.extension"
            ]
        )
    ]

    static let byID: [String: SettingsDestination] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
