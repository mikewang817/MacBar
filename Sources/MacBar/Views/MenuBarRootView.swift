import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager
    let airDropService: AirDropService
    let ocrService: OCRService
    let onPreferredSizeChange: ((CGSize) -> Void)?
    let onRequestClose: ((Bool) -> Void)?
    @State private var focusedField: Bool = false
    @State private var transientFeedback: StoreFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var pendingDestructiveAction: ClipboardDestructiveAction?
    @State private var selectedClipboardItemID: UUID?
    @State private var pendingOCRItemIDs: [UUID] = []
    @State private var runningOCRItemIDs: Set<UUID> = []
    @State private var ocrSourceIndexByItemID: [UUID: Int] = [:]
    @State private var ocrTextChunksByItemID: [UUID: [String]] = [:]
    @State private var completedOCRItemIDs: Set<UUID> = []
    @State private var ocrWorkerTask: Task<Void, Never>?
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

    private struct OCRJob {
        let itemID: UUID
        let sourceIndex: Int
        let sourceCount: Int
        let source: OCRJobSource
    }

    private enum OCRJobSource {
        case imageData(Data)
        case fileURL(URL)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Preview pane (left side, slides in)
            if showPreview, let item = selectedClipboardItem {
                clipboardPreviewPane(item: item)
                    .frame(width: previewWidth)
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

            pruneOCRState()
            syncSelectedClipboardItem()
            enqueueOCRForUnprocessedImages(prioritizing: selectedClipboardItemID)
            installKeyMonitorIfNeeded()
        }
        .onChange(of: showPreview) {
            onPreferredSizeChange?(preferredPanelSize)
        }
        .onChange(of: clipboardNavigationIDs) {
            syncSelectedClipboardItem()
        }
        .onChange(of: store.clipboardHistory) {
            pruneOCRState()
            enqueueOCRForUnprocessedImages(prioritizing: selectedClipboardItemID)
        }
        .onChange(of: selectedClipboardItemID) {
            enqueueSelectedImageOCRIfNeeded()
        }
        .onDisappear {
            focusedField = false
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
            transientFeedback = nil
            ocrWorkerTask?.cancel()
            ocrWorkerTask = nil
            pendingOCRItemIDs.removeAll()
            runningOCRItemIDs.removeAll()
            ocrSourceIndexByItemID.removeAll()
            ocrTextChunksByItemID.removeAll()
            completedOCRItemIDs.removeAll()
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
        let fileURLs = store.clipboardFileURLs(for: item)
        let availableFileURLs = store.clipboardAvailableFileURLs(for: item)
        let missingFileURLs = store.clipboardMissingFileURLs(for: item)
        let previewImage = store.clipboardPreviewImage(for: item)
        let isFileItem = store.clipboardIsFileItem(item)
        let isUnavailableFileItem = store.clipboardIsFileItemUnavailable(item)

        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if isFileItem {
                        if !missingFileURLs.isEmpty {
                            fileAvailabilityNotice(
                                missingCount: missingFileURLs.count,
                                isUnavailable: isUnavailableFileItem
                            )
                        }

                        if let previewImage {
                            clipboardPreviewImageSection(
                                item: item,
                                image: previewImage,
                                showsAirDropAction: false
                            )

                            if !fileURLs.isEmpty {
                                Divider()
                            }
                        }

                        ForEach(fileURLs, id: \.absoluteString) { url in
                            let isMissing = !availableFileURLs.contains(url)

                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: isMissing ? "exclamationmark.triangle.fill" : "doc.fill")
                                    .foregroundStyle(isMissing ? .tertiary : .secondary)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 6) {
                                        Text(url.lastPathComponent)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(isMissing ? .secondary : .primary)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        if isMissing {
                                            fileStatusBadge(
                                                store.localized("ui.clipboard.item.unavailable"),
                                                tint: .secondary
                                            )
                                        }
                                    }

                                    Text(url.path)
                                        .font(.system(size: 11))
                                        .foregroundStyle(isMissing ? .tertiary : .secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }

                        if !fileURLs.isEmpty {
                            Divider()

                            HStack(spacing: 8) {
                                Button {
                                    NSWorkspace.shared.activateFileViewerSelecting(availableFileURLs)
                                } label: {
                                    Label(store.localized("ui.clipboard.button.revealInFinder"), systemImage: "folder")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(availableFileURLs.isEmpty)

                                airDropButton(for: item)
                            }
                        }
                    } else if let previewImage {
                        clipboardPreviewImageSection(
                            item: item,
                            image: previewImage,
                            showsAirDropAction: true
                        )
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
                if isFileItem {
                    Text(store.localized("ui.clipboard.item.fileCount", fileURLs.count))
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
                    .foregroundStyle(
                        isUnavailableFileItem
                            ? AnyShapeStyle(Color.secondary.opacity(0.55))
                            : AnyShapeStyle(Color.secondary)
                    )
                Text(store.clipboardDeleteShortcutHint())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func clipboardPreviewImageSection(
        item: ClipboardItem,
        image: NSImage,
        showsAirDropAction: Bool
    ) -> some View {
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
                if showsAirDropAction {
                    airDropButton(for: item)
                }
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
        } else if runningOCRItemIDs.contains(item.id) || pendingOCRItemIDs.contains(item.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(store.localized("ui.ocr.processing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsAirDropAction {
                    Spacer()
                    airDropButton(for: item)
                }
            }
        } else if showsAirDropAction {
            HStack {
                Spacer()
                airDropButton(for: item)
            }
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

        LazyVStack(alignment: .leading, spacing: 14) {
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
        let fileURLs = store.clipboardFileURLs(for: item)
        let missingFileURLs = store.clipboardMissingFileURLs(for: item)
        let isPinned = store.isClipboardItemPinned(item.id)
        let title = store.clipboardDisplayTitle(for: item)
        let isFileItem = store.clipboardIsFileItem(item)
        let isUnavailableFileItem = store.clipboardIsFileItemUnavailable(item)
        let hasPartiallyMissingFiles = isFileItem && !isUnavailableFileItem && !missingFileURLs.isEmpty
        let canCopyItem = store.clipboardCanCopy(item)

        return HStack(spacing: 10) {
            Group {
                if isFileItem {
                    Image(systemName: "doc.fill")
                        .frame(width: 22)
                        .font(.body.weight(.medium))
                        .foregroundStyle(isUnavailableFileItem ? .secondary : .primary)
                } else if let image = store.clipboardImage(for: item) {
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
                if isFileItem, let fileURL = fileURLs.first {
                    HStack(spacing: 6) {
                        Text(fileTitle(firstFileURL: fileURL, fileCount: fileURLs.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isUnavailableFileItem ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if isUnavailableFileItem {
                            fileStatusBadge(store.localized("ui.clipboard.item.unavailable"), tint: .secondary)
                        } else if hasPartiallyMissingFiles {
                            fileStatusBadge(store.localized("ui.clipboard.item.partiallyUnavailable"), tint: .secondary)
                        }
                    }

                    Text(
                        isUnavailableFileItem
                            ? store.localized("ui.clipboard.preview.fileUnavailableInline")
                            : fileURL.deletingLastPathComponent().path
                    )
                    .font(.caption)
                    .foregroundStyle(isUnavailableFileItem ? .tertiary : .secondary)
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

            HStack(spacing: 6) {
                clipboardRowActionButton(
                    systemImage: isPinned ? "pin.fill" : "pin",
                    iconTint: isPinned ? .orange : .secondary,
                    backgroundTint: isPinned ? .orange : nil,
                    rotationDegrees: 45,
                    help: isPinned
                        ? store.localized("ui.clipboard.help.unpin")
                        : store.localized("ui.clipboard.help.pin")
                ) {
                    store.toggleClipboardItemPinned(item.id)
                }

                airDropButton(for: item, compact: true)

                clipboardRowActionButton(
                    systemImage: "doc.on.doc",
                    iconTint: canCopyItem ? .white : .secondary,
                    backgroundTint: canCopyItem ? .accentColor : nil,
                    isProminent: canCopyItem,
                    isEnabled: canCopyItem,
                    help: store.localized("ui.clipboard.button.copy")
                ) {
                    copyClipboardItemToPasteboard(item.id)
                }
            }
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
        .opacity(isUnavailableFileItem ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { isHovering in
            if isHovering {
                selectedClipboardItemID = item.id
            }
        }
        .onTapGesture {
            selectedClipboardItemID = item.id
        }
        .help(isFileItem ? store.clipboardFileHelpText(for: item) : "")
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
        guard store.clipboardCanCopy(selected) else {
            return
        }
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

        guard store.clipboardCanCopy(items[index]) else {
            return
        }
        copyClipboardItemToPasteboard(items[index].id)
    }

    private func copyRecentClipboardItemByIndex(_ index: Int) {
        let items = store.recentClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        guard store.clipboardCanCopy(items[index]) else {
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

    @MainActor
    private func enqueueSelectedImageOCRIfNeeded() {
        guard let selectedClipboardItem else {
            return
        }

        enqueueOCR(for: [selectedClipboardItem], prioritizing: selectedClipboardItem.id)
    }

    @MainActor
    private func enqueueOCRForUnprocessedImages(prioritizing prioritizedItemID: UUID?) {
        let unprocessedImageItems = store.clipboardHistory.filter {
            itemSupportsOCR($0)
                && store.clipboardOCRCache[$0.id] == nil
                && !completedOCRItemIDs.contains($0.id)
        }
        enqueueOCR(for: unprocessedImageItems, prioritizing: prioritizedItemID)
    }

    @MainActor
    private func enqueueOCR(for items: [ClipboardItem], prioritizing prioritizedItemID: UUID?) {
        pruneOCRState()

        pendingOCRItemIDs.removeAll { itemID in
            completedOCRItemIDs.contains(itemID)
                || (store.clipboardOCRCache[itemID] != nil && ocrSourceIndexByItemID[itemID] == nil)
                || runningOCRItemIDs.contains(itemID)
        }

        if let prioritizedItemID,
           items.contains(where: { $0.id == prioritizedItemID && itemSupportsOCR($0) }),
           store.clipboardOCRCache[prioritizedItemID] == nil,
           !completedOCRItemIDs.contains(prioritizedItemID),
           !runningOCRItemIDs.contains(prioritizedItemID) {
            pendingOCRItemIDs.removeAll { $0 == prioritizedItemID }
            pendingOCRItemIDs.insert(prioritizedItemID, at: 0)
        }

        for item in items where itemSupportsOCR(item) {
            guard store.clipboardOCRCache[item.id] == nil else {
                continue
            }
            guard !completedOCRItemIDs.contains(item.id) else {
                continue
            }
            guard !runningOCRItemIDs.contains(item.id) else {
                continue
            }
            guard !pendingOCRItemIDs.contains(item.id) else {
                continue
            }

            if ocrSourceIndexByItemID[item.id] == nil {
                ocrSourceIndexByItemID[item.id] = 0
            }
            pendingOCRItemIDs.append(item.id)
        }

        startOCRWorkerIfNeeded()
    }

    @MainActor
    private func startOCRWorkerIfNeeded() {
        guard ocrWorkerTask == nil else {
            return
        }

        ocrWorkerTask = Task {
            await processQueuedOCRItems()
        }
    }

    private func processQueuedOCRItems() async {
        while !Task.isCancelled {
            guard let job = await MainActor.run(body: { nextOCRJob() }) else {
                break
            }

            let recognizedText = await recognizeOCRText(for: job.source)
            guard !Task.isCancelled else {
                break
            }
            await MainActor.run {
                finishOCRJob(job: job, recognizedText: recognizedText)
            }
        }

        await MainActor.run {
            ocrWorkerTask = nil
            if !pendingOCRItemIDs.isEmpty {
                startOCRWorkerIfNeeded()
            }
        }
    }

    @MainActor
    private func nextOCRJob() -> OCRJob? {
        while let nextItemID = pendingOCRItemIDs.first {
            pendingOCRItemIDs.removeFirst()

            guard !runningOCRItemIDs.contains(nextItemID) else {
                continue
            }

            guard !completedOCRItemIDs.contains(nextItemID) else {
                clearOCRProgress(for: nextItemID, preserveCompletion: true)
                continue
            }

            guard store.clipboardOCRCache[nextItemID] == nil || ocrSourceIndexByItemID[nextItemID] != nil else {
                clearOCRProgress(for: nextItemID, preserveCompletion: true)
                continue
            }

            guard let item = store.clipboardHistory.first(where: { $0.id == nextItemID }),
                  itemSupportsOCR(item)
            else {
                clearOCRProgress(for: nextItemID)
                continue
            }

            let sourceCount = store.clipboardOCRSourceCount(for: item)
            guard sourceCount > 0 else {
                finalizeOCRItem(itemID: nextItemID)
                continue
            }

            let sourceIndex = ocrSourceIndexByItemID[nextItemID] ?? 0
            guard sourceIndex < sourceCount else {
                finalizeOCRItem(itemID: nextItemID)
                continue
            }

            guard let source = ocrJobSource(for: item, sourceIndex: sourceIndex) else {
                scheduleNextOCRSource(
                    for: nextItemID,
                    completedSourceIndex: sourceIndex,
                    sourceCount: sourceCount,
                    recognizedText: nil
                )
                continue
            }

            runningOCRItemIDs.insert(nextItemID)
            return OCRJob(
                itemID: nextItemID,
                sourceIndex: sourceIndex,
                sourceCount: sourceCount,
                source: source
            )
        }

        return nil
    }

    private func recognizeOCRText(for source: OCRJobSource) async -> String? {
        let rawText: String?

        switch source {
        case let .imageData(imageData):
            rawText = try? await ocrService.recognize(imageData: imageData)
        case let .fileURL(fileURL):
            rawText = try? await ocrService.recognize(fileURL: fileURL)
        }

        guard let trimmedText = rawText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmedText.isEmpty
        else {
            return nil
        }

        return trimmedText
    }

    @MainActor
    private func finishOCRJob(job: OCRJob, recognizedText: String?) {
        runningOCRItemIDs.remove(job.itemID)
        scheduleNextOCRSource(
            for: job.itemID,
            completedSourceIndex: job.sourceIndex,
            sourceCount: job.sourceCount,
            recognizedText: recognizedText
        )
    }

    @MainActor
    private func scheduleNextOCRSource(
        for itemID: UUID,
        completedSourceIndex: Int,
        sourceCount: Int,
        recognizedText: String?
    ) {
        if let recognizedText {
            ocrTextChunksByItemID[itemID, default: []].append(recognizedText)
        }

        let nextSourceIndex = completedSourceIndex + 1
        guard nextSourceIndex < sourceCount else {
            finalizeOCRItem(itemID: itemID)
            return
        }

        ocrSourceIndexByItemID[itemID] = nextSourceIndex
        pendingOCRItemIDs.removeAll { $0 == itemID }
        if selectedClipboardItemID == itemID {
            pendingOCRItemIDs.insert(itemID, at: 0)
        } else {
            pendingOCRItemIDs.append(itemID)
        }
    }

    @MainActor
    private func finalizeOCRItem(itemID: UUID) {
        let recognizedText = (ocrTextChunksByItemID.removeValue(forKey: itemID) ?? [])
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        ocrSourceIndexByItemID.removeValue(forKey: itemID)
        completedOCRItemIDs.insert(itemID)
        pendingOCRItemIDs.removeAll { $0 == itemID }
        runningOCRItemIDs.remove(itemID)

        if !recognizedText.isEmpty {
            store.setClipboardOCRText(for: itemID, text: recognizedText)
        }
    }

    @MainActor
    private func clearOCRProgress(for itemID: UUID, preserveCompletion: Bool = false) {
        pendingOCRItemIDs.removeAll { $0 == itemID }
        runningOCRItemIDs.remove(itemID)
        ocrSourceIndexByItemID.removeValue(forKey: itemID)
        ocrTextChunksByItemID.removeValue(forKey: itemID)
        if !preserveCompletion {
            completedOCRItemIDs.remove(itemID)
        }
    }

    @MainActor
    private func pruneOCRState() {
        let validItemIDs = Set(
            store.clipboardHistory
                .filter(itemSupportsOCR)
                .map(\.id)
        )

        pendingOCRItemIDs.removeAll { itemID in
            !validItemIDs.contains(itemID)
                || completedOCRItemIDs.contains(itemID)
                || (store.clipboardOCRCache[itemID] != nil && ocrSourceIndexByItemID[itemID] == nil)
        }
        runningOCRItemIDs = runningOCRItemIDs.intersection(validItemIDs)
        completedOCRItemIDs = completedOCRItemIDs.intersection(validItemIDs)
        ocrSourceIndexByItemID = ocrSourceIndexByItemID.filter { validItemIDs.contains($0.key) }
        ocrTextChunksByItemID = ocrTextChunksByItemID.filter { validItemIDs.contains($0.key) }
    }

    @MainActor
    private func ocrJobSource(for item: ClipboardItem, sourceIndex: Int) -> OCRJobSource? {
        if !store.clipboardIsFileItem(item) {
            guard sourceIndex == 0, let imageData = store.clipboardImageData(for: item) else {
                return nil
            }
            return .imageData(imageData)
        }

        guard let fileURL = store.clipboardOCRFileURL(for: item, at: sourceIndex) else {
            return nil
        }

        return .fileURL(fileURL)
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
        guard let item = store.clipboardHistory.first(where: { $0.id == itemID }),
              store.clipboardCanCopy(item)
        else {
            return
        }
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

    private func fileTitle(firstFileURL: URL, fileCount: Int) -> String {
        guard fileCount > 1 else {
            return firstFileURL.lastPathComponent
        }

        return "\(firstFileURL.lastPathComponent) · \(store.localized("ui.clipboard.item.fileCount", fileCount))"
    }

    private func textRowSubtitle(for item: ClipboardItem) -> String {
        store.clipboardDisplaySubtitle(for: item)
    }

    private func itemSupportsOCR(_ item: ClipboardItem) -> Bool {
        store.clipboardHasPreviewImage(for: item)
    }

    private func supportsAirDrop(for item: ClipboardItem) -> Bool {
        if store.clipboardIsFileItem(item) {
            return !store.clipboardFileURLs(for: item).isEmpty
        }

        return store.clipboardImage(for: item) != nil
    }

    private func canAirDropClipboardItem(_ item: ClipboardItem) -> Bool {
        if store.clipboardIsFileItem(item) {
            return airDropService.canSendFiles(store.clipboardAvailableFileURLs(for: item))
        }

        guard let image = store.clipboardImage(for: item) else {
            return false
        }

        return airDropService.canSendImage(image)
    }

    private func airDropClipboardItem(_ item: ClipboardItem) {
        if store.clipboardIsFileItem(item) {
            _ = airDropService.sendFiles(store.clipboardAvailableFileURLs(for: item))
            return
        }

        guard let image = store.clipboardImage(for: item) else {
            return
        }

        _ = airDropService.sendImage(image)
    }

    @ViewBuilder
    private func airDropButton(for item: ClipboardItem, compact: Bool = false) -> some View {
        let title = store.localized("ui.clipboard.button.airdrop")

        if compact {
            let canAirDrop = canAirDropClipboardItem(item)

            Button {
                airDropClipboardItem(item)
            } label: {
                clipboardRowActionLabel(
                    systemImage: "paperplane.fill",
                    iconTint: canAirDrop ? .blue : .secondary,
                    backgroundTint: canAirDrop ? .blue : nil
                )
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .disabled(!canAirDrop)
            .help(title)
        } else {
            Button {
                airDropClipboardItem(item)
            } label: {
                Label(title, systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canAirDropClipboardItem(item))
            .help(title)
        }
    }

    private func clipboardRowActionButton(
        systemImage: String,
        iconTint: Color,
        backgroundTint: Color? = nil,
        isProminent: Bool = false,
        isEnabled: Bool = true,
        rotationDegrees: Double = 0,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            clipboardRowActionLabel(
                systemImage: systemImage,
                iconTint: iconTint,
                backgroundTint: backgroundTint,
                isProminent: isProminent,
                rotationDegrees: rotationDegrees
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help(help)
    }

    private func clipboardRowActionLabel(
        systemImage: String,
        iconTint: Color,
        backgroundTint: Color? = nil,
        isProminent: Bool = false,
        rotationDegrees: Double = 0
    ) -> some View {
        let fillStyle: AnyShapeStyle
        let strokeColor: Color

        if let backgroundTint {
            fillStyle = AnyShapeStyle(backgroundTint.opacity(isProminent ? 0.94 : 0.14))
            strokeColor = backgroundTint.opacity(isProminent ? 0.24 : 0.18)
        } else {
            fillStyle = AnyShapeStyle(.thinMaterial)
            strokeColor = Color.white.opacity(0.12)
        }

        return Image(systemName: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(iconTint)
            .rotationEffect(.degrees(rotationDegrees))
            .frame(width: 30, height: 26)
            .background {
                Capsule()
                    .fill(fillStyle)
            }
            .overlay {
                Capsule()
                    .stroke(strokeColor, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(isProminent ? 0.08 : 0.04), radius: 3, y: 1)
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

    private func fileStatusBadge(_ label: String, tint: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.14))
            )
            .foregroundStyle(tint)
    }

    private func fileAvailabilityNotice(missingCount: Int, isUnavailable: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            Text(
                isUnavailable
                    ? store.localized("ui.clipboard.preview.fileUnavailable")
                    : store.localized("ui.clipboard.preview.filesPartiallyUnavailable", missingCount)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
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
