import Foundation

enum SettingsCatalog {
    static let all: [SettingsDestination] = [
        SettingsDestination(
            id: "mouse",
            title: "鼠标",
            subtitle: "滚动方向、追踪速度、辅助点按",
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
            title: "触控板",
            subtitle: "轻点、手势、滚动与缩放",
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
            title: "键盘",
            subtitle: "按键重复、修饰键、输入法快捷键",
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
            title: "显示器",
            subtitle: "分辨率、刷新率、排列和扩展模式",
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
            title: "声音",
            subtitle: "输入输出设备、提示音、音量",
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
            title: "Wi-Fi",
            subtitle: "当前网络、已知网络、自动加入",
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
            title: "蓝牙",
            subtitle: "配对设备、连接稳定性、输入设备切换",
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
            title: "网络",
            subtitle: "代理、DNS、VPN、以太网配置",
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
            title: "通知",
            subtitle: "应用通知权限、横幅样式、专注模式联动",
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
            title: "隐私与安全性",
            subtitle: "摄像头/麦克风权限、防火墙、磁盘访问",
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
            title: "辅助功能",
            subtitle: "缩放、旁白、显示与动作简化",
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
            title: "控制中心",
            subtitle: "菜单栏组件显示、布局与行为",
            symbolName: "switch.2",
            category: .system,
            keywords: ["control center", "菜单栏", "status bar", "组件"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension"
            ]
        ),
        SettingsDestination(
            id: "battery",
            title: "电池",
            subtitle: "低电量模式、健康管理与用电统计",
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
            title: "登录项",
            subtitle: "开机自启应用与后台项目",
            symbolName: "person.crop.circle.badge.checkmark",
            category: .system,
            keywords: ["login items", "开机启动", "background", "后台"],
            urlCandidates: [
                "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
            ]
        ),
        SettingsDestination(
            id: "date-time",
            title: "日期与时间",
            subtitle: "时区、24小时制、网络自动校时",
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
            title: "软件更新",
            subtitle: "检查系统更新与自动更新策略",
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
