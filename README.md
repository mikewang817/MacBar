# MacBar

A lightweight macOS menu bar clipboard manager. No cloud, no telemetry, no third-party dependencies — everything stays on your Mac.

![MacBar Screenshot](docs/screenshot.png)

## Features

### Clipboard History
MacBar silently monitors your clipboard and keeps a history of everything you copy — text, images, and files.

- **Text** — full content preserved, no size limit
- **Images** — TIFF data stored as-is, no size limit
- **Files** — captures file copies from Finder, stores full paths

Unlimited history. Pin items to keep them safe from manual clearing.

### Instant Search
Type in the search bar to filter history in real time.

- Searches text content
- Searches OCR-extracted text from images
- Searches file names and paths

### Image OCR
When you select an image item, MacBar automatically runs Apple's Vision framework to extract text. The result appears in the preview pane and is also indexed for search — no model download required.

### File Support
Copy files in Finder as usual. MacBar captures the file references and lets you paste them back or reveal them in Finder from the preview pane.

### Pin Items
Pin frequently used items to keep them at the top, safe from automatic eviction.

### 164 Languages
Switch the UI language at any time from the bottom-left menu. The selection is saved across sessions.

---

## How to Use

### Opening MacBar
- **Click** the menu bar icon (⊟)
- **Global hotkey**: `⇧⌘M` from any app

### Copying an Item
| Action | Result |
|--------|--------|
| Click the copy button on a row | Copy and move item to top |
| Press `Enter` | Copy selected item |
| `⌘1` – `⌘9` | Copy the 1st–9th recent item |
| `⌘A` – `⌘Z` | Copy the 1st–26th pinned item |

### Navigating
| Key | Action |
|-----|--------|
| `↑` / `↓` | Move selection up / down |
| Type | Filter items via search |
| `Esc` | Clear search |

### Managing Items
| Action | How |
|--------|-----|
| Pin / unpin | Click the pin icon on a row |
| Delete item | Select it, press `Delete` or `Backspace` (search must be empty) |
| Reveal file in Finder | Select a file item → click **Reveal in Finder** in the preview pane |

### Preview Pane
Selecting any item opens a preview pane on the left:

- **Text items** — full content with text selection enabled
- **Image items** — full image preview + OCR text with a one-click copy button
- **File items** — full path(s) with text selection + **Reveal in Finder** button

Hover over a file row in the list to see a tooltip with all full paths.

---

## Building from Source

MacBar uses Swift Package Manager — no Xcode project file needed.

```bash
git clone <repo>
cd MacBar
swift build          # compile
swift run MacBar     # run (no GPU features)
open Package.swift   # open in Xcode (recommended)
```

> **Note:** Run via Xcode for full functionality. `swift run` works for basic testing but Vision OCR requires an app bundle.

**Requirements:** macOS 14+, Xcode 15+

---

## Privacy

- No network requests — ever
- No analytics or crash reporting
- All data stored locally in `UserDefaults` on your Mac
- OCR runs entirely on-device via Apple's Vision framework
- Clipboard monitoring can be paused at any time

---

## License

MIT
