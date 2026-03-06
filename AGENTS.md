# MacBar Agent Guide

## 项目概览

- 项目类型：macOS 菜单栏剪贴板管理器
- 技术栈：Swift 6.2 + SwiftUI + AppKit + Vision
- 构建方式：Swift Package Manager，仓库内没有 `.xcodeproj`
- 平台要求：macOS 14+
- 依赖策略：无第三方依赖，优先使用 Apple 原生框架

应用入口是 `Sources/MacBar/MacBarApp.swift`，实际窗口与热键管理在 `Sources/MacBar/AppDelegate.swift`。

## 常用命令

在仓库根目录执行：

```bash
swift build
swift run MacBar
open Package.swift
```

说明：

- `swift build` 适合静态检查和编译验证
- `swift run MacBar` 可做基础运行验证，但部分能力依赖 app bundle
- 涉及面板行为、菜单栏、Vision OCR、资源加载时，优先用 Xcode 打开 `Package.swift` 运行

## 目录结构

```text
Package.swift
Sources/MacBar/
  MacBarApp.swift
  AppDelegate.swift
  Models/
  Services/
  Stores/
  Views/
  Resources/
scripts/
README.md
README.zh-Hans.md
```

重点文件：

- `Sources/MacBar/Stores/MacBarStore.swift`
  中央状态源，剪贴板历史、置顶、OCR 缓存、更新状态都在这里
- `Sources/MacBar/Services/ClipboardMonitor.swift`
  剪贴板轮询与写回逻辑
- `Sources/MacBar/Services/OCRService.swift`
  图片 OCR，基于 Vision，完全本地执行
- `Sources/MacBar/Services/LocalizationManager.swift`
  语言选择与本地化解析
- `Sources/MacBar/Services/UpdateService.swift`
  GitHub Releases 更新检查与安装
- `Sources/MacBar/Views/MenuBarRootView.swift`
  主 UI，列表、预览、快捷键处理都在这里

## 架构与约束

- 状态管理采用单一 `MacBarStore`，UI 变更优先通过 store 驱动，不要在 View 里复制业务状态。
- 并发边界以 `@MainActor` 为主。修改 store、AppDelegate、UI 状态时不要绕开主线程约束。
- 这是菜单栏应用，窗口使用 `NSPanel`，不要随意改成常规 `NSWindow`。
- 全局热键使用 Carbon `RegisterEventHotKey`。若修改热键，需同时检查注册逻辑与按键匹配逻辑。
- 剪贴板捕获顺序要保持为：`文件 -> 文本 -> 图片`。复制 Finder 文件时剪贴板通常也带文本表示，顺序改错会产生行为回归。
- 图片 OCR 结果只缓存到内存中的 `clipboardOCRCache`，删除或清空条目时要同步清理缓存。
- 搜索不仅搜文本，也搜图片 OCR 文本和文件名；相关修改要覆盖这三类条目。
- 更新服务会访问 GitHub Releases；如果修改 README 或隐私描述，需要与当前实现保持一致。

## 本地化规则

- 用户可见字符串不要直接硬编码，除应用名 `MacBar` 和系统按钮 `OK` 外，统一走 `store.localized(...)` 或 `localizationManager.localized(...)`。
- 新增文案时，至少同步更新：
  - `Sources/MacBar/Resources/en.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/zh-Hans.lproj/Localizable.strings`
- 其余语言由 `scripts/generate_localizations.py` 生成；仅在确实新增 key 后再跑脚本。
- 语言列表来源于 `Bundle.module.localizations`，不要手写静态语言枚举。

## 修改建议

- 做功能变更时，先判断影响的是 `Store`、`Service` 还是 `View`，不要把业务逻辑直接塞进 SwiftUI 视图层。
- 涉及文件条目展示时，注意当前 UI 约定是“文件名 + 目录路径”双行展示，悬停显示完整路径。
- 涉及预览面板尺寸时，要同步考虑 `MenuBarRootView.preferredPanelSize` 和 `AppDelegate` 的 panel size 更新逻辑。
- 涉及资源或本地化包时，确认 `Package.swift` 的 `resources: [.process("Resources")]` 仍然满足需求。
- 不要引入网络库、数据库、统计 SDK 或其他第三方依赖，除非用户明确要求并接受架构变化。

## 交付前检查

- 先跑 `swift build`
- 如果改了本地化 key，检查英文和简体中文是否都已补齐
- 如果改了热键、面板、OCR、更新流程，优先在 Xcode 中做一次手动验证
- 如仓库里存在与你任务无关的脏改动，不要回滚它们
