# MacBar — Project Guide for Claude

## 项目概述

macOS 菜单栏剪贴板管理器，使用 Swift Package Manager 构建（非 Xcode project）。无第三方依赖。

- **平台**: macOS 14+
- **语言**: Swift 6.2（严格并发）
- **架构**: MVVM + 单向数据流 Store
- **入口**: `MacBarApp.swift` (@main) → `AppDelegate.swift`

## 构建与运行

```bash
swift build      # 编译
swift run MacBar # 运行
open Package.swift # 用 Xcode 打开
```

## 项目结构

```
MacBar/
├── Package.swift
├── Sources/MacBar/
│   ├── MacBarApp.swift               # @main，空 MenuBarExtra
│   ├── AppDelegate.swift             # panel 管理、窗口定位、全局热键、事件监听
│   ├── Models/
│   │   ├── AppPanel.swift           # 枚举: .clipboard（唯一面板）
│   │   └── ClipboardItem.swift      # 剪贴板历史条目（文本/图片/文件）
│   ├── Services/
│   │   ├── AppServices.swift         # 单例依赖注入容器
│   │   ├── ClipboardMonitor.swift    # NSPasteboard 轮询（0.6s）
│   │   ├── LocalizationManager.swift # 164 语言支持
│   │   ├── OCRService.swift          # macOS Vision 框架图片文字识别
│   │   └── UpdateService.swift       # GitHub Releases 自动更新
│   ├── Stores/
│   │   └── MacBarStore.swift         # 中央状态（@MainActor ObservableObject）
│   ├── Views/
│   │   └── MenuBarRootView.swift     # 根视图（剪贴板列表 + 左侧预览窗格）
│   └── Resources/
│       ├── Assets.xcassets/AppIcon.appiconset/  # 像素风格 App 图标（10 尺寸）
│       └── *.lproj/Localizable.strings          # 164 个语言包
└── scripts/
    └── generate_localizations.py    # 自动生成翻译
```

## 依赖

无第三方依赖。仅使用 Apple 框架：AppKit、SwiftUI、Vision。

## 核心模块

### MacBarStore（状态中心）
`Sources/MacBar/Stores/MacBarStore.swift`

**关键 @Published 属性:**
```swift
clipboardSearchText: String                  // 搜索框文本
clipboardHistory: [ClipboardItem]            // 历史记录（文本 + 图片 + 文件）
pinnedClipboardItemIDs: Set<UUID>            // 置顶 ID 集合
isClipboardMonitoringEnabled: Bool           // 监听开关
clipboardOCRCache: [UUID: String]            // 图片 OCR 缓存（内存，不持久化）
```

**UserDefaults 键名:**
```
macbar.clipboardHistoryData        (JSON)
macbar.pinnedClipboardIDs
macbar.clipboardMonitoringEnabled
```

**容量限制:**
- 条目数量**无限制**
- 文本和图片**无大小限制**

**关键方法:**
```swift
copyClipboardItem(_ id: UUID) -> StoreFeedback?
copyTextToClipboard(_ text: String) -> StoreFeedback
deleteClipboardItem(_ id: UUID)
toggleClipboardItemPinned(_ id: UUID)
clearUnpinnedClipboardItems() -> StoreFeedback?
clearClipboardHistory() -> StoreFeedback?
toggleClipboardMonitoring() -> StoreFeedback
setClipboardOCRText(for id: UUID, text: String)
```

### ClipboardMonitor（剪贴板监听）
`Sources/MacBar/Services/ClipboardMonitor.swift`

`ClipboardCapture` 枚举三种类型：
```swift
enum ClipboardCapture: Equatable {
    case text(String)
    case image(Data)
    case files([URL])   // 文件复制（Finder 复制文件触发）
}
```

检测顺序：**文件 URL → 文本 → 图片**（文件优先，因为复制文件时剪贴板通常也包含文本表示）。

复制文件回剪贴板：`copyFilesToPasteboard(_ fileURLs: [URL])`，使用 `NSPasteboard.writeObjects([NSURL])`。

### OCRService（图片文字识别）
`Sources/MacBar/Services/OCRService.swift`

使用 macOS Vision 框架，完全离线，无需模型加载。

```swift
@MainActor final class OCRService {
    func recognize(nsImage: NSImage) async throws -> String
}
```

- 识别精度: `.accurate`，自动语言检测，语言纠错开启
- 识别在后台线程执行，结果缓存于 `MacBarStore.clipboardOCRCache`

### AppDelegate（窗口管理 + 全局热键）
`Sources/MacBar/AppDelegate.swift`

- 使用 `NSPanel`（非 `NSWindow`）实现无边框悬浮面板
- 本地 + 全局鼠标事件监听，点击面板外自动关闭
- 面板定位在状态栏图标正下方，自动适配屏幕边界
- 打开面板前会记录当前前台应用；复制条目或按 `Esc` 关闭面板时，尝试恢复到之前的前台应用
- **全局热键 `⇧⌘M`**：Carbon `RegisterEventHotKey`（系统级拦截，无需任何权限）+ local NSEvent monitor（面板为 key 时兜底），toggle 面板显示/隐藏
- Swift 6 C callback 桥接：文件级 `private nonisolated(unsafe) weak var _hotKeyDelegate: AppDelegate?` + `DispatchQueue.main.async`

### MenuBarRootView（主视图）
`Sources/MacBar/Views/MenuBarRootView.swift`

剪贴板列表 + 左侧预览窗格（选中条目时滑入）：

**布局:**
- 左侧预览窗格（320px，条目选中时展开）：
  - 文件条目：逐条显示完整路径（可文本选择）+ Reveal in Finder 按钮
  - 图片条目：图片预览 + OCR 结果（含 Copy 按钮）
  - 文本条目：完整文本（可选择）+ 字数/字符数统计
- 右侧主内容（460px）：搜索栏 + 状态胶囊 + 置顶分区 + 最近分区 + 底栏操作区

**列表行显示规则:**
- 第一行（粗体）：文件名（`lastPathComponent`，尾部截断）
- 第二行（灰色小字）：目录路径（`deletingLastPathComponent().path`，从头部截断）
- 悬停 Tooltip：所有文件完整路径（换行分隔）
- 文本条目：第一行显示 `previewTitle`，第二行优先显示 `previewSubtitle`，没有摘要时回退为相对时间

**键盘快捷键:**
- `↑` / `↓`: 导航列表
- `Enter`: 复制选中条目
- `Esc`: 搜索框有内容时清空搜索，否则关闭面板并尝试回到原应用
- `⌘Delete`: 删除选中条目（无论搜索框状态）
- `⌘1–9`: 快速复制最近第 N 条
- `⌘A–Z`: 快速复制第 N 个置顶条目
- `⇧⌘M`: 全局 toggle 面板（在 AppDelegate 注册）
- 复制任意条目（包括 OCR 文本 Copy）后，默认关闭面板并尝试回到原应用

**handleKeyDown 优先级顺序（重要）:**
1. `⌘Delete` → 删除（无论搜索框状态）
2. `⌘1–9` / `⌘A–Z` → 快捷复制（必须在 `isAnyTextInputEditing()` 检查之前）
3. `isAnyTextInputEditing()` 检查 → 返回 false 让搜索框处理
4. 其余快捷键（箭头、Enter、Esc 等）

**关键 state:**
```swift
focusedField: Bool               // 搜索框是否聚焦
selectedClipboardItemID: UUID?   // 当前选中条目
isClipboardOCRProcessing: Bool   // OCR 进行中标志
scrollProxy: ScrollViewProxy?    // 用于滚动到选中条目
```

### LocalizationManager
`Sources/MacBar/Services/LocalizationManager.swift`

- 支持 164 种语言（人口 >500 万）
- 通过 `store.localized("key")` 在 view/store 中引用
- 语言通过底栏菜单切换

## 数据模型

### ClipboardItem
```swift
struct ClipboardItem: Identifiable, Codable, Hashable {
    let id: UUID
    let content: String          // 文本内容（图片/文件时为空字符串）
    let imageTIFFData: Data?     // 图片原始数据
    let fileURLStrings: [String]? // 文件路径列表（file:// URL 字符串）
    let capturedAt: Date
    // 计算属性: isImage, isFile, fileURLs, primaryFileName
    // 计算属性: previewTitle, previewBody, previewSubtitle, wordCount, characterCount
}
```

## 重要设计决策

| 决策 | 原因 |
|------|------|
| 文件优先于文本检测 | 复制文件时剪贴板通常也包含文本表示，必须先检测文件 |
| 无文本/图片大小限制 | 用户需要完整内容，当前实现不对文本、图片或条目数量做截断 |
| OCR 用 Vision 非 LLM | 速度快、准确率高，无需加载模型 |
| 全局热键用 Carbon RegisterEventHotKey | NSEvent global monitor 需要 Input Monitoring 权限，Carbon API 无需任何权限，与 Alfred/Raycast 同方案 |
| NSPanel 而非 NSWindow | 不占 Dock，不出现在 Cmd+Tab 列表 |
| 剪贴板轮询 vs 通知 | NSPasteboard 通知不可靠，轮询兼容性更好 |
| UserDefaults + JSON | 简单可靠，无需 CoreData |
| 无第三方依赖 | 轻量、无网络、启动快 |

## 本地化翻译生成

```bash
cd /Users/patgo/app/MacBar
python3 -m venv .venv && source .venv/bin/activate
pip install langcodes language-data deep-translator Babel
python scripts/generate_localizations.py
```

新增 key 步骤：
1. 在 `en.lproj/Localizable.strings` 添加英文
2. 在 `zh-Hans.lproj/Localizable.strings` 手动添加中文
3. 运行脚本生成其余语言资源
4. 代码中用 `store.localized("key")` 引用

> **注意**：代码中禁止硬编码用户可见字符串（除 `"MacBar"` 应用名和系统按钮 `"OK"` 外）。

## 小红书文案管理

- 当前待发布的小红书统一维护在 `docs/xiaohongshu.md`。
- 系列化管理目录为 `docs/xiaohongshu/`：
  - `README.md`：记录内容台账、命名规则和工作流
  - `TEMPLATE.md`：新文案模板
  - `ideas.md`：后续选题池
  - `drafts/`：按 `YYYY-MM-DD-序号-主题.md` 归档草稿
  - `published/`：已发布定稿
- 如果用户说“这是上一篇的续篇”，新稿必须延续上一篇的叙事，不要重新做一篇通用产品介绍。
- 文案默认优先讲用户痛点、产品定位、体验变化，再讲技术；避免写成提交记录或功能清单。
- 小红书稿件即使保存在 `.md` 文件中，也按纯文本格式书写，不使用 Markdown 标题、列表、加粗、引用和链接语法。
- 每次产出可读草稿后，要同时更新 `docs/xiaohongshu.md` 和对应的 `docs/xiaohongshu/drafts/...` 文件，并补全 `docs/xiaohongshu/README.md` 的台账。

## 常见任务


**修改全局热键**: 两处同步修改：
1. `setupGlobalHotkey()` 中的 `RegisterEventHotKey` 调用（`kVK_ANSI_M` + `cmdKey | shiftKey`）
2. `isHotkeyEvent()` 中的 `event.keyCode == UInt16(kVK_ANSI_M)` + modifier flags 检查
- 使用 `keyCode`（物理键位），不用 `charactersIgnoringModifiers`（受输入法干扰）

**剪贴板图片 OCR 与搜索**:
- 图片条目被捕获后，View 层在 `onAppear`/`onChange(of: clipboardHistory)` 中自动触发 `triggerOCRForUnprocessedImages()`
- OCR 结果缓存于 `clipboardOCRCache[item.id]`，删除/清空条目时同步移除
- `filteredClipboardItems` 搜索时同时检索 OCR 缓存、文件名和文件完整路径
- 预览窗格显示 OCR 文字，顶部有 Copy 按钮可一键复制识别内容；复制后面板默认关闭并尝试回到原应用

**新增面板**: `AppPanel.swift` 添加 case → `MenuBarRootView` 补全相关逻辑（header、clipboardPanelBody 改为 activePanelBody switch、handleKeyDown、handleMoveCommand、showPreview 等）

**自动更新流程**:
- `AppDelegate.applicationDidFinishLaunching` 启动 5s 后触发 `store.checkForUpdates()`
- `MacBarStore.pendingUpdateRelease` 非 nil 时，footer 显示绿色更新按钮
- 点击按钮调用 `store.installUpdate()` → `UpdateService.downloadAndInstall()`
- 安装脚本：`sleep 2` → `rm -rf /Applications/MacBar.app` → `cp -Rf` → `open` → 退出当前进程
- **关键**：必须先 `rm -rf` 再 `cp`，直接 `cp -Rf src /Applications/MacBar.app` 会将新 app 放入旧目录内

**发布 Release 流程**:
```bash
# 1. 构建 archive
xcodebuild archive -scheme MacBar -configuration Release \
  -destination "generic/platform=macOS" -archivePath /tmp/MacBar.xcarchive SKIP_INSTALL=NO

# 2. 组装 app bundle
DERIVED=$(ls -d ~/Library/Developer/Xcode/DerivedData/MacBar-*/Build/Intermediates.noindex/ArchiveIntermediates/MacBar/BuildProductsPath/Release | head -1)
mkdir -p /tmp/MacBarBuild/MacBar.app/Contents/{MacOS,Resources}
cp /tmp/MacBar.xcarchive/Products/usr/local/bin/MacBar /tmp/MacBarBuild/MacBar.app/Contents/MacOS/
cp Sources/MacBar/Info.plist /tmp/MacBarBuild/MacBar.app/Contents/
xcrun actool --compile /tmp/MacBarBuild/MacBar.app/Contents/Resources \
  --platform macosx --minimum-deployment-target 14.0 \
  --app-icon AppIcon --output-partial-info-plist /tmp/actool_partial.plist \
  Sources/MacBar/Resources/Assets.xcassets
ditto "$DERIVED/MacBar_MacBar.bundle" /tmp/MacBarBuild/MacBar.app/Contents/Resources/MacBar_MacBar.bundle
codesign --force --deep --sign - /tmp/MacBarBuild/MacBar.app

# 3. 打包并发布
cd /tmp/MacBarBuild && ditto -c -k --keepParent MacBar.app MacBar-vX.X.X.zip
gh release create vX.X.X MacBar-vX.X.X.zip --title "MacBar vX.X.X" --notes "..."
```
- `MacBar_MacBar.bundle` 必须包含，否则 SPM 资源包找不到，所有本地化字符串不显示
