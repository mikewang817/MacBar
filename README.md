# MacBar

MacBar is a local-first macOS clipboard manager for people who copy and paste all day. It keeps text, images, and files in one fast menu bar history, with OCR and image-aware paste behavior that fits real Mac workflows.

## What MacBar does well

- Keeps one searchable history for text, images, and Finder files
- Runs OCR locally for image items
- Lets image items work in two ways:
  - `Image` mode for pasting into apps like Word, Notion, chat tools, and editors
  - `File` mode for pasting into Finder folders and file-oriented workflows
- Supports pinning with stable shortcuts
- Works from the menu bar with keyboard-first navigation
- Stays fully local on your Mac

## Key features

### One history for text, images, and files

MacBar captures:

- text copied from any app
- image data copied from screenshots, browsers, and apps
- file references copied from Finder

Everything appears in one list, with preview and quick reuse.

### Smarter image reuse

Images are not always used the same way.

Sometimes you want to paste an image directly into an app. Other times you want to paste it into Finder as a file.

MacBar supports both:

- In the list, image items copy as image content by default
- For image items, `Left` / `Right` switches between `Image` and `File` copy modes
- In the preview pane, image items also offer `Copy as File`

### OCR built in

MacBar uses Apple's Vision framework locally to extract text from image items. OCR text is shown in the preview pane and is indexed for search.

### Fast keyboard flow

- `⇧⌘M` opens the panel from anywhere
- `Enter` copies the selected item
- double-click copies the selected item
- `↑` / `↓` moves selection
- `Esc` clears search first, then closes the panel
- `⌘1` to `⌘9` copies recent items
- pinned items get stable shortcuts from `⌘B` to `⌘Z`
- `⌘,` opens the dedicated Settings window

### Preview pane actions

Depending on item type, MacBar can:

- preview full text
- preview images
- show OCR text
- reveal files in Finder
- AirDrop files and supported image items
- copy image items as either image content or files

## Privacy and behavior

- No cloud sync
- No telemetry
- No analytics SDK
- OCR runs on-device
- Clipboard history stays local
- App Store builds do not use external update checks

## Language support

MacBar currently ships with 7 UI languages:

- English
- Simplified Chinese
- German
- French
- Japanese
- Korean
- Arabic

## Installation

MacBar is distributed through Apple channels.

- TestFlight: [https://testflight.apple.com/join/RFPxZvs8](https://testflight.apple.com/join/RFPxZvs8)
- App Store release: handled through App Store Connect and App Review

This GitHub repository does not publish installable release archives.

## Build from source

MacBar uses Swift Package Manager for source structure and an Xcode project generated from `project.yml`.

### Quick compile check

```bash
swift build
```

### Open in Xcode

```bash
open MacBar.xcodeproj
```

### Regenerate the Xcode project after changing `project.yml`

```bash
xcodegen generate
```

### Debug build from the command line

```bash
xcodebuild \
  -project MacBar.xcodeproj \
  -scheme MacBar \
  -configuration Debug \
  -derivedDataPath /tmp/MacBar-Local \
  build
```

Built app:

```bash
open /tmp/MacBar-Local/Build/Products/Debug/MacBar.app
```

## Public repo note

This repository is public for source visibility and collaboration. Marketing assets, release archives, and website deployment content are handled outside the main app branch.

---

## 中文简介

MacBar 是一个本地优先的 macOS 菜单栏剪贴板管理器，专门面向高频复制粘贴工作流。

它的特点不是只记录文本，而是把：

- 文本
- 图片
- Finder 文件

统一放进一个可搜索的历史中，并且对图片提供两种复用方式：

- `Image`：适合粘贴到 Word、Notion、聊天工具、编辑器
- `File`：适合粘贴到 Finder 文件夹或文件型工作流

另外它还支持：

- 本地 OCR
- 固定常用条目
- 稳定的固定项快捷键
- 菜单栏快速打开
- 独立设置窗口

当前安装与测试渠道：

- TestFlight: [https://testflight.apple.com/join/RFPxZvs8](https://testflight.apple.com/join/RFPxZvs8)

GitHub 仓库不再提供安装包下载。
