# MacBar Agent Guide

> 本文件应与 `CLAUDE.md` 保持同一套规则与流程；修改其中一份时，另一份也要同步更新。

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
docs/
```

重点文件：

- `Sources/MacBar/Stores/MacBarStore.swift`
  中央状态源，剪贴板历史、置顶、OCR 缓存、更新状态都在这里
- `Sources/MacBar/Services/ClipboardMonitor.swift`
  剪贴板轮询与写回逻辑
- `Sources/MacBar/Services/ClipboardImageStore.swift`
  剪贴板图片落盘与读取缓存；历史里的图片不再直接长期塞进 `UserDefaults`
- `Sources/MacBar/Services/AirDropService.swift`
  统一封装文件和图片的隔空投送动作，基于 `NSSharingService(named: .sendViaAirDrop)`
- `Sources/MacBar/Services/OCRService.swift`
  图片 OCR，基于 Vision，完全本地执行；输入是图片二进制数据，识别在后台线程完成
- `Sources/MacBar/AppVersion.swift`
  统一版本号入口；优先读 `Bundle.main`，读不到时回退到源码里的版本号
- `Sources/MacBar/Services/LocalizationManager.swift`
  语言选择与本地化解析
- `Sources/MacBar/Views/MenuBarRootView.swift`
  主 UI，列表、预览、快捷键处理都在这里

## 架构与约束

- 状态管理采用单一 `MacBarStore`，UI 变更优先通过 store 驱动，不要在 View 里复制业务状态。
- 并发边界以 `@MainActor` 为主。修改 store、AppDelegate、UI 状态时不要绕开主线程约束。
- 这是菜单栏应用，窗口使用 `NSPanel`，不要随意改成常规 `NSWindow`。
- 全局热键使用 Carbon `RegisterEventHotKey`。若修改热键，需同时检查注册逻辑与按键匹配逻辑。
- 剪贴板捕获顺序要保持为：`文件 -> 文本 -> 图片`。复制 Finder 文件时剪贴板通常也带文本表示，顺序改错会产生行为回归。
- 图片 OCR 结果只缓存到内存中的 `clipboardOCRCache`，删除或清空条目时要同步清理缓存。
- 剪贴板历史中的图片二进制数据优先落到 `Application Support/MacBar/ClipboardImages/`，持久化到 `UserDefaults` 的历史只保留元数据；修改图片存储时要同时处理迁移、删除和孤儿文件清理。
- 图片展示与复制优先走 `MacBarStore.clipboardImage(...)` / `clipboardImageData(...)`，不要在 View 里反复直接 `NSImage(data:)` 解码。
- 文件和图片的隔空投送动作统一走 `AirDropService`；不要在多个 View 里各自直接拼 `NSSharingService` 调用。
- OCR 触发采用队列式调度，避免为整段历史同时启动大量 Vision 请求；如果改动 OCR 入口，要同时检查去重、优先级和面板关闭后的行为。
- 搜索不仅搜文本，也搜图片 OCR 文本、文件名和文件完整路径；相关修改要覆盖这三类条目。
- 复制任意条目后默认会关闭面板，并尽量回到打开前的前台应用；修改复制流时要同时检查 `MenuBarRootView` 的关闭回调和 `AppDelegate` 的前台应用恢复逻辑。
- `Esc` 行为是两段式：搜索框有内容时清空搜索，否则关闭面板；改动搜索交互时不要破坏这条约定。

## 本地化规则

- 用户可见字符串不要直接硬编码，除应用名 `MacBar` 和系统按钮 `OK` 外，统一走 `store.localized(...)` 或 `localizationManager.localized(...)`。
- 快捷键、按键名、菜单动作等文案要符合目标语言的真实使用习惯，不要机械直译；例如中文场景优先写 `Enter`、`CMD + 删除键`，而不是把按键名称字面翻成“输入”“命令删除”。
- 快捷键提示目前由 `MacBarStore` 按语言风格动态生成；如果调整这类文案，优先改生成逻辑，不要只改某一种语言的整句翻译。
- MacBar 当前只维护 7 种界面语言：`en`、`zh-Hans`、`de`、`fr`、`ja`、`ko`、`ar`；不要重新引入其他 `.lproj` 目录，除非用户明确要求扩语种。
- 新增文案时，必须同步更新以下 7 个文件：
  - `Sources/MacBar/Resources/en.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/zh-Hans.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/de.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/fr.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/ja.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/ko.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/ar.lproj/Localizable.strings`
- 不要再使用 `scripts/generate_localizations.py` 维护 UI 多语言；当前约定是直接维护上述语言文件。
- 语言列表是产品定义，不再直接暴露 `Bundle.module.localizations` 的全部结果；设置页中的语言选项应与上述 7 种语言保持一致，并支持“跟随系统”。

## 修改建议

- 做功能变更时，先判断影响的是 `Store`、`Service` 还是 `View`，不要把业务逻辑直接塞进 SwiftUI 视图层。
- 涉及文件条目展示时，注意当前 UI 约定是“文件名 + 目录路径”双行展示，悬停显示完整路径。
- 涉及文本条目展示时，注意当前列表约定是“首行标题 + 次行摘要/相对时间”双行展示。
- 涉及图片条目展示时，优先复用 store 提供的缓存读取接口，并继续保持列表与预览共用同一份图片来源。
- 涉及文件或图片条目操作按钮时，注意预览区和列表行现在都支持隔空投送，交互应保持一致。
- 涉及底部快捷键提示时，注意当前不是直接显示本地化整句，而是由 `MacBarStore.clipboardCopyShortcutHint()` / `clipboardDeleteShortcutHint()` 根据语言习惯生成。
- 涉及语言切换时，注意当前入口在设置页，不在底部工具栏；修改语言相关 UI 时不要恢复成独立 footer 菜单。
- 涉及预览面板尺寸时，要同步考虑 `MenuBarRootView.preferredPanelSize` 和 `AppDelegate` 的 panel size 更新逻辑。
- 涉及资源或本地化包时，确认 `Package.swift` 的 `resources: [.process("Resources")]` 仍然满足需求。
- 当前版本没有配置导入/导出功能，除非用户明确要求，否则不要重新引入相关入口或模型。
- 不要引入网络库、数据库、统计 SDK 或其他第三方依赖，除非用户明确要求并接受架构变化。

## Git 与网站分支规则

- 网站落地页和 Cloudflare Pages 部署相关改动只允许保留在本地分支 `codex/website-local`。
- `codex/website-local` 是本地专用分支，不得 push 到 GitHub，不得合并回 `master`，也不要 cherry-pick 其中提交，除非用户明确要求。
- `master` 默认只保留应用主线代码与文档，不应包含 `website/`、`wrangler.jsonc`、Pages 下载包等网站发布内容。
- 任何执行 `git push` 之前，必须先检查当前分支不是 `codex/website-local`，并确认 `origin/master..HEAD` 中没有网站相关提交。
- 建议在 push 前固定执行：

```bash
git branch --show-current
git log --oneline origin/master..HEAD
git diff --stat origin/master..HEAD
```

- 如果需要继续修改网站，先执行 `git switch codex/website-local`；网站部署到 Cloudflare Pages 不依赖 push GitHub。
- 网站部署默认使用临时 Wrangler 命令：

```bash
npx --yes wrangler pages deploy website
```

- 除非用户明确要求安装全局 `wrangler`，否则优先使用上述 `npx` 方式，不要依赖本机全局安装。

## App Store 与证书管理约定

- 对于 App Store Connect 上传、TestFlight、正式发布、证书、provisioning profile、签名配置等事项，默认优先使用 `fastlane`。
- 手工点 Xcode、手工切签名、手工上传只作为排障或临时兜底，不再作为主流程。
- 若仓库里已有 `fastlane/`、`Fastfile`、`Appfile`、`Matchfile` 或相关 lane，优先在现有配置上扩展。
- 若用户要求“搞定上架”“管理证书”“自动化发布”，优先补 fastlane lane，而不是继续堆一次性 shell 脚本。
- 证书、profile、上传、提审相关能力应尽量沉淀进 fastlane，保证后续可重复执行。
- 常规 App Store 发布步骤默认按以下顺序执行：

```bash
bundle exec fastlane mac bump_version version:X.Y.Z
bundle exec fastlane mac sync_signing
bundle exec fastlane mac build_app_store
bundle exec fastlane mac upload_app_store
```

- 若用户明确要求一条命令串起上述流程，可使用：

```bash
bundle exec fastlane mac release_app_store
```

每次发布新版本时：

- 先更新 `Sources/MacBar/Info.plist` 和 `Sources/MacBar/AppVersion.swift` 的版本号。
- 提交并推送应用代码前，先确认当前分支不是 `codex/website-local`。
- 通过 fastlane 完成签名、构建和上传，不再通过 GitHub Releases 分发安装包。
- 如果官网需要同步文案或链接，切到 `codex/website-local` 单独处理并用 Wrangler 部署。

## 交付前检查

- 先跑 `swift build`
- 如果改了本地化 key，检查 7 个受支持语言文件是否都已补齐
- 如果改了热键、面板、OCR、复制后返回原应用或 App Store 发布流程，优先在 Xcode 中做一次手动验证
- 如仓库里存在与你任务无关的脏改动，不要回滚它们
