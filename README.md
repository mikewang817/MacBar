# MacBar

MacBar 是一个常驻在 macOS 菜单栏的快速入口应用，目标是让你在 1-2 次点击内进入常用系统设置页（如鼠标、触控板、Wi-Fi、隐私与安全性等）。

## 已完成功能（MVP）

- 菜单栏常驻：使用 `MenuBarExtra`，不占 Dock。
- 常用设置直达：内置多组 System Settings 深链（新旧系统双候选）。
- 搜索：支持中文/英文关键词检索。
- 收藏：星标高频设置项，持久化保存。
- 设备感知显示：未检测到鼠标设备时，自动隐藏“鼠标”入口。
- 实时刷新：鼠标插拔后会自动刷新列表，无需重启 MacBar。
- 失败回退：深链失效时自动回退到系统设置主页。

## 体验设计

- 入口路径短：每个设置项都带有明确描述和单独“打开”按钮。
- 信息密度高但可读：按类别分组，优先展示收藏。
- 状态可见：每次打开后底部显示结果（成功/回退/失败）。

## 技术方案

- 语言与框架：Swift 6 + SwiftUI + AppKit
- 打包方式：Swift Package 可执行目标
- 架构分层：
  - `Data`：设置目录与深链候选
  - `Models`：领域模型与分类
  - `Services`：系统设置导航器
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
    ├── Models/SettingsDestination.swift
    ├── Services/SettingsNavigator.swift
    ├── Stores/MacBarStore.swift
    └── Views/MenuBarRootView.swift
```

## 运行

```bash
cd /Users/patgo/app/MacBar
swift build
swift run MacBar
```

## 下一步建议

1. 增加“开机启动”开关（`SMAppService`）。
2. 增加用户自定义入口（自定义 URL Scheme / 脚本）。
3. 增加诊断页：检测当前系统可用深链并自动修正。
