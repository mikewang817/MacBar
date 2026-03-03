# MacBar

MacBar 是一个常驻在 macOS 菜单栏的快速入口应用，目标是让你在 1-2 次点击内进入常用系统设置页（如鼠标、触控板、Wi-Fi、隐私与安全性等）。

## 已完成功能（MVP）

- 菜单栏常驻：使用 `MenuBarExtra`，不占 Dock。
- 常用设置直达：内置多组 System Settings 深链（新旧系统双候选）。
- 搜索：支持中文/英文关键词检索。
- 收藏：星标高频设置项，持久化保存。
- 设备感知显示：未检测到鼠标设备时，自动隐藏“鼠标”入口。
- 实时刷新：鼠标插拔后会自动刷新列表，无需重启 MacBar。
- 多语言支持：默认跟随 macOS 系统语言，可在应用内切换语言。
- 语言选项列表：仅展示已支持语言（不展示未支持语言）。
- 使用人口阈值：内置“使用人口 >500万”语言资源（当前生成 164 个语言包，含方言回退映射）。
- 资源生成脚本：`scripts/generate_localizations.py` 可重复生成本地化文件。
- 失败回退：深链失效时自动回退到系统设置主页。
- 深层跳转：为键盘/声音/网络/通知/隐私与安全性/日期与时间等提供子页直达。
- 配置管理：支持导出 JSON 配置与导入配置。

## 体验设计

- 入口路径短：每个设置项都带有明确描述和单独“打开”按钮。
- 信息密度高但可读：按类别分组，优先展示收藏。
- 结果反馈：深链回退/失败与配置操作会弹窗提示。
- 国际化结构：文案全部通过 `Localizable.strings` 管理，便于继续扩展翻译。

## 技术方案

- 语言与框架：Swift 6 + SwiftUI + AppKit
- 打包方式：Swift Package 可执行目标
- 架构分层：
  - `Data`：设置目录与深链候选
  - `Models`：领域模型与分类
  - `Services`：系统设置导航器、设备检测、语言管理
  - `Stores`：状态管理与本地持久化
  - `Views`：菜单栏窗口 UI

## 项目结构

```
MacBar/
├── Package.swift
├── README.md
└── Sources/MacBar
    ├── AppDelegate.swift
    ├── MacBarApp.swift
    ├── MacBar.swift
    ├── Data/SettingsCatalog.swift
    ├── Models/SettingsCategory.swift
    ├── Models/AppConfiguration.swift
    ├── Models/SettingsDestination.swift
    ├── Resources/*.lproj/Localizable.strings
    ├── Services/AppConfigurationManager.swift
    ├── Services/LocalizationManager.swift
    ├── Services/SettingsNavigator.swift
    ├── Stores/MacBarStore.swift
    └── Views/MenuBarRootView.swift
└── scripts/generate_localizations.py
```

## 运行

```bash
cd /Users/patgo/app/MacBar
swift build
swift run MacBar
```

## 多语言资源再生成

```bash
cd /Users/patgo/app/MacBar
python3 -m venv .venv
source .venv/bin/activate
pip install langcodes language-data deep-translator Babel
python scripts/generate_localizations.py
```

## 下一步建议

1. 增加“开机启动”开关（`SMAppService`）。
2. 增加用户自定义入口（自定义 URL Scheme / 脚本）。
3. 增加诊断页：检测当前系统可用深链并自动修正。
