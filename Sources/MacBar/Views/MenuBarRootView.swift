import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: MacBarStore
    let airDropService: AirDropService
    let ocrService: OCRService
    let onPreferredSizeChange: ((CGSize) -> Void)?
    let onRequestClose: ((Bool) -> Void)?
    @State private var focusedField: Bool = false
    @State private var transientFeedback: StoreFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?
    @State private var pendingDestructiveAction: ClipboardDestructiveAction?
    @State private var selectedClipboardItemID: UUID?
    @State private var hoveredClipboardItemID: UUID?
    @State private var isHoverSelectionSuspended: Bool = false
    @State private var ocrQueue = OCRQueueState()
    @State private var ocrWorkerTask: Task<Void, Never>?
    @State private var hoverSelectionTask: Task<Void, Never>?
    @State private var hoverExitTask: Task<Void, Never>?
    @State private var keyDownMonitor: Any?
    @State private var globalKeyDownMonitor: Any?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var selectedImageCopyMode: ClipboardImageCopyMode = .image
    @State private var showsImageCopyModeTip: Bool = false

    private let mainWidth: CGFloat = 460
    private let previewWidth: CGFloat = 320
    private let panelHeight: CGFloat = 620
    private let hoverSelectionDelay: Duration = .milliseconds(45)
    private let hoverExitDelay: Duration = .milliseconds(70)

    private var preferredPanelSize: CGSize {
        let previewPaneWidth: CGFloat = showPreview ? (previewWidth + 1) : 0
        return CGSize(width: mainWidth + previewPaneWidth, height: panelHeight)
    }

    private var showPreview: Bool {
        store.showsPreviewPane && selectedClipboardItem != nil
    }

    private var selectedClipboardItem: ClipboardItem? {
        guard let selectedClipboardItemID else { return nil }
        return clipboardNavigationItems.first { $0.id == selectedClipboardItemID }
    }

    private var highlightedClipboardItemID: UUID? {
        hoveredClipboardItemID ?? selectedClipboardItemID
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

    private struct OCRQueueState {
        var pendingItemIDs: [UUID] = []
        var runningItemIDs: Set<UUID> = []
        var sourceIndexByItemID: [UUID: Int] = [:]
        var textChunksByItemID: [UUID: [String]] = [:]
        var completedItemIDs: Set<UUID> = []

        mutating func reset(resetCompleted: Bool) {
            pendingItemIDs.removeAll()
            runningItemIDs.removeAll()
            sourceIndexByItemID.removeAll()
            textChunksByItemID.removeAll()
            if resetCompleted {
                completedItemIDs.removeAll()
            }
        }

        mutating func clearProgress(for itemID: UUID, preserveCompletion: Bool = false) {
            pendingItemIDs.removeAll { $0 == itemID }
            runningItemIDs.remove(itemID)
            sourceIndexByItemID.removeValue(forKey: itemID)
            textChunksByItemID.removeValue(forKey: itemID)
            if !preserveCompletion {
                completedItemIDs.remove(itemID)
            }
        }
    }

    private enum ClipboardImageCopyMode {
        case image
        case file
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
            store.refreshClipboardFileAvailability(force: true)
            store.refreshLaunchAtLoginStatus()
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
            reprioritizeSelectedClipboardItemForOCR()
        }
        .onChange(of: store.ocrMode) {
            refreshOCRProcessing()
        }
        .onDisappear {
            focusedField = false
            feedbackDismissTask?.cancel()
            feedbackDismissTask = nil
            transientFeedback = nil
            ocrWorkerTask?.cancel()
            ocrWorkerTask = nil
            hoverSelectionTask?.cancel()
            hoverExitTask?.cancel()
            hoverExitTask = nil
            hoverSelectionTask = nil
            hoveredClipboardItemID = nil
            ocrQueue.reset(resetCompleted: true)
            removeKeyMonitor()
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onSubmit {
            copySelectedClipboardItem(triggeredByKeyboard: true)
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
        .alert(
            store.localized("ui.clipboard.tip.imageCopyMode.title"),
            isPresented: $showsImageCopyModeTip
        ) {
            Button(store.localized("ui.button.gotIt"), role: .cancel) {}
        } message: {
            Text(store.localized("ui.clipboard.tip.imageCopyMode.message"))
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
        let canCopyAsFile = store.clipboardCanCopyAsFile(item)

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
                                showsAirDropAction: false,
                                showsCopyAsFileAction: false
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
                                    store.refreshClipboardFileAvailability(force: true)
                                    _ = store.withClipboardFileAccess(for: item) { refreshedURLs in
                                        NSWorkspace.shared.activateFileViewerSelecting(refreshedURLs)
                                    }
                                } label: {
                                    Text(store.localized("ui.clipboard.button.revealInFinder"))
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(availableFileURLs.isEmpty)

                                if canCopyAsFile {
                                    Button {
                                        copyClipboardItemAsFileToPasteboard(item.id)
                                    } label: {
                                        Text(store.localized("ui.clipboard.button.copyAsFile"))
                                            .font(.caption)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                airDropButton(for: item)
                            }
                        }
                    } else if let previewImage {
                        clipboardPreviewImageSection(
                            item: item,
                            image: previewImage,
                            showsAirDropAction: true,
                            showsCopyAsFileAction: canCopyAsFile
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
                if let selectedClipboardItem, supportsAlternateFileCopy(for: selectedClipboardItem) {
                    Text("← \(store.localized("ui.clipboard.item.image")) · → \(store.localized("ui.clipboard.item.file"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        showsAirDropAction: Bool,
        showsCopyAsFileAction: Bool
    ) -> some View {
        let showsSupplementaryContent =
            store.clipboardOCRCache[item.id] != nil
            || ocrQueue.runningItemIDs.contains(item.id)
            || ocrQueue.pendingItemIDs.contains(item.id)
            || showsAirDropAction
            || showsCopyAsFileAction

        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

        if showsSupplementaryContent {
            Divider()
        }

        if let ocrText = store.clipboardOCRCache[item.id] {
            HStack {
                Text(store.localized("ui.ocr.label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showsAirDropAction {
                    airDropButton(for: item)
                }
                if showsCopyAsFileAction {
                    Button {
                        copyClipboardItemAsFileToPasteboard(item.id)
                    } label: {
                        Text(store.localized("ui.clipboard.button.copyAsFile"))
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button {
                    copyTextToPasteboard(ocrText)
                } label: {
                    Text(store.localized("ui.clipboard.button.copy"))
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(ocrText)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if ocrQueue.runningItemIDs.contains(item.id) || ocrQueue.pendingItemIDs.contains(item.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(store.localized("ui.ocr.processing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if showsAirDropAction || showsCopyAsFileAction {
                    Spacer()
                }
                if showsAirDropAction {
                    airDropButton(for: item)
                }
                if showsCopyAsFileAction {
                    Button {
                        copyClipboardItemAsFileToPasteboard(item.id)
                    } label: {
                        Text(store.localized("ui.clipboard.button.copyAsFile"))
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        } else if showsAirDropAction || showsCopyAsFileAction {
            HStack {
                Spacer()
                if showsCopyAsFileAction {
                    Button {
                        copyClipboardItemAsFileToPasteboard(item.id)
                    } label: {
                        Text(store.localized("ui.clipboard.button.copyAsFile"))
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if showsAirDropAction {
                    airDropButton(for: item)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View { clipboardHeader }

    private var clipboardHeader: some View {
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
                    onMoveLeft: { handleSelectedImageCopyModeChange(.image) },
                    onMoveRight: { handleSelectedImageCopyModeChange(.file) },
                    onSubmit: { copySelectedClipboardItem(triggeredByKeyboard: true) },
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

                    if let selectedClipboardItem, supportsAlternateFileCopy(for: selectedClipboardItem) {
                        statusChip(
                            systemImage: selectedImageCopyMode == .image ? "photo.fill" : "doc.fill",
                            label: selectedImageCopyMode == .image
                                ? store.localized("ui.clipboard.item.image")
                                : store.localized("ui.clipboard.item.file"),
                            tint: .secondary
                        )
                    }

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

    private var clipboardListIdentity: String {
        let itemIDs = clipboardNavigationIDs.map(\.uuidString).joined(separator: ",")
        return "\(store.clipboardSearchText)|\(itemIDs)"
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
        .id(clipboardListIdentity)
    }

    private var clipboardEmptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(store.localized("ui.clipboard.empty.tutorial.title"))
                        .font(.headline.weight(.semibold))
                }

                Text(
                    store.localized(
                        store.isClipboardMonitoringEnabled
                            ? "ui.clipboard.empty.tutorial.subtitle.monitoringOn"
                            : "ui.clipboard.empty.tutorial.subtitle.monitoringOff"
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                emptyTutorialStep(
                    number: 1,
                    titleKey: "ui.clipboard.empty.tutorial.step1.title",
                    bodyKey: "ui.clipboard.empty.tutorial.step1.body"
                )
                emptyTutorialStep(
                    number: 2,
                    titleKey: "ui.clipboard.empty.tutorial.step2.title",
                    bodyKey: "ui.clipboard.empty.tutorial.step2.body"
                )
                emptyTutorialStep(
                    number: 3,
                    titleKey: "ui.clipboard.empty.tutorial.step3.title",
                    bodyKey: "ui.clipboard.empty.tutorial.step3.body"
                )
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !store.isClipboardMonitoringEnabled {
                Button(store.localized("ui.clipboard.button.resumeMonitoring")) {
                    presentFeedback(store.toggleClipboardMonitoring())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func emptyTutorialStep(number: Int, titleKey: String, bodyKey: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.secondary.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(store.localized(titleKey))
                    .font(.subheadline.weight(.semibold))
                Text(store.localized(bodyKey))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private func clipboardPinnedSection(title: String, items: [ClipboardItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items, id: \.id) { item in
                let shortcutLabel = store.pinnedClipboardShortcutLabel(for: item.id)
                clipboardRow(item, shortcutLabel: shortcutLabel, isSelected: highlightedClipboardItemID == item.id)
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
                clipboardRow(item, shortcutLabel: shortcutLabel, isSelected: highlightedClipboardItemID == item.id)
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
        let supportsAlternateCopyMode = supportsAlternateFileCopy(for: item)
        let activeCopyMode = isSelected && supportsAlternateCopyMode ? selectedImageCopyMode : .image
        let canCopyItem = activeCopyMode == .file
            ? store.clipboardCanCopyAsFile(item)
            : store.clipboardCanCopy(item)
        let copyButtonSystemImage = activeCopyMode == .file ? "doc.badge.plus" : "doc.on.doc"
        let copyButtonHelp = activeCopyMode == .file
            ? store.localized("ui.clipboard.button.copyAsFile")
            : store.localized("ui.clipboard.button.copy")

        return HStack(spacing: 10) {
            HStack(spacing: 10) {
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

                if isSelected && supportsAlternateCopyMode {
                    clipboardCopyModeBadge(activeCopyMode)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                isHoverSelectionSuspended = false
                commitClipboardSelection(item.id, clearsHoverState: false)
            }
            .onTapGesture(count: 2) {
                isHoverSelectionSuspended = false
                performPrimaryClipboardAction(for: item.id)
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
                    systemImage: copyButtonSystemImage,
                    iconTint: canCopyItem ? .white : .secondary,
                    backgroundTint: canCopyItem ? .accentColor : nil,
                    isProminent: canCopyItem,
                    isEnabled: canCopyItem,
                    help: copyButtonHelp
                ) {
                    performPrimaryClipboardAction(for: item.id)
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
        .onHover { isHovering in
            handleClipboardRowHover(isHovering: isHovering, itemID: item.id)
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

        // CMD+1-9 / pinned CMD shortcuts: always handle regardless of search field focus.
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
            // Pinned shortcuts are assigned per item and intentionally never use CMD+A.
            if let pinnedItem = store.pinnedClipboardItem(forShortcutKey: first) {
                if store.clipboardIsFileItem(pinnedItem) {
                    store.refreshClipboardFileAvailability(force: true)
                }
                guard store.clipboardCanCopy(pinnedItem) else {
                    return true
                }
                copyClipboardItemToPasteboard(pinnedItem.id)
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
        case 123: // left
            return handleSelectedImageCopyModeChange(.image)
        case 124: // right
            return handleSelectedImageCopyModeChange(.file)
        case 36, 76: // return / keypad enter
            copySelectedClipboardItem(triggeredByKeyboard: true)
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
            cancelHoverSelection()
            selectedClipboardItemID = nil
            return
        }

        let currentIndex = selectedClipboardItemID
            .flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        let newID = items[nextIndex].id
        suspendHoverSelection()
        commitClipboardSelection(newID, clearsHoverState: false)
        scrollProxy?.scrollTo(newID)
    }

    private func copySelectedClipboardItem(triggeredByKeyboard: Bool = false) {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            return
        }

        let selected = selectedClipboardItemID
            .flatMap { id in items.first(where: { $0.id == id }) } ?? items[0]
        if store.clipboardIsFileItem(selected) {
            store.refreshClipboardFileAvailability(force: true)
        }
        let shouldShowTip = triggeredByKeyboard
            && supportsAlternateFileCopy(for: selected)
            && !store.hasSeenImageCopyModeTip
        let didCopy = performPrimaryClipboardAction(
            for: selected.id,
            closesPanelOverride: shouldShowTip ? false : nil
        )
        if triggeredByKeyboard, didCopy {
            presentImageCopyModeTipIfNeeded(for: selected)
        }
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
            cancelHoverSelection()
            selectedClipboardItemID = nil
        } else {
            let nextIndex = min(currentIndex, updatedItems.count - 1)
            commitClipboardSelection(updatedItems[nextIndex].id, clearsHoverState: true)
        }
    }

    private func copyRecentClipboardItemByIndex(_ index: Int) {
        let items = store.recentClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        if store.clipboardIsFileItem(items[index]) {
            store.refreshClipboardFileAvailability(force: true)
        }
        guard store.clipboardCanCopy(items[index]) else {
            return
        }
        copyClipboardItemToPasteboard(items[index].id)
    }

    private func syncSelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            cancelHoverSelection()
            selectedClipboardItemID = nil
            selectedImageCopyMode = .image
            return
        }

        if let hoveredClipboardItemID,
           !items.contains(where: { $0.id == hoveredClipboardItemID }) {
            cancelHoverSelection()
        }

        if let selectedClipboardItemID,
           items.contains(where: { $0.id == selectedClipboardItemID }) {
            return
        }

        selectedClipboardItemID = items[0].id
        selectedImageCopyMode = .image
    }

    private func handleClipboardRowHover(isHovering: Bool, itemID: UUID) {
        if isHovering {
            guard !isHoverSelectionSuspended else {
                return
            }

            hoverExitTask?.cancel()
            hoverExitTask = nil
            hoveredClipboardItemID = itemID
            scheduleHoverSelectionCommit(for: itemID)
            return
        }

        if isHoverSelectionSuspended {
            isHoverSelectionSuspended = false
            return
        }

        guard hoveredClipboardItemID == itemID else {
            return
        }

        scheduleHoverSelectionExit(for: itemID)
    }

    private func scheduleHoverSelectionCommit(for itemID: UUID) {
        guard selectedClipboardItemID != itemID else {
            hoverSelectionTask?.cancel()
            hoverSelectionTask = nil
            return
        }

        hoverSelectionTask?.cancel()
        hoverSelectionTask = Task { @MainActor in
            try? await Task.sleep(for: hoverSelectionDelay)
            guard !Task.isCancelled, hoveredClipboardItemID == itemID else {
                return
            }

            commitClipboardSelection(itemID, clearsHoverState: false)
        }
    }

    private func cancelHoverSelection() {
        hoverSelectionTask?.cancel()
        hoverExitTask?.cancel()
        hoverExitTask = nil
        hoverSelectionTask = nil
        hoveredClipboardItemID = nil
    }

    private func suspendHoverSelection() {
        isHoverSelectionSuspended = true
        cancelHoverSelection()
    }

    private func commitClipboardSelection(_ itemID: UUID, clearsHoverState: Bool) {
        if clearsHoverState {
            cancelHoverSelection()
        } else {
            hoverSelectionTask?.cancel()
            hoverSelectionTask = nil
            hoverExitTask?.cancel()
            hoverExitTask = nil
        }

        guard selectedClipboardItemID != itemID else {
            return
        }

        selectedClipboardItemID = itemID
        selectedImageCopyMode = .image
    }

    private func scheduleHoverSelectionExit(for itemID: UUID) {
        hoverExitTask?.cancel()
        hoverExitTask = Task { @MainActor in
            try? await Task.sleep(for: hoverExitDelay)
            guard !Task.isCancelled, hoveredClipboardItemID == itemID else {
                return
            }

            cancelHoverSelection()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let transientFeedback {
                feedbackStrip(transientFeedback)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack {
                clipboardActionsMenu
                panelToggleButton

                Spacer()

                if BuildInfo.supportsExternalUpdates {
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
                }

                Button(store.localized("ui.button.quit")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
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

    private var panelToggleButton: some View {
        Button {
            openSettingsWindow()
        } label: {
            Label(
                store.localized("ui.settings.button.open"),
                systemImage: "gearshape"
            )
        }
        .buttonStyle(.borderless)
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

    @MainActor
    private func reprioritizeSelectedClipboardItemForOCR() {
        guard store.ocrMode != .disabled else {
            stopOCRProcessing(resetCompleted: false)
            return
        }

        guard let selectedClipboardItem else {
            if store.ocrMode == .selectedOnly {
                stopOCRProcessing(resetCompleted: false)
            }
            return
        }

        guard itemSupportsOCR(selectedClipboardItem) else {
            if store.ocrMode == .selectedOnly {
                stopOCRProcessing(resetCompleted: false)
            }
            return
        }

        let selectedItemID = selectedClipboardItem.id
        guard store.clipboardOCRCache[selectedItemID] == nil, !ocrQueue.completedItemIDs.contains(selectedItemID) else {
            return
        }

        switch store.ocrMode {
        case .disabled:
            stopOCRProcessing(resetCompleted: false)
        case .selectedOnly:
            stopOCRProcessing(resetCompleted: false)
            ocrQueue.sourceIndexByItemID[selectedItemID] = ocrQueue.sourceIndexByItemID[selectedItemID] ?? 0
            ocrQueue.pendingItemIDs = [selectedItemID]
            startOCRWorkerIfNeeded()
        case .automatic:
            ocrQueue.pendingItemIDs.removeAll { $0 == selectedItemID }
            if !ocrQueue.runningItemIDs.contains(selectedItemID) {
                ocrQueue.sourceIndexByItemID[selectedItemID] = ocrQueue.sourceIndexByItemID[selectedItemID] ?? 0
                ocrQueue.pendingItemIDs.insert(selectedItemID, at: 0)
            }
            startOCRWorkerIfNeeded()
        }
    }

    @MainActor
    private func enqueueOCRForUnprocessedImages(prioritizing prioritizedItemID: UUID?) {
        switch store.ocrMode {
        case .disabled:
            stopOCRProcessing(resetCompleted: false)
            return
        case .selectedOnly:
            stopOCRProcessing(resetCompleted: false)

            guard
                let prioritizedItemID,
                let prioritizedItem = store.clipboardHistory.first(where: { $0.id == prioritizedItemID }),
                itemSupportsOCR(prioritizedItem),
                store.clipboardOCRCache[prioritizedItem.id] == nil,
                !ocrQueue.completedItemIDs.contains(prioritizedItem.id)
            else {
                return
            }

            enqueueOCR(for: [prioritizedItem], prioritizing: prioritizedItem.id)
            return
        case .automatic:
            break
        }

        let unprocessedImageItems = store.clipboardHistory.filter {
            itemSupportsOCR($0)
                && store.clipboardOCRCache[$0.id] == nil
                && !ocrQueue.completedItemIDs.contains($0.id)
        }
        enqueueOCR(for: unprocessedImageItems, prioritizing: prioritizedItemID)
    }

    @MainActor
    private func enqueueOCR(for items: [ClipboardItem], prioritizing prioritizedItemID: UUID?) {
        pruneOCRState()

        ocrQueue.pendingItemIDs.removeAll { itemID in
            ocrQueue.completedItemIDs.contains(itemID)
                || (store.clipboardOCRCache[itemID] != nil && ocrQueue.sourceIndexByItemID[itemID] == nil)
                || ocrQueue.runningItemIDs.contains(itemID)
        }

        if let prioritizedItemID,
           items.contains(where: { $0.id == prioritizedItemID && itemSupportsOCR($0) }),
           store.clipboardOCRCache[prioritizedItemID] == nil,
           !ocrQueue.completedItemIDs.contains(prioritizedItemID),
           !ocrQueue.runningItemIDs.contains(prioritizedItemID) {
            ocrQueue.pendingItemIDs.removeAll { $0 == prioritizedItemID }
            ocrQueue.pendingItemIDs.insert(prioritizedItemID, at: 0)
        }

        for item in items where itemSupportsOCR(item) {
            guard store.clipboardOCRCache[item.id] == nil else {
                continue
            }
            guard !ocrQueue.completedItemIDs.contains(item.id) else {
                continue
            }
            guard !ocrQueue.runningItemIDs.contains(item.id) else {
                continue
            }
            guard !ocrQueue.pendingItemIDs.contains(item.id) else {
                continue
            }

            if ocrQueue.sourceIndexByItemID[item.id] == nil {
                ocrQueue.sourceIndexByItemID[item.id] = 0
            }
            ocrQueue.pendingItemIDs.append(item.id)
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
            if !ocrQueue.pendingItemIDs.isEmpty {
                startOCRWorkerIfNeeded()
            }
        }
    }

    @MainActor
    private func nextOCRJob() -> OCRJob? {
        while let nextItemID = ocrQueue.pendingItemIDs.first {
            ocrQueue.pendingItemIDs.removeFirst()

            guard !ocrQueue.runningItemIDs.contains(nextItemID) else {
                continue
            }

            guard !ocrQueue.completedItemIDs.contains(nextItemID) else {
                clearOCRProgress(for: nextItemID, preserveCompletion: true)
                continue
            }

            guard store.clipboardOCRCache[nextItemID] == nil || ocrQueue.sourceIndexByItemID[nextItemID] != nil else {
                clearOCRProgress(for: nextItemID, preserveCompletion: true)
                continue
            }

            guard let item = store.clipboardHistory.first(where: { $0.id == nextItemID }),
                  itemSupportsOCR(item)
            else {
                clearOCRProgress(for: nextItemID)
                continue
            }

            let sourceCount = store.clipboardOCRSources(for: item).count
            guard sourceCount > 0 else {
                finalizeOCRItem(itemID: nextItemID)
                continue
            }

            let sourceIndex = ocrQueue.sourceIndexByItemID[nextItemID] ?? 0
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

            ocrQueue.runningItemIDs.insert(nextItemID)
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
        ocrQueue.runningItemIDs.remove(job.itemID)
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
            ocrQueue.textChunksByItemID[itemID, default: []].append(recognizedText)
        }

        let nextSourceIndex = completedSourceIndex + 1
        guard nextSourceIndex < sourceCount else {
            finalizeOCRItem(itemID: itemID)
            return
        }

        ocrQueue.sourceIndexByItemID[itemID] = nextSourceIndex
        ocrQueue.pendingItemIDs.removeAll { $0 == itemID }
        if selectedClipboardItemID == itemID {
            ocrQueue.pendingItemIDs.insert(itemID, at: 0)
        } else {
            ocrQueue.pendingItemIDs.append(itemID)
        }
    }

    @MainActor
    private func finalizeOCRItem(itemID: UUID) {
        let recognizedText = (ocrQueue.textChunksByItemID.removeValue(forKey: itemID) ?? [])
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        ocrQueue.sourceIndexByItemID.removeValue(forKey: itemID)
        ocrQueue.completedItemIDs.insert(itemID)
        ocrQueue.pendingItemIDs.removeAll { $0 == itemID }
        ocrQueue.runningItemIDs.remove(itemID)

        if !recognizedText.isEmpty {
            store.setClipboardOCRText(for: itemID, text: recognizedText)
        }
    }

    @MainActor
    private func clearOCRProgress(for itemID: UUID, preserveCompletion: Bool = false) {
        ocrQueue.clearProgress(for: itemID, preserveCompletion: preserveCompletion)
    }

    @MainActor
    private func pruneOCRState() {
        let validItemIDs = Set(
            store.clipboardHistory
                .filter(itemSupportsOCR)
                .map(\.id)
        )

        ocrQueue.pendingItemIDs.removeAll { itemID in
            !validItemIDs.contains(itemID)
                || ocrQueue.completedItemIDs.contains(itemID)
                || (store.clipboardOCRCache[itemID] != nil && ocrQueue.sourceIndexByItemID[itemID] == nil)
        }
        ocrQueue.runningItemIDs = ocrQueue.runningItemIDs.intersection(validItemIDs)
        ocrQueue.completedItemIDs = ocrQueue.completedItemIDs.intersection(validItemIDs)
        ocrQueue.sourceIndexByItemID = ocrQueue.sourceIndexByItemID.filter { validItemIDs.contains($0.key) }
        ocrQueue.textChunksByItemID = ocrQueue.textChunksByItemID.filter { validItemIDs.contains($0.key) }
    }

    @MainActor
    private func ocrJobSource(for item: ClipboardItem, sourceIndex: Int) -> OCRJobSource? {
        guard let source = store.clipboardOCRSource(for: item, at: sourceIndex) else {
            return nil
        }

        switch source {
        case .clipboardImageData:
            guard let imageData = store.clipboardImageData(for: item) else {
                return nil
            }
            return .imageData(imageData)
        case .fileURL:
            guard let imageData = store.clipboardOCRImageData(for: item, at: sourceIndex) else {
                return nil
            }
            return .imageData(imageData)
        }
    }

    private func clearSearch() {
        guard !store.clipboardSearchText.isEmpty else {
            return
        }
        store.clipboardSearchText = ""
        focusedField = true
    }

    @MainActor
    private func refreshOCRProcessing() {
        enqueueOCRForUnprocessedImages(prioritizing: selectedClipboardItemID)
    }

    @MainActor
    private func stopOCRProcessing(resetCompleted: Bool) {
        ocrWorkerTask?.cancel()
        ocrWorkerTask = nil
        ocrQueue.reset(resetCompleted: resetCompleted)
    }

    private func handleCancelAction() {
        if hasMeaningfulText(store.clipboardSearchText) {
            clearSearch()
        } else {
            requestClosePanel(restorePreviousApp: true)
        }
    }

    @discardableResult
    private func copyClipboardItemToPasteboard(
        _ itemID: UUID,
        closesPanelOverride: Bool? = nil
    ) -> Bool {
        commitClipboardSelection(itemID, clearsHoverState: false)
        guard let item = store.clipboardHistory.first(where: { $0.id == itemID }) else {
            return false
        }
        if store.clipboardIsFileItem(item) {
            store.refreshClipboardFileAvailability(force: true)
        }
        guard store.clipboardCanCopy(item) else {
            return false
        }
        let shouldClosePanel = closesPanelOverride ?? (onRequestClose != nil && store.closesPanelAfterCopy)
        let feedback = store.copyClipboardItem(
            itemID,
            persistHistoryImmediately: !shouldClosePanel
        )
        guard feedback != nil else {
            return false
        }

        if shouldClosePanel {
            requestClosePanel(restorePreviousApp: store.restoresPreviousAppAfterCopy)
            Task { @MainActor in
                store.scheduleClipboardPersistence()
            }
        } else {
            presentFeedback(feedback)
        }
        return true
    }

    @discardableResult
    private func performPrimaryClipboardAction(
        for itemID: UUID,
        closesPanelOverride: Bool? = nil
    ) -> Bool {
        guard let item = store.clipboardHistory.first(where: { $0.id == itemID }) else {
            return false
        }

        if activePrimaryCopyMode(for: item) == .file {
            return copyClipboardItemAsFileToPasteboard(itemID, closesPanelOverride: closesPanelOverride)
        } else {
            return copyClipboardItemToPasteboard(itemID, closesPanelOverride: closesPanelOverride)
        }
    }

    private func supportsAlternateFileCopy(for item: ClipboardItem) -> Bool {
        store.clipboardHasPreviewImage(for: item) && store.clipboardCanCopyAsFile(item)
    }

    private func activePrimaryCopyMode(for item: ClipboardItem) -> ClipboardImageCopyMode {
        if supportsAlternateFileCopy(for: item), selectedClipboardItemID == item.id {
            return selectedImageCopyMode
        }
        return .image
    }

    @discardableResult
    private func handleSelectedImageCopyModeChange(_ mode: ClipboardImageCopyMode) -> Bool {
        guard let selectedClipboardItem,
              supportsAlternateFileCopy(for: selectedClipboardItem)
        else {
            return false
        }

        selectedImageCopyMode = mode
        return true
    }

    private func clipboardCopyModeBadge(_ mode: ClipboardImageCopyMode) -> some View {
        let systemImage = mode == .image ? "photo.fill" : "doc.fill"
        let label = mode == .image
            ? store.localized("ui.clipboard.item.image")
            : store.localized("ui.clipboard.item.file")

        return Label(label, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )
    }

    private func presentImageCopyModeTipIfNeeded(for item: ClipboardItem) {
        guard supportsAlternateFileCopy(for: item),
              !store.hasSeenImageCopyModeTip
        else {
            return
        }

        store.markImageCopyModeTipAsSeen()
        showsImageCopyModeTip = true
    }

    private func openSettingsWindow() {
        onRequestClose?(false)
        AppDelegate.shared?.showSettingsWindow(nil)
    }

    private func copyTextToPasteboard(_ text: String) {
        let feedback = store.copyTextToClipboard(text)
        if onRequestClose != nil && store.closesPanelAfterCopy {
            requestClosePanel(restorePreviousApp: store.restoresPreviousAppAfterCopy)
        } else {
            presentFeedback(feedback)
        }
    }

    @discardableResult
    private func copyClipboardItemAsFileToPasteboard(
        _ itemID: UUID,
        closesPanelOverride: Bool? = nil
    ) -> Bool {
        commitClipboardSelection(itemID, clearsHoverState: false)
        guard let item = store.clipboardHistory.first(where: { $0.id == itemID }) else {
            return false
        }
        if store.clipboardIsFileItem(item) {
            store.refreshClipboardFileAvailability(force: true)
        }
        guard store.clipboardCanCopyAsFile(item) else {
            return false
        }

        let shouldClosePanel = closesPanelOverride ?? (onRequestClose != nil && store.closesPanelAfterCopy)
        let feedback = store.copyClipboardItemAsFile(
            itemID,
            persistHistoryImmediately: !shouldClosePanel
        )
        guard feedback != nil else {
            return false
        }

        if shouldClosePanel {
            requestClosePanel(restorePreviousApp: store.restoresPreviousAppAfterCopy)
            Task { @MainActor in
                store.scheduleClipboardPersistence()
            }
        } else {
            presentFeedback(feedback)
        }
        return true
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
        !store.clipboardOCRSources(for: item).isEmpty
    }

    private func supportsAirDrop(for item: ClipboardItem) -> Bool {
        if store.clipboardIsFileItem(item) {
            return !store.clipboardAvailableFileURLs(for: item).isEmpty
        }

        return store.clipboardImageData(for: item) != nil
    }

    private func airDropClipboardItem(_ item: ClipboardItem) {
        let didStartAirDrop: Bool

        if store.clipboardIsFileItem(item) {
            store.refreshClipboardFileAvailability(force: true)
            didStartAirDrop = store.withClipboardFileAccess(for: item) { urls in
                airDropService.sendFiles(urls)
            } ?? false
        } else if let image = store.clipboardImage(for: item) {
            didStartAirDrop = airDropService.sendImage(image)
        } else {
            didStartAirDrop = false
        }

        guard didStartAirDrop else {
            return
        }

        if onRequestClose != nil {
            requestClosePanel(restorePreviousApp: false)
        }
    }

    @ViewBuilder
    private func airDropButton(for item: ClipboardItem, compact: Bool = false) -> some View {
        let title = store.localized("ui.clipboard.button.airdrop")

        if compact {
            let canAirDrop = supportsAirDrop(for: item)

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
            let canAirDrop = supportsAirDrop(for: item)

            Button {
                airDropClipboardItem(item)
            } label: {
                Text(title)
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canAirDrop)
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
    let onMoveLeft: () -> Bool
    let onMoveRight: () -> Bool
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
            case #selector(NSResponder.moveLeft(_:)):
                return parent.onMoveLeft()
            case #selector(NSResponder.moveRight(_:)):
                return parent.onMoveRight()
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
