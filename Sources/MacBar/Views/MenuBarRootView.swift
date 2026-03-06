import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager
    let ocrService: OCRService
    let onPreferredSizeChange: ((CGSize) -> Void)?
    let onRequestClose: ((Bool) -> Void)?
    @State private var focusedField: Bool = false
    @State private var transientFeedback: StoreFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var pendingDestructiveAction: ClipboardDestructiveAction?
    @State private var selectedClipboardItemID: UUID?
    @State private var isClipboardOCRProcessing: Bool = false
    @State private var keyDownMonitor: Any?
    @State private var globalKeyDownMonitor: Any?
    @State private var scrollProxy: ScrollViewProxy?

    private let mainWidth: CGFloat = 460
    private let previewWidth: CGFloat = 320
    private let panelHeight: CGFloat = 620

    private var preferredPanelSize: CGSize {
        let previewPaneWidth: CGFloat = showPreview ? (previewWidth + 1) : 0
        return CGSize(width: mainWidth + previewPaneWidth, height: panelHeight)
    }

    private var showPreview: Bool {
        selectedClipboardItem != nil
    }

    private var selectedClipboardItem: ClipboardItem? {
        guard let selectedClipboardItemID else { return nil }
        return clipboardNavigationItems.first { $0.id == selectedClipboardItemID }
    }

    private enum ClipboardDestructiveAction: String {
        case clearUnpinned
        case clearAll

        var titleKey: String {
            switch self {
            case .clearUnpinned:
                "ui.clipboard.confirm.clearUnpinned.title"
            case .clearAll:
                "ui.clipboard.confirm.clearAll.title"
            }
        }

        var messageKey: String {
            switch self {
            case .clearUnpinned:
                "ui.clipboard.confirm.clearUnpinned.message"
            case .clearAll:
                "ui.clipboard.confirm.clearAll.message"
            }
        }

        var buttonKey: String {
            switch self {
            case .clearUnpinned:
                "ui.clipboard.button.clearUnpinned"
            case .clearAll:
                "ui.clipboard.button.clearAll"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Preview pane (left side, slides in)
            if showPreview, let item = selectedClipboardItem {
                clipboardPreviewPane(item: item)
                    .frame(width: previewWidth)
                    .task(id: item.id) {
                        await autoOCRClipboardItem(item)
                    }
                    .transition(.move(edge: .leading).combined(with: .opacity))

                Divider()
            }

            // Main content (right side)
            VStack(alignment: .leading, spacing: 10) {
                header
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        clipboardPanelBody
                            .padding(.vertical, 2)
                    }
                    .onAppear { scrollProxy = proxy }
                }

                Divider()
                footer
            }
            .padding(14)
            .frame(width: mainWidth)
        }
        .frame(height: panelHeight)
        .animation(.easeInOut(duration: 0.2), value: showPreview)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            onPreferredSizeChange?(preferredPanelSize)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = true
            }

            syncSelectedClipboardItem()
            triggerOCRForUnprocessedImages()
            installKeyMonitorIfNeeded()
        }
        .onChange(of: showPreview) {
            onPreferredSizeChange?(preferredPanelSize)
        }
        .onChange(of: clipboardNavigationIDs) {
            syncSelectedClipboardItem()
        }
        .onChange(of: store.clipboardHistory) {
            triggerOCRForUnprocessedImages()
        }
        .onDisappear {
            focusedField = false
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
            transientFeedback = nil
            removeKeyMonitor()
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onSubmit {
            copySelectedClipboardItem()
        }
        .alert(
            pendingDestructiveAction.map { store.localized($0.titleKey) } ?? "",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDestructiveAction = nil
                    }
                }
            ),
            presenting: pendingDestructiveAction
        ) { action in
            Button(store.localized(action.buttonKey), role: .destructive) {
                performDestructiveAction(action)
            }
            Button(store.localized("ui.button.cancel"), role: .cancel) {
                pendingDestructiveAction = nil
            }
        } message: {
            Text(store.localized($0.messageKey))
        }
    }

    // MARK: - Clipboard Preview Pane

    private func clipboardPreviewPane(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if item.isFile {
                        ForEach(item.fileURLs, id: \.absoluteString) { url in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "doc.fill")
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 1)
                                Text(url.path)
                                    .font(.system(size: 12))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        if !item.fileURLs.isEmpty {
                            Divider()

                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
                            } label: {
                                Label(store.localized("ui.clipboard.button.revealInFinder"), systemImage: "folder")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else if let imageData = item.imageTIFFData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

                        Divider()

                        if let ocrText = store.clipboardOCRCache[item.id] {
                            HStack {
                                Text(store.localized("ui.ocr.label"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    copyTextToPasteboard(ocrText)
                                } label: {
                                    Label(store.localized("ui.clipboard.button.copy"), systemImage: "doc.on.doc")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            Text(ocrText)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if isClipboardOCRProcessing && selectedClipboardItem?.id == item.id {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(store.localized("ui.ocr.processing"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !item.content.isEmpty {
                        Text(item.content)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if item.isFile {
                    Text(store.localized("ui.clipboard.item.fileCount", item.fileURLs.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if item.characterCount > 0 {
                    Text(store.localized("ui.clipboard.item.characters", item.characterCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(store.localized("ui.clipboard.item.words", item.wordCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(store.clipboardCapturedAtLabel(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text(store.clipboardCopyShortcutHint())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.clipboardDeleteShortcutHint())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Text("MacBar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                CommandAwareSearchField(
                    text: $store.clipboardSearchText,
                    placeholder: store.localized("ui.clipboard.search.placeholder"),
                    isFocused: focusedField,
                    onFocus: { focusedField = true },
                    onMoveUp: { moveClipboardSelection(delta: -1) },
                    onMoveDown: { moveClipboardSelection(delta: 1) },
                    onSubmit: { copySelectedClipboardItem() },
                    onCancel: { handleCancelAction() }
                )
                .frame(minWidth: 180, maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                statusChip(
                    systemImage: store.isClipboardMonitoringEnabled ? "wave.3.right.circle.fill" : "pause.circle.fill",
                    label: store.localized(
                        store.isClipboardMonitoringEnabled
                            ? "ui.clipboard.status.monitoringOn"
                            : "ui.clipboard.status.monitoringOff"
                    ),
                    tint: store.isClipboardMonitoringEnabled ? .green : .orange
                )

                if store.isClipboardSearching {
                    statusChip(
                        systemImage: "line.3.horizontal.decrease.circle.fill",
                        label: store.localized("ui.clipboard.status.resultsCount", clipboardNavigationItems.count),
                        tint: clipboardNavigationItems.isEmpty ? .secondary : .accentColor
                    )

                    Button(store.localized("ui.clipboard.button.clearSearch")) {
                        clearSearch()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                } else if !store.clipboardHistory.isEmpty {
                    statusChip(
                        systemImage: "tray.full.fill",
                        label: store.localized("ui.clipboard.status.itemsCount", store.clipboardHistory.count),
                        tint: .secondary
                    )
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Clipboard Panel

    private var clipboardNavigationItems: [ClipboardItem] {
        store.pinnedClipboardItems + store.recentClipboardItems
    }

    private var clipboardNavigationIDs: [UUID] {
        clipboardNavigationItems.map(\.id)
    }

    @ViewBuilder
    private var clipboardPanelBody: some View {
        let pinned = store.pinnedClipboardItems
        let recent = store.recentClipboardItems

        VStack(alignment: .leading, spacing: 14) {
            if pinned.isEmpty, recent.isEmpty {
                if store.isClipboardSearching {
                    clipboardSearchEmptyState
                } else {
                    clipboardEmptyState
                }
            } else {
                if !pinned.isEmpty {
                    clipboardPinnedSection(
                        title: store.localized("ui.clipboard.section.pinned"),
                        items: pinned
                    )
                }

                if !recent.isEmpty {
                    clipboardRecentSection(
                        title: store.localized("ui.clipboard.section.recent"),
                        items: recent
                    )
                }
            }
        }
    }

    private var clipboardEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(store.localized("ui.clipboard.empty.title"))
                .font(.subheadline.weight(.semibold))
            Text(
                store.localized(
                    store.isClipboardMonitoringEnabled
                        ? "ui.clipboard.empty.hint.monitoringOn"
                        : "ui.clipboard.empty.hint.monitoringOff"
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if !store.isClipboardMonitoringEnabled {
                Button(store.localized("ui.clipboard.button.resumeMonitoring")) {
                    presentFeedback(store.toggleClipboardMonitoring())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private var clipboardSearchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(store.localized("ui.clipboard.empty.search.title"))
                .font(.subheadline.weight(.semibold))
            Text(store.localized("ui.clipboard.empty.search.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(store.localized("ui.clipboard.button.clearSearch")) {
                clearSearch()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private static let pinnedShortcutLetters: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private func clipboardPinnedSection(title: String, items: [ClipboardItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let shortcutLabel = index < Self.pinnedShortcutLetters.count
                    ? "⌘\(Self.pinnedShortcutLetters[index])"
                    : nil
                clipboardRow(item, shortcutLabel: shortcutLabel, isSelected: selectedClipboardItemID == item.id)
                    .id(item.id)
            }
        }
    }

    private func clipboardRecentSection(title: String, items: [ClipboardItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let shortcutLabel = index < 9 ? "⌘\(index + 1)" : nil
                clipboardRow(item, shortcutLabel: shortcutLabel, isSelected: selectedClipboardItemID == item.id)
                    .id(item.id)
            }
        }
    }

    private func clipboardRow(_ item: ClipboardItem, shortcutLabel: String?, isSelected: Bool) -> some View {
        let isPinned = store.isClipboardItemPinned(item.id)
        let title: String
        if item.isImage {
            title = store.localized("ui.clipboard.item.image")
        } else if item.previewTitle.isEmpty {
            title = store.localized("ui.clipboard.item.empty")
        } else {
            title = item.previewTitle
        }

        return HStack(spacing: 10) {
            Group {
                if item.isFile {
                    Image(systemName: "doc.fill")
                        .frame(width: 22)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                } else if let imageData = item.imageTIFFData, let image = NSImage(data: imageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 22)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if item.isFile, let fileURL = item.fileURLs.first {
                    Text(fileTitle(for: item, firstFileURL: fileURL))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(fileURL.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(textRowSubtitle(for: item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 8)

            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                store.toggleClipboardItemPinned(item.id)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(
                isPinned
                    ? store.localized("ui.clipboard.help.unpin")
                    : store.localized("ui.clipboard.help.pin")
            )

            Button {
                copyClipboardItemToPasteboard(item.id)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    isSelected
                        ? AnyShapeStyle(Color.accentColor.opacity(0.32))
                        : AnyShapeStyle(.quaternary.opacity(0.25))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor.opacity(0.95) : .clear, lineWidth: 1.2)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedClipboardItemID = item.id
        }
        .help(item.isFile ? (item.fileURLs.map(\.path).joined(separator: "\n")) : "")
    }

    // MARK: - Key Monitoring

    private func installKeyMonitorIfNeeded() {
        guard keyDownMonitor == nil else {
            return
        }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyDown(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
            self.keyDownMonitor = nil
        }

        if let globalKeyDownMonitor {
            NSEvent.removeMonitor(globalKeyDownMonitor)
            self.globalKeyDownMonitor = nil
        }
    }

    private func hasMeaningfulText(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isEditingTextInput(for event: NSEvent) -> Bool {
        event.window?.firstResponder is NSTextView
    }

    private func isAnyTextInputEditing() -> Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else {
            return false
        }
        return firstResponder is NSTextView
            || firstResponder is NSSearchField
            || firstResponder is NSTextField
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117

        // ⌘+Delete / ⌘+Backspace: always delete selected item regardless of search text
        if flags == [.command], isDeleteKey {
            deleteSelectedClipboardItem()
            return true
        }

        // CMD+1-9 / CMD+A-Z: always handle regardless of search field focus.
        // The search field is auto-focused whenever the panel is open, so these shortcuts
        // must be checked before isAnyTextInputEditing() or they are never reached.
        if flags == [.command],
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let first = chars.first {
            // CMD+1-9: copy nth recent item
            if let digit = Int(String(first)), (1...9).contains(digit) {
                copyRecentClipboardItemByIndex(digit - 1)
                return true
            }
            // CMD+A-Z: copy nth pinned item
            if let letterIndex = Self.pinnedShortcutLetters.firstIndex(
                of: Character(first.uppercased())
            ) {
                copyPinnedClipboardItemByIndex(letterIndex)
                return true
            }
        }

        if isAnyTextInputEditing() {
            return false
        }

        let isEditingTextInput = isEditingTextInput(for: event)

        guard flags.isEmpty else {
            return false
        }

        if isEditingTextInput {
            return false
        }

        switch event.keyCode {
        case 125: // down
            moveClipboardSelection(delta: 1)
            return true
        case 126: // up
            moveClipboardSelection(delta: -1)
            return true
        case 36, 76: // return / keypad enter
            copySelectedClipboardItem()
            return true
        case 53: // escape
            requestClosePanel(restorePreviousApp: true)
            return true
        default:
            return false
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .up:
            moveClipboardSelection(delta: -1)
        case .down:
            moveClipboardSelection(delta: 1)
        default:
            break
        }
    }

    private func moveClipboardSelection(delta: Int) {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            selectedClipboardItemID = nil
            return
        }

        let currentIndex = selectedClipboardItemID
            .flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        let newID = items[nextIndex].id
        selectedClipboardItemID = newID
        withAnimation {
            scrollProxy?.scrollTo(newID, anchor: .center)
        }
    }

    private func copySelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            return
        }

        let selected = selectedClipboardItemID
            .flatMap { id in items.first(where: { $0.id == id }) } ?? items[0]
        copyClipboardItemToPasteboard(selected.id)
    }

    private func deleteSelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty,
              let selectedID = selectedClipboardItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedID })
        else {
            return
        }

        store.deleteClipboardItem(selectedID)

        let updatedItems = clipboardNavigationItems
        if updatedItems.isEmpty {
            selectedClipboardItemID = nil
        } else {
            let nextIndex = min(currentIndex, updatedItems.count - 1)
            selectedClipboardItemID = updatedItems[nextIndex].id
        }
    }

    private func copyPinnedClipboardItemByIndex(_ index: Int) {
        let items = store.pinnedClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        copyClipboardItemToPasteboard(items[index].id)
    }

    private func copyRecentClipboardItemByIndex(_ index: Int) {
        let items = store.recentClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        copyClipboardItemToPasteboard(items[index].id)
    }

    private func syncSelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            selectedClipboardItemID = nil
            return
        }

        if let selectedClipboardItemID,
           items.contains(where: { $0.id == selectedClipboardItemID }) {
            return
        }

        selectedClipboardItemID = items[0].id
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let transientFeedback {
                feedbackStrip(transientFeedback)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                languageMenu
                clipboardActionsMenu

                Spacer()

                if store.isUpdateInstalling {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(store.localized("ui.update.installing"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let release = store.pendingUpdateRelease {
                    Button {
                        Task { await store.installUpdate() }
                    } label: {
                        Label(
                            store.localized("ui.update.available", release.versionNumber),
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.green)
                }

                Text(AppVersion.displayString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button(store.localized("ui.button.quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    private var languageMenu: some View {
        Menu {
            ForEach(localizationManager.languageOptions) { option in
                Button {
                    localizationManager.selectLanguage(code: option.code)
                } label: {
                    if option.code == localizationManager.selectedLanguageCode {
                        Label(languageLabel(for: option), systemImage: "checkmark")
                    } else {
                        Text(languageLabel(for: option))
                    }
                }
            }
        } label: {
            Label(store.localized("ui.language.menu"), systemImage: "globe")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    private var clipboardActionsMenu: some View {
        Menu {
            Button {
                presentFeedback(store.toggleClipboardMonitoring())
            } label: {
                Label(
                    store.localized(
                        store.isClipboardMonitoringEnabled
                            ? "ui.clipboard.button.pauseMonitoring"
                            : "ui.clipboard.button.resumeMonitoring"
                    ),
                    systemImage: store.isClipboardMonitoringEnabled ? "pause.circle" : "play.circle"
                )
            }

            Divider()

            Button {
                pendingDestructiveAction = .clearUnpinned
            } label: {
                Label(store.localized("ui.clipboard.button.clearUnpinned"), systemImage: "line.3.horizontal.decrease.circle")
            }

            Button(role: .destructive) {
                pendingDestructiveAction = .clearAll
            } label: {
                Label(store.localized("ui.clipboard.button.clearAll"), systemImage: "trash")
            }
        } label: {
            Label(store.localized("ui.menu.actions"), systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
    }

    private func presentFeedback(_ feedback: StoreFeedback?) {
        guard let feedback else {
            return
        }

        feedbackDismissTask?.cancel()
        withAnimation(.easeInOut(duration: 0.18)) {
            transientFeedback = feedback
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    transientFeedback = nil
                }
                feedbackDismissTask = nil
            }
        }
    }

    private func languageLabel(for option: LanguageOption) -> String {
        if option.code == LocalizationManager.systemLanguageCode {
            let systemName = localizationManager.systemLanguageName
            return localizationManager.localized("ui.language.followSystem", systemName)
        }

        return option.label
    }

    private func autoOCRClipboardItem(_ item: ClipboardItem) async {
        guard item.isImage,
              store.clipboardOCRCache[item.id] == nil,
              let imageData = item.imageTIFFData,
              let image = NSImage(data: imageData) else {
            return
        }
        if selectedClipboardItem?.id == item.id {
            isClipboardOCRProcessing = true
        }
        if let text = try? await ocrService.recognize(nsImage: image) {
            store.setClipboardOCRText(for: item.id, text: text)
        }
        if selectedClipboardItem?.id == item.id {
            isClipboardOCRProcessing = false
        }
    }

    private func triggerOCRForUnprocessedImages() {
        for item in store.clipboardHistory where item.isImage && store.clipboardOCRCache[item.id] == nil {
            Task { await autoOCRClipboardItem(item) }
        }
    }

    private func clearSearch() {
        guard !store.clipboardSearchText.isEmpty else {
            return
        }
        store.clipboardSearchText = ""
        focusedField = true
    }

    private func handleCancelAction() {
        if hasMeaningfulText(store.clipboardSearchText) {
            clearSearch()
        } else {
            requestClosePanel(restorePreviousApp: true)
        }
    }

    private func copyClipboardItemToPasteboard(_ itemID: UUID) {
        selectedClipboardItemID = itemID
        let shouldClosePanel = onRequestClose != nil
        let feedback = store.copyClipboardItem(
            itemID,
            persistHistoryImmediately: !shouldClosePanel
        )

        if shouldClosePanel {
            requestClosePanel(restorePreviousApp: true)
            Task { @MainActor in
                store.scheduleClipboardPersistence()
            }
        } else {
            presentFeedback(feedback)
        }
    }

    private func copyTextToPasteboard(_ text: String) {
        let feedback = store.copyTextToClipboard(text)
        if onRequestClose != nil {
            requestClosePanel(restorePreviousApp: true)
        } else {
            presentFeedback(feedback)
        }
    }

    private func performDestructiveAction(_ action: ClipboardDestructiveAction) {
        switch action {
        case .clearUnpinned:
            presentFeedback(store.clearUnpinnedClipboardItems())
        case .clearAll:
            presentFeedback(store.clearClipboardHistory())
        }
        pendingDestructiveAction = nil
    }

    private func fileTitle(for item: ClipboardItem, firstFileURL: URL) -> String {
        guard item.fileURLs.count > 1 else {
            return firstFileURL.lastPathComponent
        }

        return "\(firstFileURL.lastPathComponent) · \(store.localized("ui.clipboard.item.fileCount", item.fileURLs.count))"
    }

    private func textRowSubtitle(for item: ClipboardItem) -> String {
        if !item.previewSubtitle.isEmpty {
            return item.previewSubtitle
        }

        return store.clipboardCapturedAtLabel(for: item)
    }

    private func statusChip(systemImage: String, label: String, tint: Color) -> some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    private func feedbackStrip(_ feedback: StoreFeedback) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(feedback.title)
                    .font(.caption.weight(.semibold))
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func requestClosePanel(restorePreviousApp: Bool) {
        feedbackDismissTask?.cancel()
        DispatchQueue.main.async {
            onRequestClose?(restorePreviousApp)
        }
    }
}

private struct CommandAwareSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Bool
    let onFocus: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onSubmit: () -> Void
    let onCancel: () -> Void

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: CommandAwareSearchField

        init(parent: CommandAwareSearchField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onFocus()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else {
                return
            }

            if parent.text != field.stringValue {
                parent.text = field.stringValue
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.focusRingType = .default
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = true
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.parent = self

        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }

        guard let window = nsView.window else {
            if nsView.stringValue != text {
                nsView.stringValue = text
            }
            return
        }

        let firstResponder = window.firstResponder
        let isFieldResponder = firstResponder === nsView
        let isEditorResponder = firstResponder === nsView.currentEditor()
        let isEditing = isFieldResponder || isEditorResponder
        let isOtherTextInputFocused = !isEditing && (
            firstResponder is NSTextView
            || firstResponder is NSSearchField
            || firstResponder is NSTextField
        )

        if !isEditing, nsView.stringValue != text {
            nsView.stringValue = text
        }

        if isFocused {
            if !isEditing && !isOtherTextInputFocused {
                window.makeFirstResponder(nsView)
            }
        }
    }
}
