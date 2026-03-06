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
docs/
```

重点文件：

- `Sources/MacBar/Stores/MacBarStore.swift`
  中央状态源，剪贴板历史、置顶、OCR 缓存、更新状态都在这里
- `Sources/MacBar/Services/ClipboardMonitor.swift`
  剪贴板轮询与写回逻辑
- `Sources/MacBar/Services/OCRService.swift`
  图片 OCR，基于 Vision，完全本地执行
- `Sources/MacBar/AppVersion.swift`
  统一版本号入口；优先读 `Bundle.main`，读不到时回退到源码里的版本号
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
- 搜索不仅搜文本，也搜图片 OCR 文本、文件名和文件完整路径；相关修改要覆盖这三类条目。
- 复制任意条目后默认会关闭面板，并尽量回到打开前的前台应用；修改复制流时要同时检查 `MenuBarRootView` 的关闭回调和 `AppDelegate` 的前台应用恢复逻辑。
- `Esc` 行为是两段式：搜索框有内容时清空搜索，否则关闭面板；改动搜索交互时不要破坏这条约定。
- 更新检查不是只在启动时触发：启动后会强制检查一次，之后每次打开面板都会累计次数；当前达到 20 次时会再次检查，避免长时间不重启时错过新 release。
- 更新服务会访问 GitHub Releases；如果修改 README 或隐私描述，需要与当前实现保持一致。

## 本地化规则

- 用户可见字符串不要直接硬编码，除应用名 `MacBar` 和系统按钮 `OK` 外，统一走 `store.localized(...)` 或 `localizationManager.localized(...)`。
- 快捷键、按键名、菜单动作等文案要符合目标语言的真实使用习惯，不要机械直译；例如中文场景优先写 `Enter`、`CMD + 删除键`，而不是把按键名称字面翻成“输入”“命令删除”。
- 快捷键提示目前由 `MacBarStore` 按语言风格动态生成；如果调整这类文案，优先改生成逻辑，不要只改某一种语言的整句翻译。
- 新增文案时，至少同步更新：
  - `Sources/MacBar/Resources/en.lproj/Localizable.strings`
  - `Sources/MacBar/Resources/zh-Hans.lproj/Localizable.strings`
- 其余语言由 `scripts/generate_localizations.py` 生成；仅在确实新增 key 后再跑脚本。
- 语言列表来源于 `Bundle.module.localizations`，不要手写静态语言枚举。

## 修改建议

- 做功能变更时，先判断影响的是 `Store`、`Service` 还是 `View`，不要把业务逻辑直接塞进 SwiftUI 视图层。
- 涉及文件条目展示时，注意当前 UI 约定是“文件名 + 目录路径”双行展示，悬停显示完整路径。
- 涉及文本条目展示时，注意当前列表约定是“首行标题 + 次行摘要/相对时间”双行展示。
- 涉及底部快捷键提示时，注意当前不是直接显示本地化整句，而是由 `MacBarStore.clipboardCopyShortcutHint()` / `clipboardDeleteShortcutHint()` 根据语言习惯生成。
- 涉及预览面板尺寸时，要同步考虑 `MenuBarRootView.preferredPanelSize` 和 `AppDelegate` 的 panel size 更新逻辑。
- 涉及资源或本地化包时，确认 `Package.swift` 的 `resources: [.process("Resources")]` 仍然满足需求。
- 当前版本没有配置导入/导出功能，除非用户明确要求，否则不要重新引入相关入口或模型。
- 不要引入网络库、数据库、统计 SDK 或其他第三方依赖，除非用户明确要求并接受架构变化。

## 发布 Release 流程

每次发布新版本按以下步骤执行：

### 1. 修改版本号

编辑 `Sources/MacBar/Info.plist`，同时递增两个字段：
- `CFBundleVersion`：整数，每次 +1
- `CFBundleShortVersionString`：语义版本，如 `1.0.8`

同时同步更新 `Sources/MacBar/AppVersion.swift` 里的 fallback 值。原因是 SwiftPM 运行时的 `Bundle.main` 不一定带上自定义 `Info.plist`，应用内版本显示和更新检查会回退到这里。

提交并推送：
```bash
git add Sources/MacBar/Info.plist Sources/MacBar/AppVersion.swift
git commit -m "chore: bump version to X.X.X"
git push
```

### 2. 构建 Archive

```bash
xcodebuild archive \
  -scheme MacBar \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath /tmp/MacBar.xcarchive \
  SKIP_INSTALL=NO
```

### 3. 组装 App Bundle

```bash
VERSION="X.X.X"
APP_DIR="/tmp/MacBarBuild/MacBar.app/Contents"
DERIVED=$(ls -d ~/Library/Developer/Xcode/DerivedData/MacBar-*/Build/Intermediates.noindex/ArchiveIntermediates/MacBar/BuildProductsPath/Release | head -1)

rm -rf /tmp/MacBarBuild && mkdir -p "$APP_DIR/MacOS" "$APP_DIR/Resources"

# 可执行文件
cp /tmp/MacBar.xcarchive/Products/usr/local/bin/MacBar "$APP_DIR/MacOS/MacBar"

# Info.plist
cp Sources/MacBar/Info.plist "$APP_DIR/Info.plist"

# 编译图标和资源（生成 Assets.car）
xcrun actool \
  --compile "$APP_DIR/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist /tmp/actool_partial.plist \
  Sources/MacBar/Resources/Assets.xcassets

# SPM 资源包（本地化字符串等，必须包含）
ditto "$DERIVED/MacBar_MacBar.bundle" "$APP_DIR/Resources/MacBar_MacBar.bundle"

# 签名
codesign --force --deep --sign - /tmp/MacBarBuild/MacBar.app
```

> **注意**：`MacBar_MacBar.bundle` 必须复制，缺失会导致所有本地化字符串显示为 key。

### 4. 打包并发布到 GitHub

```bash
cd /tmp/MacBarBuild
ditto -c -k --keepParent MacBar.app "MacBar-v${VERSION}.zip"
gh release create "v${VERSION}" "MacBar-v${VERSION}.zip" \
  --title "MacBar v${VERSION}" \
  --notes "## v${VERSION}

- ..."
```

## 交付前检查

- 先跑 `swift build`
- 如果改了本地化 key，检查英文和简体中文是否都已补齐
- 如果改了热键、面板、OCR、复制后返回原应用、更新流程，优先在 Xcode 中做一次手动验证
- 如仓库里存在与你任务无关的脏改动，不要回滚它们
