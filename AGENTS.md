# MacBar Agent Guide

> 本文件应与 `CLAUDE.md` 保持一致。修改其中一份时，另一份也要同步更新。

## 项目概览

- 项目类型：macOS 菜单栏剪贴板管理器
- 技术栈：Swift 6.2 + SwiftUI + AppKit + Vision
- 构建方式：Swift Package Manager + Xcode 工程
- Xcode 工程来源：`MacBar.xcodeproj` 由 `project.yml` 生成
- 平台要求：macOS 14+
- 分发方向：当前主线默认面向 App Store
- 更新策略：当前主线默认不启用外部更新，不再依赖 GitHub Releases 或官网安装包

应用入口在 `Sources/MacBar/MacBarApp.swift`，菜单栏窗口和设置窗口逻辑在 `Sources/MacBar/AppDelegate.swift`。

## 常用命令

在仓库根目录执行：

```bash
swift build
swift run MacBar
open MacBar.xcodeproj
```

补充：

- 修改 `project.yml` 后，执行 `xcodegen generate`
- 需要更接近真实运行环境时，优先从 Xcode 跑 `MacBar.xcodeproj`
- App Store 相关流程优先使用 `fastlane`

## 目录结构

```text
Package.swift
project.yml
MacBar.xcodeproj/
Sources/MacBar/
  MacBarApp.swift
  AppDelegate.swift
  MacBar.swift
  Models/
  Services/
  Stores/
  Views/
  Resources/
fastlane/
scripts/
README.md
AGENTS.md
CLAUDE.md
```

关键文件：

- `Sources/MacBar/Stores/MacBarStore.swift`
  中央状态源，剪贴板历史、置顶、OCR 缓存、复制语义、更新状态都在这里
- `Sources/MacBar/Services/ClipboardMonitor.swift`
  剪贴板采集与写回
- `Sources/MacBar/Services/ClipboardImageStore.swift`
  图片持久化与缓存读取
- `Sources/MacBar/Services/AirDropService.swift`
  文件和图片的隔空投送
- `Sources/MacBar/Services/OCRService.swift`
  本地 OCR
- `Sources/MacBar/Views/MenuBarRootView.swift`
  主列表、预览区、键盘交互
- `Sources/MacBar/Views/SettingsRootView.swift`
  独立设置窗口
- `Sources/MacBar/MacBar.swift`
  `BuildInfo` 所在位置；当前主线默认 `isAppStoreDistribution = true`
- `project.yml`
  XcodeGen 配置源

## 架构与行为约束

- 状态管理以 `MacBarStore` 为中心，不要在 SwiftUI View 里复制业务状态。
- 菜单栏主界面使用 `NSPanel`，设置使用独立 `NSWindow`。不要恢复旧的“菜单栏内嵌设置页”结构。
- 全局热键使用 Carbon `RegisterEventHotKey`，当前约定是 `⇧⌘M`。
- 剪贴板捕获顺序保持：`文件 -> 文本 -> 图片`。
- 搜索需要覆盖：文本内容、OCR 文本、文件名、完整路径。
- 图片缓存优先通过 `MacBarStore.clipboardImage(...)` / `clipboardImageData(...)` 读取，不要在 View 层反复解码。
- 图片项当前有两种复制语义：
  - `Image`：适合粘贴到 Word、Notion、聊天工具、编辑器
  - `File`：适合粘贴到 Finder、文件夹、文件型工作流
- 修改图片复制逻辑时，要同时检查：
  - 列表回车复制
  - 双击复制
  - 左右箭头切换 `Image / File`
  - 预览区 `Copy as File`
- 置顶项快捷键必须稳定分配，当前范围是 `⌘B` 到 `⌘Z`，不能再使用 `⌘A`。
- 复制条目后默认会关闭面板，并尽量恢复到原前台应用；变更复制行为时要同时检查面板关闭逻辑。
- `Esc` 规则：先清空搜索，再关闭面板。
- 预览区动作按钮当前约定是纯文字按钮，并保持一致高度。
- App Store 主线默认不启用外部更新；除非用户明确要求，不要恢复 GitHub / 官网更新检查。

## 本地化规则

- 用户可见文案不要硬编码，统一走 `store.localized(...)` 或 `localizationManager.localized(...)`。
- 当前维护的界面语言只有 7 种：
  - `en`
  - `zh-Hans`
  - `de`
  - `fr`
  - `ja`
  - `ko`
  - `ar`
- 新增文案时，必须同步更新以上 7 个 `Localizable.strings`。
- 不要重新引入其他 `.lproj`，除非用户明确要求扩语种。
- 不要恢复旧的自动本地化生成脚本流程；当前约定是直接维护字符串文件。

## Git、网站与公开仓库规则

- `master` 只保留应用主线代码与必要公开文档。
- `Marketing/` 默认只保留在本地，不要加入 `master`，除非用户明确要求。
- 不要把营销素材、短视频、平台文案、生成图、临时脚本推到 `master`。
- 对公开 GitHub 仓库，避免新增内部过程文档或临时 `docs/` 资产；若不是用户明确要求，公开说明优先收敛到 `README.md`。
- 网站相关改动只允许放在本地分支 `codex/website-local`。
- `codex/website-local` 不得 push 到 GitHub，不得合并回 `master`，除非用户明确要求。
- 网站部署默认使用：

```bash
npx --yes wrangler pages deploy website
```

- 执行 `git push` 前，固定检查：

```bash
git branch --show-current
git log --oneline origin/master..HEAD
git diff --stat origin/master..HEAD
```

## App Store 与 fastlane 约定

- App Store Connect 上传、TestFlight、正式发布、证书、profile、签名配置默认优先使用 `fastlane`。
- 手工点 Xcode 和手工上传只作为排障手段。
- 常规发布步骤：

```bash
bundle exec fastlane mac bump_version version:X.Y.Z
bundle exec fastlane mac sync_signing
bundle exec fastlane mac build_app_store
bundle exec fastlane mac upload_app_store
```

- 一键发布：

```bash
bundle exec fastlane mac release_app_store
```

- 发布前先更新：
  - `Sources/MacBar/Info.plist`
  - `Sources/MacBar/AppVersion.swift`

## 交付前检查

- 先跑 `swift build`
- 如果改了 `project.yml`，确认执行过 `xcodegen generate`
- 如果改了 OCR、热键、复制语义、预览区、设置窗口、面板关闭逻辑，优先在 Xcode 做一次手动验证
- 如果改了文案，确认 7 种语言都已补齐
- 如仓库里存在与你任务无关的脏改动，不要回滚它们
