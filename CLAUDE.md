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
│   │   ├── AppConfiguration.swift   # 可序列化配置（schema v7）
│   │   ├── AppPanel.swift           # 枚举: .clipboard（唯一面板）
│   │   └── ClipboardItem.swift      # 剪贴板历史条目（文本/图片/文件）
│   ├── Services/
│   │   ├── AppConfigurationManager.swift  # JSON 配置导入/导出
│   │   ├── AppServices.swift              # 单例依赖注入容器
│   │   ├── ClipboardMonitor.swift         # NSPasteboard 轮询（0.6s）
│   │   ├── LocalizationManager.swift      # 164 语言支持
│   │   └── OCRService.swift               # macOS Vision 框架图片文字识别
│   ├── Stores/
│   │   └── MacBarStore.swift         # 中央状态（@MainActor ObservableObject）
│   ├── Views/
│   │   └── MenuBarRootView.swift     # 根视图（剪贴板列表 + 右侧预览窗格）
│   └── Resources/
│       ├── Assets.xcassets/AppIcon.appiconset/  # 像素风格 App 图标（10 尺寸）
│       └── *.lproj/Localizable.strings          # 164 个语言包
└── scripts/
    └── generate_localizations.py    # 自动生成翻译
```

## 依赖

无第三方依赖。仅使用 Apple 框架：AppKit、SwiftUI、Vision、UniformTypeIdentifiers。

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
deleteClipboardItem(_ id: UUID)
toggleClipboardItemPinned(_ id: UUID)
clearUnpinnedClipboardItems() -> StoreFeedback?
clearClipboardHistory() -> StoreFeedback?
toggleClipboardMonitoring() -> StoreFeedback
setClipboardOCRText(for id: UUID, text: String)
exportConfiguration() -> StoreFeedback?
importConfiguration() -> StoreFeedback?
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
- **全局热键 `⇧⌘M`**：global monitor（其他 App 在前台时）+ local monitor（面板为 key 时）双重注册，toggle 面板显示/隐藏

### MenuBarRootView（主视图）
`Sources/MacBar/Views/MenuBarRootView.swift`

剪贴板列表 + 右侧预览窗格（选中条目时滑入）：

**布局:**
- 左侧预览窗格（320px，条目选中时展开）：
  - 文件条目：逐条显示完整路径（可文本选择）+ Reveal in Finder 按钮
  - 图片条目：图片预览 + OCR 结果（含 Copy 按钮）
  - 文本条目：完整文本（可选择）+ 字数/字符数统计
- 右侧主内容（460px）：搜索栏 + 置顶分区 + 最近分区 + 语言底栏

**列表行文件条目双行显示:**
- 第一行（粗体）：文件名（`lastPathComponent`，尾部截断）
- 第二行（灰色小字）：目录路径（`deletingLastPathComponent().path`，从头部截断）
- 悬停 Tooltip：所有文件完整路径（换行分隔）

**键盘快捷键:**
- `↑` / `↓`: 导航列表
- `Enter`: 复制选中条目
- `Delete` / `Backspace`: 删除选中条目（搜索框为空时）
- `⌘1–9`: 快速复制最近第 N 条
- `⌘A–Z`: 快速复制第 N 个置顶条目
- `⇧⌘M`: 全局 toggle 面板（在 AppDelegate 注册）

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
    // 计算属性: previewTitle, previewBody, wordCount, characterCount
}
```

### AppConfiguration（schema v7）
```swift
struct AppConfiguration: Codable {
    let schemaVersion: Int          // 当前 7
    let selectedLanguageCode: String
    let clipboardItems: [ClipboardItem]?
    let clipboardPinnedIDs: [String]?
    let clipboardMonitoringEnabled: Bool?
}
```

## 重要设计决策

| 决策 | 原因 |
|------|------|
| 文件优先于文本检测 | 复制文件时剪贴板通常也包含文本表示，必须先检测文件 |
| 无文本/图片大小限制 | 用户需要完整内容，按条目数量（200条）控制总量 |
| OCR 用 Vision 非 LLM | 速度快、准确率高，无需加载模型 |
| 全局热键双 monitor | global 监听其他 App 在前台时，local 监听面板为 key 时 |
| NSPanel 而非 NSWindow | 不占 Dock，不出现在 Cmd+Tab 列表 |
| 剪贴板轮询 vs 通知 | NSPasteboard 通知不可靠，轮询兼容性更好 |
| UserDefaults + JSON | 简单可靠，无需 CoreData |
| 无第三方依赖 | 轻量、无网络、启动快 |

## 本地化翻译生成

`en.lproj` 和 `zh-Hans.lproj` 当前共有 **38 个活跃 key**，仅覆盖剪贴板功能所需字符串。

```bash
cd /Users/patgo/app/MacBar
python3 -m venv .venv && source .venv/bin/activate
pip install langcodes language-data deep-translator Babel
python scripts/generate_localizations.py
```

新增 key 步骤：
1. 在 `en.lproj/Localizable.strings` 添加英文
2. 在 `zh-Hans.lproj/Localizable.strings` 手动添加中文
3. 运行脚本生成其余 162 种语言
4. 代码中用 `store.localized("key")` 引用

> **注意**：代码中禁止硬编码用户可见字符串（除 `"MacBar"` 应用名和系统按钮 `"OK"` 外）。

## 常见任务


**修改全局热键**: `AppDelegate.isHotkeyEvent()` — 检查 `modifierFlags` 和 `charactersIgnoringModifiers`

**剪贴板图片 OCR 与搜索**:
- 图片条目被捕获后，View 层在 `onAppear`/`onChange(of: clipboardHistory)` 中自动触发 `triggerOCRForUnprocessedImages()`
- OCR 结果缓存于 `clipboardOCRCache[item.id]`，删除/清空条目时同步移除
- `filteredClipboardItems` 搜索时同时检索 OCR 缓存和文件名
- 预览窗格显示 OCR 文字，顶部有 Copy 按钮可一键复制识别内容

**新增面板**: `AppPanel.swift` 添加 case → `MenuBarRootView` 补全相关逻辑（header、clipboardPanelBody 改为 activePanelBody switch、handleKeyDown、handleMoveCommand、showPreview 等）
