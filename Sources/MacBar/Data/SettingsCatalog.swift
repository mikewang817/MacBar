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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "trackpad-point-and-click",
                    titleKey: "quicklink.trackpad.pointAndClick",
                    keywords: ["click", "tap", "secondary click", "点按", "轻点", "辅助点按"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Trackpad-Settings.extension?PointAndClick",
                        "x-apple.systempreferences:com.apple.preference.trackpad?PointAndClick"
                    ]
                ),
                SettingsQuickLink(
                    id: "trackpad-scroll-and-zoom",
                    titleKey: "quicklink.trackpad.scrollAndZoom",
                    keywords: ["scroll", "zoom", "natural", "滚动", "缩放", "自然滚动"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Trackpad-Settings.extension?ScrollAndZoom",
                        "x-apple.systempreferences:com.apple.preference.trackpad?ScrollAndZoom"
                    ]
                ),
                SettingsQuickLink(
                    id: "trackpad-more-gestures",
                    titleKey: "quicklink.trackpad.moreGestures",
                    keywords: ["gestures", "swipe", "mission control", "手势", "滑动"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Trackpad-Settings.extension?MoreGestures",
                        "x-apple.systempreferences:com.apple.preference.trackpad?MoreGestures"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "keyboard-input-sources",
                    titleKey: "quicklink.keyboard.inputSources",
                    keywords: ["input source", "ime", "layout", "输入法", "输入来源", "键盘布局"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?InputSources",
                        "x-apple.systempreferences:com.apple.preference.keyboard?InputSources"
                    ]
                ),
                SettingsQuickLink(
                    id: "keyboard-shortcuts",
                    titleKey: "quicklink.keyboard.shortcuts",
                    keywords: ["shortcut", "hotkey", "快捷键", "热键"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
                        "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
                    ]
                ),
                SettingsQuickLink(
                    id: "keyboard-dictation",
                    titleKey: "quicklink.keyboard.dictation",
                    keywords: ["dictation", "voice input", "听写", "语音输入"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Dictation",
                        "x-apple.systempreferences:com.apple.preference.keyboard?Dictation"
                    ]
                ),
                SettingsQuickLink(
                    id: "keyboard-modifier-keys",
                    titleKey: "quicklink.keyboard.modifierKeys",
                    keywords: ["modifier", "caps lock", "option", "command", "修饰键"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?ModifierKeys",
                        "x-apple.systempreferences:com.apple.preference.keyboard?ModifierKeys"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "sound-output",
                    titleKey: "quicklink.sound.output",
                    keywords: ["output", "speaker", "airplay", "输出", "扬声器", "耳机"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Sound-Settings.extension?output",
                        "x-apple.systempreferences:com.apple.preference.sound?output"
                    ]
                ),
                SettingsQuickLink(
                    id: "sound-input",
                    titleKey: "quicklink.sound.input",
                    keywords: ["input", "microphone", "record", "输入", "麦克风", "录音"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Sound-Settings.extension?input",
                        "x-apple.systempreferences:com.apple.preference.sound?input"
                    ]
                ),
                SettingsQuickLink(
                    id: "sound-effects",
                    titleKey: "quicklink.sound.effects",
                    keywords: ["effect", "alert", "startup sound", "提示音", "音效"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Sound-Settings.extension?effects",
                        "x-apple.systempreferences:com.apple.preference.sound?effects"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "network-vpn",
                    titleKey: "quicklink.network.vpn",
                    keywords: ["vpn", "tunnel", "企业网络", "专线"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Network-Settings.extension?VPN",
                        "x-apple.systempreferences:com.apple.preference.network?VPN"
                    ]
                ),
                SettingsQuickLink(
                    id: "network-proxies",
                    titleKey: "quicklink.network.proxies",
                    keywords: ["proxy", "http proxy", "socks", "代理"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Network-Settings.extension?Proxies",
                        "x-apple.systempreferences:com.apple.preference.network?Proxies"
                    ]
                ),
                SettingsQuickLink(
                    id: "network-dns",
                    titleKey: "quicklink.network.dns",
                    keywords: ["dns", "resolver", "解析", "域名"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Network-Settings.extension?DNS",
                        "x-apple.systempreferences:com.apple.preference.network?DNS"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "notifications-general",
                    titleKey: "quicklink.notifications.general",
                    keywords: ["banner", "badge", "alert", "通知中心", "横幅", "角标"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?Notifications",
                        "x-apple.systempreferences:com.apple.preference.notifications?Notifications"
                    ]
                ),
                SettingsQuickLink(
                    id: "notifications-iphone-mirroring",
                    titleKey: "quicklink.notifications.iphone",
                    keywords: ["iphone", "remote notification", "mirror", "iPhone 通知", "镜像"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?RemoteNotifications",
                        "x-apple.systempreferences:com.apple.preference.notifications?RemoteNotifications"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "privacy-camera",
                    titleKey: "quicklink.privacy.camera",
                    keywords: ["camera", "webcam", "摄像头"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Camera",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                    ]
                ),
                SettingsQuickLink(
                    id: "privacy-microphone",
                    titleKey: "quicklink.privacy.microphone",
                    keywords: ["microphone", "mic", "麦克风"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Microphone",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                    ]
                ),
                SettingsQuickLink(
                    id: "privacy-location-services",
                    titleKey: "quicklink.privacy.location",
                    keywords: ["location", "gps", "定位"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                    ]
                ),
                SettingsQuickLink(
                    id: "privacy-screen-capture",
                    titleKey: "quicklink.privacy.screenCapture",
                    keywords: ["screen capture", "recording", "屏幕录制", "录屏"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                    ]
                ),
                SettingsQuickLink(
                    id: "privacy-accessibility",
                    titleKey: "quicklink.privacy.accessibility",
                    keywords: ["accessibility", "assistive", "辅助功能权限"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ]
                )
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
            ],
            quickLinks: [
                SettingsQuickLink(
                    id: "date-time-general",
                    titleKey: "quicklink.dateTime.general",
                    keywords: ["date", "time", "clock", "日期", "时间", "时钟"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Date-Time-Settings.extension?DateTimePref",
                        "x-apple.systempreferences:com.apple.preference.datetime?DateTime",
                        "x-apple.systempreferences:com.apple.preference.datetime?DateTimePref"
                    ]
                ),
                SettingsQuickLink(
                    id: "date-time-timezone",
                    titleKey: "quicklink.dateTime.timeZone",
                    keywords: ["timezone", "location", "NTP", "时区", "自动时区"],
                    urlCandidates: [
                        "x-apple.systempreferences:com.apple.Date-Time-Settings.extension?TimeZonePref",
                        "x-apple.systempreferences:com.apple.preference.datetime?TimeZone",
                        "x-apple.systempreferences:com.apple.preference.datetime?TimeZonePref"
                    ]
                )
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
