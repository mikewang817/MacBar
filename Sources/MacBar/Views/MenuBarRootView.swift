import AppKit
import SwiftUI

struct MenuBarRootView: View {
    private enum SearchField: Hashable {
        case settings
        case clipboard
    }

    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager
    let navigator: SettingsNavigator
    @FocusState private var focusedField: SearchField?
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isFeedbackAlertPresented: Bool = false
    @State private var selectedSettingsDestinationID: String?
    @State private var selectedClipboardItemID: UUID?
    @State private var keyDownMonitor: Any?
    @State private var globalKeyDownMonitor: Any?
    @State private var scrollProxy: ScrollViewProxy?

    private let mainWidth: CGFloat = 460
    private let previewWidth: CGFloat = 320

    private var showPreview: Bool {
        store.activePanel == .clipboard && selectedClipboardItem != nil
    }

    private var selectedClipboardItem: ClipboardItem? {
        guard let selectedClipboardItemID else { return nil }
        return clipboardNavigationItems.first { $0.id == selectedClipboardItemID }
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
                panelSwitcher
                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        activePanelBody
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
        .frame(height: 620)
        .animation(.easeInOut(duration: 0.2), value: showPreview)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                focusedField = store.activePanel == .settings ? .settings : .clipboard
            }

            syncSelectedSettingsDestination()
            syncSelectedClipboardItem()
            installKeyMonitorIfNeeded()
        }
        .onChange(of: store.activePanel) { newPanel in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                focusedField = newPanel == .settings ? .settings : .clipboard
            }

            if newPanel == .settings {
                syncSelectedSettingsDestination()
            } else {
                syncSelectedClipboardItem()
            }
        }
        .onChange(of: settingsNavigationIDs) { _ in
            syncSelectedSettingsDestination()
        }
        .onChange(of: clipboardNavigationIDs) { _ in
            syncSelectedClipboardItem()
        }
        .onDisappear {
            focusedField = nil
            removeKeyMonitor()
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onSubmit {
            if store.activePanel == .settings {
                openSelectedSetting()
            } else {
                copySelectedClipboardItem()
            }
        }
        .alert(alertTitle, isPresented: $isFeedbackAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Inline clipboard preview

    private func clipboardPreviewPane(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let imageData = item.imageTIFFData, let image = NSImage(data: imageData) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                if item.characterCount > 0 {
                    Text(store.localized("ui.clipboard.item.characters", item.characterCount))
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
                Text("Enter → \(store.localized("ui.clipboard.button.copy"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let isPinned = store.isClipboardItemPinned(item.id)
                Text(isPinned
                     ? store.localized("ui.clipboard.help.unpin")
                     : store.localized("ui.clipboard.help.pin"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }


    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("MacBar")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            searchBar
                .frame(minWidth: 180, maxWidth: .infinity)

            Button {
                store.activePanel = store.activePanel == .settings ? .clipboard : .settings
            } label: {
                Image(systemName: "switch.2")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help(
                store.activePanel == .settings
                    ? store.localized("ui.panel.clipboard")
                    : store.localized("ui.panel.settings")
            )
        }
    }

    private var panelSwitcher: some View {
        HStack(spacing: 8) {
            panelButton(
                title: store.localized("ui.panel.settings"),
                panel: .settings
            )
            panelButton(
                title: store.localized("ui.panel.clipboard"),
                panel: .clipboard
            )

            Spacer()
        }
    }

    private func panelButton(title: String, panel: AppPanel) -> some View {
        let isSelected = store.activePanel == panel

        return Button {
            store.activePanel = panel
        } label: {
            Text(title)
                .font(.headline)
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.16))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var searchBar: some View {
        switch store.activePanel {
        case .settings:
            CommandAwareSearchField(
                text: $store.searchText,
                placeholder: store.localized("ui.search.placeholder"),
                isFocused: focusedField == .settings,
                onFocus: { focusedField = .settings },
                onMoveUp: {
                    moveSettingsSelection(delta: -1)
                },
                onMoveDown: {
                    moveSettingsSelection(delta: 1)
                },
                onSubmit: {
                    openSelectedSetting()
                }
            )
        case .clipboard:
            CommandAwareSearchField(
                text: $store.clipboardSearchText,
                placeholder: store.localized("ui.clipboard.search.placeholder"),
                isFocused: focusedField == .clipboard,
                onFocus: { focusedField = .clipboard },
                onMoveUp: {
                    moveClipboardSelection(delta: -1)
                },
                onMoveDown: {
                    moveClipboardSelection(delta: 1)
                },
                onSubmit: {
                    copySelectedClipboardItem()
                }
            )
        }
    }

    @ViewBuilder
    private var activePanelBody: some View {
        switch store.activePanel {
        case .settings:
            settingsPanelBody
        case .clipboard:
            clipboardPanelBody
        }
    }

    private var showFavoritesSection: Bool {
        !store.isSearching && !store.favoriteDestinations.isEmpty
    }

    private var settingsNavigationItems: [SettingsDestination] {
        var ordered: [SettingsDestination] = []

        if showFavoritesSection {
            ordered.append(contentsOf: store.favoriteDestinations)
        }

        for section in filteredGroupedSearchResults {
            ordered.append(contentsOf: section.items)
        }

        return ordered
    }

    private var filteredGroupedSearchResults: [MacBarStore.CategorySection] {
        let sections = store.groupedSearchResults
        guard showFavoritesSection else {
            return sections
        }

        let favIDs = store.favoriteIDs
        return sections.compactMap { section in
            let filtered = section.items.filter { !favIDs.contains($0.id) }
            guard !filtered.isEmpty else {
                return nil
            }
            return MacBarStore.CategorySection(category: section.category, items: filtered)
        }
    }

    private var settingsNavigationIDs: [String] {
        settingsNavigationItems.map(\.id)
    }

    private var clipboardNavigationItems: [ClipboardItem] {
        store.pinnedClipboardItems + store.recentClipboardItems
    }

    private var clipboardNavigationIDs: [UUID] {
        clipboardNavigationItems.map(\.id)
    }

    private var settingsPanelBody: some View {
        let grouped = filteredGroupedSearchResults

        return VStack(alignment: .leading, spacing: 14) {
            if showFavoritesSection {
                destinationSection(
                    title: store.localized("ui.section.favorites"),
                    items: store.favoriteDestinations
                )
            }

            if grouped.isEmpty, !showFavoritesSection {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(store.localized("ui.empty.title"))
                        .font(.subheadline.weight(.semibold))
                    Text(store.localized("ui.empty.hint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ForEach(grouped) { section in
                    destinationSection(
                        title: store.localizedTitle(for: section.category),
                        items: section.items
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var clipboardPanelBody: some View {
        let pinned = store.pinnedClipboardItems
        let recent = store.recentClipboardItems

        VStack(alignment: .leading, spacing: 14) {
            if pinned.isEmpty, recent.isEmpty {
                clipboardEmptyState
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
        let title = item.previewTitle.isEmpty
            ? store.localized("ui.clipboard.item.empty")
            : (item.isImage ? store.localized("ui.clipboard.item.image") : item.previewTitle)

        return HStack(spacing: 10) {
            Group {
                if let imageData = item.imageTIFFData, let image = NSImage(data: imageData) {
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
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
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
                selectedClipboardItemID = item.id
                _ = store.copyClipboardItem(item.id)
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
    }

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

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])

        if store.activePanel == .clipboard, flags == [.command],
           let chars = event.charactersIgnoringModifiers?.lowercased(),
           let first = chars.first {
            // CMD+1-9 for recent (unpinned) items
            if let digit = Int(String(first)), (1...9).contains(digit) {
                copyRecentClipboardItemByIndex(digit - 1)
                return true
            }
            // CMD+A-Z for pinned items
            if let letterIndex = Self.pinnedShortcutLetters.firstIndex(
                of: Character(first.uppercased())
            ) {
                copyPinnedClipboardItemByIndex(letterIndex)
                return true
            }
        }

        guard flags.isEmpty else {
            return false
        }

        switch event.keyCode {
        case 123: // left
            switchPanel(delta: -1)
            return true
        case 124: // right
            switchPanel(delta: 1)
            return true
        case 125: // down
            if store.activePanel == .settings {
                moveSettingsSelection(delta: 1)
            } else {
                moveClipboardSelection(delta: 1)
            }
            return true
        case 126: // up
            if store.activePanel == .settings {
                moveSettingsSelection(delta: -1)
            } else {
                moveClipboardSelection(delta: -1)
            }
            return true
        case 36, 76: // return / keypad enter
            if store.activePanel == .settings {
                openSelectedSetting()
            } else {
                copySelectedClipboardItem()
            }
            return true
        default:
            return false
        }
    }

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        switch direction {
        case .left:
            switchPanel(delta: -1)
        case .right:
            switchPanel(delta: 1)
        case .up:
            if store.activePanel == .settings {
                moveSettingsSelection(delta: -1)
            } else {
                moveClipboardSelection(delta: -1)
            }
        case .down:
            if store.activePanel == .settings {
                moveSettingsSelection(delta: 1)
            } else {
                moveClipboardSelection(delta: 1)
            }
        @unknown default:
            break
        }
    }

    private func switchPanel(delta: Int) {
        let panels = AppPanel.allCases
        guard let currentIndex = panels.firstIndex(of: store.activePanel) else {
            return
        }
        let nextIndex = currentIndex + delta
        guard nextIndex >= 0, nextIndex < panels.count else {
            return
        }
        store.activePanel = panels[nextIndex]
    }


    private func moveSettingsSelection(delta: Int) {
        let items = settingsNavigationItems
        guard !items.isEmpty else {
            selectedSettingsDestinationID = nil
            return
        }

        let currentIndex = selectedSettingsDestinationID
            .flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        let newID = items[nextIndex].id
        selectedSettingsDestinationID = newID
        withAnimation {
            scrollProxy?.scrollTo(newID, anchor: .center)
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

    private func openSelectedSetting() {
        let items = settingsNavigationItems
        guard !items.isEmpty else {
            return
        }

        let selected = selectedSettingsDestinationID
            .flatMap { id in items.first(where: { $0.id == id }) } ?? items[0]
        selectedSettingsDestinationID = selected.id
        open(selected)
    }

    private func copySelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty else {
            return
        }

        let selected = selectedClipboardItemID
            .flatMap { id in items.first(where: { $0.id == id }) } ?? items[0]
        selectedClipboardItemID = selected.id
        _ = store.copyClipboardItem(selected.id)
    }

    private func copyPinnedClipboardItemByIndex(_ index: Int) {
        let items = store.pinnedClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        let item = items[index]
        selectedClipboardItemID = item.id
        _ = store.copyClipboardItem(item.id)
    }

    private func copyRecentClipboardItemByIndex(_ index: Int) {
        let items = store.recentClipboardItems
        guard index >= 0, index < items.count else {
            return
        }

        let item = items[index]
        selectedClipboardItemID = item.id
        _ = store.copyClipboardItem(item.id)
    }

    private func syncSelectedSettingsDestination() {
        let items = settingsNavigationItems
        guard !items.isEmpty else {
            selectedSettingsDestinationID = nil
            return
        }

        if let selectedSettingsDestinationID,
           items.contains(where: { $0.id == selectedSettingsDestinationID }) {
            return
        }

        selectedSettingsDestinationID = items[0].id
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


    private var footer: some View {
        HStack {
            Button(store.localized("ui.button.systemSettingsHome")) {
                _ = navigator.openSystemSettingsHome()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            languageMenu

            Spacer()

            Button(store.localized("ui.button.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
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


    private func destinationSection(title: String, items: [SettingsDestination]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items) { destination in
                destinationRow(destination, isSelected: selectedSettingsDestinationID == destination.id)
                    .id(destination.id)
            }
        }
    }

    private func destinationRow(_ destination: SettingsDestination, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbolName)
                .frame(width: 22)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.localizedTitle(for: destination))
                    .font(.subheadline.weight(.semibold))
                Text(store.localizedSubtitle(for: destination))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !destination.quickLinks.isEmpty {
                quickLinksMenu(for: destination)
            }

            Button {
                store.toggleFavorite(destination.id)
            } label: {
                Image(systemName: store.isFavorite(destination.id) ? "star.fill" : "star")
                    .foregroundStyle(store.isFavorite(destination.id) ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
            .help(
                store.isFavorite(destination.id)
                ? store.localized("ui.help.favorite.remove")
                : store.localized("ui.help.favorite.add")
            )

            Button(store.localized("ui.button.open")) {
                selectedSettingsDestinationID = destination.id
                open(destination)
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
            selectedSettingsDestinationID = destination.id
        }
    }

    private func open(_ destination: SettingsDestination) {
        let result = navigator.open(destination)
        presentOpenResultIfNeeded(result)
    }

    private func open(_ quickLink: SettingsQuickLink, in destination: SettingsDestination) {
        let result = navigator.open(quickLink: quickLink, in: destination)
        presentOpenResultIfNeeded(result)
    }

    private func quickLinksMenu(for destination: SettingsDestination) -> some View {
        Menu {
            ForEach(destination.quickLinks) { quickLink in
                Button(quickLink.localizedTitle(using: localizationManager)) {
                    open(quickLink, in: destination)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.body)
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help(store.localized("ui.help.quickLinks"))
    }

    private func presentFeedback(_ feedback: StoreFeedback?) {
        guard let feedback else {
            return
        }

        alertTitle = feedback.title
        alertMessage = feedback.message
        isFeedbackAlertPresented = true
    }

    private func presentOpenResultIfNeeded(_ result: SettingsOpenResult) {
        guard result.status != .success else {
            return
        }

        presentFeedback(
            StoreFeedback(
                title: store.localized("feedback.opening.title"),
                message: result.message
            )
        )
    }

    private func languageLabel(for option: LanguageOption) -> String {
        if option.code == LocalizationManager.systemLanguageCode {
            let systemName = localizationManager.systemLanguageName
            return localizationManager.localized("ui.language.followSystem", systemName)
        }

        return option.label
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

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard let window = nsView.window else {
            return
        }

        if isFocused {
            if window.firstResponder !== nsView.currentEditor() {
                window.makeFirstResponder(nsView)
            }
        } else if window.firstResponder === nsView.currentEditor() {
            window.makeFirstResponder(nil)
        }
    }
}


