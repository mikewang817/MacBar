# MacBar

A lightweight macOS menu bar clipboard manager. No cloud, no telemetry, and no third-party dependencies. Everything stays on your Mac.

![MacBar Screenshot](docs/screenshot2.png)

## Features

### Clipboard History
MacBar silently monitors your clipboard and keeps a history of everything you copy: text, images, and files.

- **Text**: full content preserved, no size limit
- **Images**: TIFF data stored as-is, no size limit
- **Files**: captures file copies from Finder and stores full paths

Unlimited history. Pin items to keep them safe from manual clearing.

### Instant Search
Type in the search bar to filter history in real time.

- Searches text content
- Searches OCR text extracted from images
- Searches file names and full paths

### Image OCR
When you select an image item, MacBar runs Apple's Vision framework locally to extract text. The result appears in the preview pane and is also indexed for search.

### File Support
Copy files in Finder as usual. MacBar captures the file references and lets you paste them back or reveal them in Finder from the preview pane.

### Pin Items
Pin frequently used items to keep them at the top and protect them from manual clearing.

### 164 Languages
Switch the UI language at any time from the bottom-left menu. The selection is saved across sessions.

## How to Use

### Open MacBar
- Click the menu bar icon (`⊟`)
- Use the global hotkey `⇧⌘M` from any app

### Copy an Item
| Action | Result |
|--------|--------|
| Click the copy button on a row | Copy and move the item to the top |
| Press `Enter` | Copy the selected item |
| `⌘1` - `⌘9` | Copy the 1st to 9th recent item |
| `⌘A` - `⌘Z` | Copy the 1st to 26th pinned item |

### Navigate
| Key | Action |
|-----|--------|
| `↑` / `↓` | Move selection up / down |
| Type | Filter items via search |
| `Esc` | Clear search first, then close the panel if search is empty |

### Manage Items
| Action | How |
|--------|-----|
| Pin / unpin | Click the pin icon on a row |
| Delete an item | Select it, then press `⌘Delete` |
| Reveal a file in Finder | Select a file item, then click **Reveal in Finder** in the preview pane |

### Preview Pane
Selecting an item opens a preview pane on the left:

- **Text items**: full content with text selection enabled
- **Image items**: full image preview plus OCR text with a one-click copy button
- **File items**: full path list with text selection plus a **Reveal in Finder** button

Hover over a file row in the list to see a tooltip with the full path.

## Installation

1. Download the latest `MacBar-*.zip` from [Releases](https://github.com/mikewang817/MacBar/releases).
2. Unzip it and move `MacBar.app` to `/Applications`.
3. Launch `MacBar.app` once. macOS may block it on first launch because the app is not notarized.
4. Open **System Settings > Privacy & Security** and scroll to the **Security** section.
5. Find the message about `MacBar.app`, click **Open Anyway**, then confirm **Open**.
6. After approval, MacBar appears in your menu bar as `⊟` with no Dock icon.

Alternative first-launch method:

- Right-click `MacBar.app` in Finder, choose **Open**, then click **Open** again.

Optional Terminal command to remove the quarantine flag:

```bash
xattr -rd com.apple.quarantine /Applications/MacBar.app
```

**Requirements:** macOS 14 or later, Apple Silicon

## Building from Source

MacBar uses Swift Package Manager. There is no `.xcodeproj` in the repository.

```bash
git clone https://github.com/mikewang817/MacBar.git
cd MacBar
swift build
swift run MacBar
open Package.swift
```

Run from Xcode for full validation. `swift run` is suitable for basic checks, but panel behavior, menu bar integration, Vision OCR, and resource loading are best verified from the app bundle in Xcode.

**Requirements:** macOS 14+, Xcode with Swift 6.2 support

## Privacy

- No cloud sync
- No analytics or crash reporting
- No third-party dependencies
- All data is stored locally in `UserDefaults` on your Mac
- OCR runs entirely on-device via Apple's Vision framework
- Clipboard monitoring can be paused at any time

## License

MIT

---

## 中文说明

MacBar 是一个轻量级 macOS 菜单栏剪贴板管理器。无云端、无追踪、无第三方依赖，所有数据都留在你的 Mac 上。

## 功能特性

### 剪贴板历史
MacBar 会静默监控剪贴板，保存你复制过的文本、图片和文件。

- **文本**：完整保存内容，无大小限制
- **图片**：按原始 TIFF 数据存储，无大小限制
- **文件**：捕获 Finder 中的文件复制操作，保存完整路径

历史记录不设上限。你可以固定常用条目，避免被手动清除。

### 即时搜索
在搜索栏输入关键词，实时过滤历史记录。

- 搜索文本内容
- 搜索图片 OCR 识别文字
- 搜索文件名和完整路径

### 图片 OCR
选中图片条目时，MacBar 会在本地调用 Apple Vision 框架提取文字。识别结果会显示在预览面板里，并加入搜索索引。

### 文件支持
在 Finder 中正常复制文件，MacBar 会自动捕获文件引用，支持重新粘贴，也支持在预览面板中直接在 Finder 里显示。

### 固定条目
固定常用条目后，它们会一直显示在顶部，也不会被手动清除误删。

### 164 种语言
可以随时从左下角菜单切换界面语言，选择会跨会话保存。

## 使用方法

### 打开 MacBar
- 点击菜单栏图标 `⊟`
- 在任意应用中使用全局快捷键 `⇧⌘M`

### 复制条目
| 操作 | 效果 |
|------|------|
| 点击行上的复制按钮 | 复制并把条目移到顶部 |
| 按 `Enter` | 复制当前选中条目 |
| `⌘1` - `⌘9` | 复制第 1 到第 9 条最近记录 |
| `⌘A` - `⌘Z` | 复制第 1 到第 26 条固定条目 |

### 导航
| 按键 | 操作 |
|------|------|
| `↑` / `↓` | 上下移动选中项 |
| 直接输入 | 搜索过滤条目 |
| `Esc` | 先清空搜索；如果搜索为空，再关闭面板 |

### 管理条目
| 操作 | 方式 |
|------|------|
| 固定 / 取消固定 | 点击行上的图钉图标 |
| 删除条目 | 选中条目后按 `⌘Delete` |
| 在 Finder 中显示文件 | 选中文件条目，然后点击预览面板中的 **Reveal in Finder** |

### 预览面板
选中任意条目后，左侧会打开预览面板：

- **文本条目**：完整内容，支持文本选择
- **图片条目**：完整图片预览，加 OCR 文字和一键复制按钮
- **文件条目**：完整路径列表，支持文本选择，并带 **Reveal in Finder** 按钮

把鼠标悬停在文件行上，可以看到完整路径提示。

## 安装

1. 从 [Releases](https://github.com/mikewang817/MacBar/releases) 下载最新的 `MacBar-*.zip`。
2. 解压后将 `MacBar.app` 移动到 `/Applications`。
3. 先启动一次 `MacBar.app`。如果 macOS 因为应用未公证而阻止打开，不用关闭安装流程。
4. 打开 **系统设置 > 隐私与安全性**，滚动到 **安全性** 区域。
5. 找到关于 `MacBar.app` 被阻止的提示，点击 **仍要打开**，然后再确认 **打开**。
6. 完成首次放行后，MacBar 会以 `⊟` 图标出现在菜单栏中，不会显示 Dock 图标。

首次启动的另一种方式：

- 在 Finder 中右键点击 `MacBar.app`，选择 **打开**，然后再次点击 **打开**。

如果你想用终端移除隔离标记，也可以执行：

```bash
xattr -rd com.apple.quarantine /Applications/MacBar.app
```

**系统要求：** macOS 14 及以上，Apple Silicon

## 从源码构建

MacBar 使用 Swift Package Manager，仓库中没有 `.xcodeproj`。

```bash
git clone https://github.com/mikewang817/MacBar.git
cd MacBar
swift build
swift run MacBar
open Package.swift
```

建议通过 Xcode 做完整验证。`swift run` 适合基础检查，但面板行为、菜单栏集成、Vision OCR 和资源加载更适合在 Xcode 生成的 app bundle 环境中验证。

**系统要求：** macOS 14+，支持 Swift 6.2 的 Xcode

## 隐私

- 无云同步
- 无统计分析或崩溃上报
- 无第三方依赖
- 所有数据都通过 `UserDefaults` 本地存储在你的 Mac 上
- OCR 完全通过 Apple Vision 框架在设备上运行
- 剪贴板监控可随时暂停

## 许可证

MIT
