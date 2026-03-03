import AppKit
import SwiftUI

struct MenuBarRootView: View {
    private enum SearchField: Hashable {
        case settings
        case clipboard
        case todo
    }

    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager
    let navigator: SettingsNavigator
    let onPreferredSizeChange: ((CGSize) -> Void)?
    @State private var focusedField: SearchField?
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var isFeedbackAlertPresented: Bool = false
    @State private var selectedSettingsDestinationID: String?
    @State private var selectedClipboardItemID: UUID?
    @State private var selectedTodoItemID: UUID?
    @State private var isTodoInputEditing: Bool = false
    @State private var keyDownMonitor: Any?
    @State private var globalKeyDownMonitor: Any?
    @State private var scrollProxy: ScrollViewProxy?
    @StateObject private var quickControls = QuickControlsState()

    private let mainWidth: CGFloat = 460
    private let previewWidth: CGFloat = 320
    private let panelHeight: CGFloat = 620

    private var preferredPanelSize: CGSize {
        let previewPaneWidth: CGFloat = showPreview ? (previewWidth + 1) : 0
        return CGSize(width: mainWidth + previewPaneWidth, height: panelHeight)
    }

    private var showPreview: Bool {
        switch store.activePanel {
        case .clipboard:
            return selectedClipboardItem != nil
        case .settings:
            return selectedSettingsDestination != nil
        case .todo:
            return selectedTodoItem != nil
        }
    }

    private var selectedClipboardItem: ClipboardItem? {
        guard let selectedClipboardItemID else { return nil }
        return clipboardNavigationItems.first { $0.id == selectedClipboardItemID }
    }

    private var selectedSettingsDestination: SettingsDestination? {
        guard let selectedSettingsDestinationID else { return nil }
        return settingsNavigationItems.first { $0.id == selectedSettingsDestinationID }
    }

    private var selectedTodoItem: TodoItem? {
        guard let selectedTodoItemID else { return nil }
        return todoNavigationItems.first { $0.id == selectedTodoItemID }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Preview pane (left side, slides in)
            if showPreview {
                Group {
                    if store.activePanel == .clipboard, let item = selectedClipboardItem {
                        clipboardPreviewPane(item: item)
                    } else if store.activePanel == .settings, let dest = selectedSettingsDestination {
                        settingsPreviewPane(destination: dest)
                    } else if store.activePanel == .todo, let item = selectedTodoItem {
                        todoPreviewPane(item: item)
                    }
                }
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
        .frame(height: panelHeight)
        .animation(.easeInOut(duration: 0.2), value: showPreview)
        .onAppear {
            onPreferredSizeChange?(preferredPanelSize)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                switch store.activePanel {
                case .settings: focusedField = .settings
                case .clipboard: focusedField = .clipboard
                case .todo: focusedField = .todo
                }
            }

            syncSelectedSettingsDestination()
            syncSelectedClipboardItem()
            syncSelectedTodoItem()
            installKeyMonitorIfNeeded()
        }
        .onChange(of: showPreview) { _ in
            onPreferredSizeChange?(preferredPanelSize)
        }
        .onChange(of: store.activePanel) { newPanel in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                switch newPanel {
                case .settings: focusedField = .settings
                case .clipboard: focusedField = .clipboard
                case .todo: focusedField = .todo
                }
            }

            if newPanel != .todo {
                isTodoInputEditing = false
            }

            switch newPanel {
            case .settings: syncSelectedSettingsDestination()
            case .clipboard: syncSelectedClipboardItem()
            case .todo: syncSelectedTodoItem()
            }
        }
        .onChange(of: settingsNavigationIDs) { _ in
            syncSelectedSettingsDestination()
        }
        .onChange(of: clipboardNavigationIDs) { _ in
            syncSelectedClipboardItem()
        }
        .onChange(of: todoNavigationIDs) { _ in
            syncSelectedTodoItem()
        }
        .onDisappear {
            focusedField = nil
            removeKeyMonitor()
        }
        .onMoveCommand { direction in
            handleMoveCommand(direction)
        }
        .onSubmit {
            switch store.activePanel {
            case .settings: openSelectedSetting()
            case .clipboard: copySelectedClipboardItem()
            case .todo:
                break
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
                Text("Enter → \(store.localized("ui.clipboard.button.copy"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Delete → \(store.localized("ui.clipboard.help.delete"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Inline todo preview

    private func todoPreviewPane(item: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Priority badge
                    if let priority = item.priority {
                        HStack(spacing: 4) {
                            Image(systemName: todoPriorityIcon(priority))
                                .foregroundStyle(todoPriorityColor(priority))
                            Text(store.localized("ui.todo.priority.\(priority.rawValue)"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(todoPriorityColor(priority))
                        }
                    }

                    // Title
                    Text(item.title)
                        .font(.system(size: 14, weight: .semibold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .strikethrough(item.isCompleted)

                    // Notes
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.system(size: 12))
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()

                    // Inline editing
                    VStack(alignment: .leading, spacing: 8) {
                        // Priority picker
                        HStack {
                            Text(store.localized("ui.todo.preview.priority"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Menu {
                                Button(store.localized("ui.todo.preview.noPriority")) {
                                    store.updateTodoItem(item.id, priority: .some(nil))
                                }
                                ForEach(TodoPriority.allCases, id: \.self) { p in
                                    Button {
                                        store.updateTodoItem(item.id, priority: .some(p))
                                    } label: {
                                        Label(
                                            store.localized("ui.todo.priority.\(p.rawValue)"),
                                            systemImage: todoPriorityIcon(p)
                                        )
                                    }
                                }
                            } label: {
                                if let p = item.priority {
                                    Label(
                                        store.localized("ui.todo.priority.\(p.rawValue)"),
                                        systemImage: todoPriorityIcon(p)
                                    )
                                    .font(.caption)
                                    .foregroundStyle(todoPriorityColor(p))
                                } else {
                                    Text(store.localized("ui.todo.preview.noPriority"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        // Due date picker
                        HStack {
                            Text(store.localized("ui.todo.preview.dueDate.label"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if item.dueDate != nil {
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { item.dueDate ?? Date() },
                                        set: { store.updateTodoItem(item.id, dueDate: .some($0)) }
                                    ),
                                    displayedComponents: [.date]
                                )
                                .labelsHidden()
                                .controlSize(.small)

                                Button {
                                    store.updateTodoItem(item.id, dueDate: .some(nil))
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(store.localized("ui.todo.preview.addDueDate")) {
                                    store.updateTodoItem(item.id, dueDate: .some(Date()))
                                }
                                .font(.caption)
                                .controlSize(.small)
                            }
                        }

                        Divider()

                        // Notes editor
                        Text(store.localized("ui.todo.preview.notes"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: Binding(
                            get: { item.notes ?? "" },
                            set: { store.updateTodoItem(item.id, notes: $0.isEmpty ? nil : $0) }
                        ))
                        .font(.system(size: 11))
                        .frame(minHeight: 60)
                        .scrollContentBackground(.hidden)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.quaternary.opacity(0.3))
                        )
                    }
                }
                .padding(12)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                if let dueLabel = store.todoDueDateLabel(for: item) {
                    Text(store.localized("ui.todo.preview.dueDate", dueLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(store.todoCreatedAtLabel(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.localized(item.isCompleted ? "ui.todo.status.completed" : "ui.todo.status.pending"))
                    .font(.caption)
                    .foregroundStyle(item.isCompleted ? .green : .orange)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("Enter → \(store.localized("ui.todo.help.toggleComplete"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Delete → \(store.localized("ui.todo.help.delete"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func todoPriorityIcon(_ priority: TodoPriority) -> String {
        switch priority {
        case .high: return "exclamationmark.triangle.fill"
        case .medium: return "flag.fill"
        case .low: return "arrow.down.circle"
        }
    }

    private func todoPriorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .high: return .red
        case .medium: return .orange
        case .low: return .blue
        }
    }

    // MARK: - Inline settings preview

    private func settingsPreviewPane(destination: SettingsDestination) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 12) {
                Image(systemName: destination.symbolName)
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                Text(store.localizedTitle(for: destination))
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(store.localizedSubtitle(for: destination))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(16)

            if !destination.quickLinks.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text(store.localized("ui.help.quickLinks"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(destination.quickLinks) { quickLink in
                        Button {
                            open(quickLink, in: destination)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle")
                                    .font(.caption)
                                Text(quickLink.localizedTitle(using: localizationManager))
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }
                .padding(12)
            }

            quickControlsSection(for: destination)

            Spacer(minLength: 0)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(destination.category.localizedTitle(using: localizationManager))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                Text("Enter → \(store.localized("ui.button.open"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .task(id: destination.id) {
            quickControls.invalidate()
            quickControls.loadValues(for: destination.id)
        }
    }

    // MARK: - Quick Controls

    private static let quickControlDestinations: Set<String> = [
        "displays", "sound", "mouse", "trackpad", "keyboard", "wifi",
        "bluetooth", "network", "battery", "accessibility", "notifications",
        "date-time", "login-items", "software-update"
    ]

    @ViewBuilder
    private func quickControlsSection(for destination: SettingsDestination) -> some View {
        if Self.quickControlDestinations.contains(destination.id) {
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(store.localized("ui.quickControls.info"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    switch destination.id {
                    case "displays": displaysInfoView
                    case "sound": soundInfoView
                    case "mouse": mouseInfoView
                    case "trackpad": trackpadInfoView
                    case "keyboard": keyboardInfoView
                    case "wifi": wifiInfoView
                    case "bluetooth": bluetoothInfoView
                    case "network": networkInfoView
                    case "battery": batteryInfoView
                    case "accessibility": accessibilityInfoView
                    case "notifications": notificationsInfoView
                    case "date-time": dateTimeInfoView
                    case "login-items": loginItemsInfoView
                    case "software-update": softwareUpdateInfoView
                    default: EmptyView()
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: Displays — info only

    private var displaysInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "sun.max",
                label: store.localized("ui.quickControls.darkMode"),
                value: quickControls.isDarkMode ? "On" : "Off"
            )
            infoRow(
                icon: "paintpalette",
                label: store.localized("ui.quickControls.accentColor"),
                value: accentColorName
            )
            if let name = quickControls.displayName {
                infoRow(icon: "display", label: store.localized("ui.info.displayName"), value: name)
            }
            if let res = quickControls.displayResolution {
                infoRow(icon: "rectangle.dashed", label: store.localized("ui.info.resolution"), value: res)
            }
            if let gpu = quickControls.gpuName {
                infoRow(icon: "cpu", label: "GPU", value: gpu)
            }
            if let cores = quickControls.gpuCores {
                infoRow(icon: "square.grid.3x3", label: store.localized("ui.info.gpuCores"), value: cores)
            }
            if let metal = quickControls.metalVersion {
                infoRow(icon: "diamond", label: "Metal", value: metal)
            }
            infoRow(
                icon: "sun.min",
                label: store.localized("ui.info.autoBrightness"),
                value: quickControls.autoBrightness ? "On" : "Off"
            )
        }
    }

    private var accentColorName: String {
        let map: [Int: String] = [
            0: "Red", 1: "Orange", 2: "Yellow", 3: "Green",
            4: "Blue", 5: "Purple", 6: "Pink", -1: "Graphite",
        ]
        guard let value = quickControls.accentColorValue else { return "Multicolor" }
        return map[value] ?? "Blue"
    }

    // MARK: Sound — info only

    private var soundInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: quickControls.isOutputMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                label: store.localized("ui.quickControls.outputVolume"),
                value: quickControls.outputVolume.map { "\($0)%" } ?? "–"
            )
            infoRow(
                icon: "speaker.slash",
                label: store.localized("ui.quickControls.mute"),
                value: quickControls.isOutputMuted ? "On" : "Off"
            )
            if let device = quickControls.defaultOutputDevice {
                infoRow(icon: "hifispeaker", label: store.localized("ui.info.outputDevice"), value: device)
            }

            Divider()

            infoRow(
                icon: "mic.fill",
                label: store.localized("ui.quickControls.inputVolume"),
                value: quickControls.inputVolume.map { "\($0)%" } ?? "–"
            )
            if let device = quickControls.defaultInputDevice {
                infoRow(icon: "mic", label: store.localized("ui.info.inputDevice"), value: device)
            }

            Divider()

            infoRow(
                icon: "bell.fill",
                label: store.localized("ui.quickControls.alertVolume"),
                value: quickControls.alertVolume.map { "\($0)%" } ?? "–"
            )
        }
    }

    // MARK: Mouse — info only

    private var mouseInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "computermouse",
                label: store.localized("ui.quickControls.trackingSpeed"),
                value: String(format: "%.1f", quickControls.mouseTrackingSpeed)
            )
            infoRow(
                icon: "scroll",
                label: store.localized("ui.quickControls.scrollSpeed"),
                value: String(format: "%.1f", quickControls.mouseScrollSpeed)
            )
            infoRow(
                icon: "arrow.up.arrow.down",
                label: store.localized("ui.quickControls.naturalScroll"),
                value: quickControls.isNaturalScrollEnabled ? "On" : "Off"
            )
        }
    }

    // MARK: Trackpad — info only

    private var trackpadInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "hand.point.up",
                label: store.localized("ui.quickControls.trackingSpeed"),
                value: String(format: "%.1f", quickControls.trackpadTrackingSpeed)
            )
            infoRow(
                icon: "hand.tap",
                label: store.localized("ui.quickControls.tapToClick"),
                value: quickControls.isTapToClickEnabled ? "On" : "Off"
            )
            infoRow(
                icon: "hand.draw",
                label: store.localized("ui.quickControls.threeFingerDrag"),
                value: quickControls.isThreeFingerDragEnabled ? "On" : "Off"
            )
        }
    }

    // MARK: Keyboard — info only

    private var keyboardInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "repeat",
                label: store.localized("ui.quickControls.keyRepeat"),
                value: String(format: "%.0f ms", quickControls.keyRepeatInterval * 1000)
            )
            infoRow(
                icon: "timer",
                label: store.localized("ui.quickControls.delayUntilRepeat"),
                value: String(format: "%.1f s", quickControls.keyRepeatDelay)
            )
        }
    }

    // MARK: Wi-Fi — info only

    private var wifiInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "wifi",
                label: store.localized("ui.quickControls.wifi"),
                value: quickControls.isWiFiEnabled ? "On" : "Off"
            )
            if let ssid = quickControls.currentSSID {
                infoRow(icon: "wifi.circle", label: "SSID", value: ssid)
            }
            if let mac = quickControls.wifiMACAddress {
                infoRow(icon: "number", label: "MAC", value: mac)
            }
        }
    }

    // MARK: Bluetooth — info only

    private var bluetoothInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "antenna.radiowaves.left.and.right",
                label: store.localized("ui.quickControls.bluetooth.power"),
                value: quickControls.isBluetoothOn ? "On" : "Off"
            )
            if let version = quickControls.bluetoothVersion {
                infoRow(icon: "info.circle", label: "BLE", value: version)
            }

            if !quickControls.connectedBluetoothDevices.isEmpty {
                Divider()
                Text(store.localized("ui.quickControls.bluetooth.connected"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(quickControls.connectedBluetoothDevices, id: \.self) { device in
                    infoRow(icon: "wave.3.right", label: device)
                }
            }

            if !quickControls.pairedBluetoothDevices.isEmpty {
                Divider()
                Text(store.localized("ui.info.bluetooth.paired"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(quickControls.pairedBluetoothDevices, id: \.self) { device in
                    infoRow(icon: "link", label: device)
                }
            }

            if quickControls.connectedBluetoothDevices.isEmpty && quickControls.pairedBluetoothDevices.isEmpty {
                Text(store.localized("ui.quickControls.bluetooth.noDevices"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Network — info only

    private var networkInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "network",
                label: store.localized("ui.quickControls.network.localIP"),
                value: quickControls.localIP ?? store.localized("ui.quickControls.network.noIP")
            )
            if let router = quickControls.routerIP {
                infoRow(icon: "wifi.router", label: store.localized("ui.info.network.router"), value: router)
            }
            if let mask = quickControls.subnetMask {
                infoRow(icon: "square.grid.2x2", label: store.localized("ui.info.network.subnet"), value: mask)
            }

            if !quickControls.dnsServers.isEmpty {
                Divider()
                Text(store.localized("ui.quickControls.network.dns"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(quickControls.dnsServers, id: \.self) { dns in
                    Text(dns)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: Battery — info only

    private var batteryInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let pct = quickControls.batteryPercentage {
                HStack(spacing: 8) {
                    Image(systemName: batteryIcon)
                        .font(.title3)
                        .foregroundStyle(pct <= 20 ? .red : .green)
                    Text("\(pct)%")
                        .font(.title3.monospacedDigit().weight(.semibold))
                }

                if quickControls.isBatteryCharging {
                    infoRow(icon: "bolt.fill", label: store.localized("ui.quickControls.battery.charging"))
                } else if quickControls.isBatteryPluggedIn {
                    infoRow(icon: "powerplug.fill", label: store.localized("ui.quickControls.battery.pluggedIn"))
                } else {
                    infoRow(icon: "battery.100", label: store.localized("ui.quickControls.battery.onBattery"))
                }
            }

            if let time = quickControls.batteryTimeRemaining {
                infoRow(icon: "clock", label: store.localized("ui.info.battery.timeRemaining"), value: time)
            }

            Divider()

            if let capacity = quickControls.batteryMaxCapacity {
                infoRow(
                    icon: "gauge.with.dots.needle.bottom.50percent",
                    label: store.localized("ui.info.battery.maxCapacity"),
                    value: capacity
                )
            }

            if let cycles = quickControls.batteryCycleCount {
                infoRow(
                    icon: "arrow.triangle.2.circlepath",
                    label: store.localized("ui.quickControls.battery.cycleCount"),
                    value: "\(cycles)"
                )
            }

            if let condition = quickControls.batteryCondition {
                infoRow(
                    icon: "heart.fill",
                    label: store.localized("ui.quickControls.battery.condition"),
                    value: condition
                )
            }
        }
    }

    private var batteryIcon: String {
        guard let pct = quickControls.batteryPercentage else { return "battery.0" }
        if quickControls.isBatteryCharging { return "battery.100.bolt" }
        switch pct {
        case 76...100: return "battery.100"
        case 51...75: return "battery.75"
        case 26...50: return "battery.50"
        case 1...25: return "battery.25"
        default: return "battery.0"
        }
    }

    // MARK: Accessibility — info only

    private var accessibilityInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "figure.walk",
                label: store.localized("ui.quickControls.accessibility.reduceMotion"),
                value: quickControls.isReduceMotionEnabled ? "On" : "Off"
            )
            infoRow(
                icon: "square.on.square",
                label: store.localized("ui.quickControls.accessibility.reduceTransparency"),
                value: quickControls.isReduceTransparencyEnabled ? "On" : "Off"
            )
            infoRow(
                icon: "circle.lefthalf.filled",
                label: store.localized("ui.quickControls.accessibility.increaseContrast"),
                value: quickControls.isIncreaseContrastEnabled ? "On" : "Off"
            )
        }
    }

    // MARK: Notifications — info only

    private var notificationsInfoView: some View {
        infoRow(
            icon: "moon.fill",
            label: store.localized("ui.quickControls.notifications.dnd"),
            value: quickControls.isFocusEnabled ? "On" : "Off"
        )
    }

    // MARK: Date & Time — info only

    private var dateTimeInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            infoRow(
                icon: "clock",
                label: store.localized("ui.quickControls.dateTime.24hour"),
                value: quickControls.is24HourClock ? "On" : "Off"
            )
            infoRow(
                icon: "globe",
                label: store.localized("ui.quickControls.dateTime.timezone"),
                value: quickControls.currentTimezone
            )
        }
    }

    // MARK: Login Items — info only

    private var loginItemsInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if quickControls.loginItems.isEmpty {
                Text(store.localized("ui.quickControls.loginItems.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(quickControls.loginItems, id: \.self) { item in
                    infoRow(icon: "app.badge", label: item)
                }
            }
        }
    }

    // MARK: Software Update — info only

    private var softwareUpdateInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let count = quickControls.pendingUpdates, count > 0 {
                infoRow(
                    icon: "arrow.down.circle.fill",
                    label: store.localized("ui.quickControls.softwareUpdate.pending"),
                    value: "\(count)"
                )
            } else {
                infoRow(
                    icon: "checkmark.circle.fill",
                    label: store.localized("ui.quickControls.softwareUpdate.upToDate")
                )
            }

            if let date = quickControls.lastUpdateCheck {
                infoRow(
                    icon: "clock",
                    label: store.localized("ui.quickControls.softwareUpdate.lastCheck"),
                    value: date
                )
            }
        }
    }

    // MARK: Shared Helpers

    private func infoRow(icon: String, label: String, value: String? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.caption)
                .foregroundStyle(.primary)
            if let value {
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
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
                switchPanel(delta: 1)
            } label: {
                Image(systemName: "switch.2")
                    .font(.title2)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help(localizedPanelTitle(nextPanel(after: store.activePanel)))
        }
    }

    private func nextPanel(after panel: AppPanel) -> AppPanel {
        let panels = AppPanel.allCases
        guard let index = panels.firstIndex(of: panel), !panels.isEmpty else {
            return panel
        }

        return panels[(index + 1) % panels.count]
    }

    private func localizedPanelTitle(_ panel: AppPanel) -> String {
        switch panel {
        case .settings:
            return store.localized("ui.panel.settings")
        case .clipboard:
            return store.localized("ui.panel.clipboard")
        case .todo:
            return store.localized("ui.panel.todo")
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
            panelButton(
                title: store.localized("ui.panel.todo"),
                panel: .todo
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
                isFocused: true,
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
                isFocused: true,
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
        case .todo:
            CommandAwareSearchField(
                text: $store.todoSearchText,
                placeholder: store.localized("ui.todo.search.placeholder"),
                isFocused: focusedField == .todo,
                onFocus: { focusedField = .todo },
                onMoveUp: {
                    moveTodoSelection(delta: -1)
                },
                onMoveDown: {
                    moveTodoSelection(delta: 1)
                },
                onSubmit: {
                    toggleSelectedTodoCompleted()
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
        case .todo:
            todoPanelBody
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

    // MARK: - Todo Panel

    private var todoNavigationItems: [TodoItem] {
        store.pinnedTodoItems + store.recentTodoItems
    }

    private var todoNavigationIDs: [UUID] {
        todoNavigationItems.map(\.id)
    }

    @ViewBuilder
    private var todoPanelBody: some View {
        let pinned = store.pinnedTodoItems
        let recent = store.recentTodoItems

        VStack(alignment: .leading, spacing: 14) {
            todoInputField

            if pinned.isEmpty, recent.isEmpty {
                todoEmptyState
            } else {
                if !pinned.isEmpty {
                    todoSection(
                        title: store.localized("ui.todo.section.pinned"),
                        items: pinned
                    )
                }

                if !recent.isEmpty {
                    todoSection(
                        title: store.localized("ui.todo.section.recent"),
                        items: recent
                    )
                }
            }
        }
    }

    private var todoInputField: some View {
        HStack(spacing: 8) {
            TextField(
                store.localized("ui.todo.input.placeholder"),
                text: $store.todoInputText,
                onEditingChanged: { isEditing in
                    isTodoInputEditing = isEditing
                    if isEditing {
                        focusedField = nil
                    }
                },
                onCommit: {
                    submitTodoInput()
                }
            )
            .textFieldStyle(.roundedBorder)

            Button {
                submitTodoInput()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(store.todoInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .submitScope()
    }

    private func submitTodoInput() {
        let feedback = store.addTodoItem(title: store.todoInputText)
        guard feedback != nil else {
            return
        }

        store.todoInputText = ""
        isTodoInputEditing = false
        NSApp.keyWindow?.makeFirstResponder(nil)
        focusedField = .todo
        syncSelectedTodoItem()
    }

    private var todoEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(store.localized("ui.todo.empty.title"))
                .font(.subheadline.weight(.semibold))
            Text(store.localized("ui.todo.empty.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    private func todoSection(title: String, items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(items) { item in
                todoRow(item, isSelected: selectedTodoItemID == item.id)
                    .id(item.id)
            }
        }
    }

    private func todoRow(_ item: TodoItem, isSelected: Bool) -> some View {
        let isPinned = store.isTodoItemPinned(item.id)

        return HStack(spacing: 10) {
            Button {
                store.toggleTodoItemCompleted(item.id)
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .frame(width: 22)
                    .font(.body.weight(.medium))
                    .foregroundStyle(item.isCompleted ? .green : .primary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.previewTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if let priority = item.priority {
                    Text(store.localized("ui.todo.priority.\(priority.rawValue)"))
                        .font(.caption2)
                        .foregroundStyle(todoPriorityColor(priority))
                }
            }

            Spacer(minLength: 8)

            if let dueLabel = store.todoDueDateLabel(for: item) {
                Text(dueLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button {
                store.toggleTodoItemPinned(item.id)
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(isPinned ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            .help(
                isPinned
                    ? store.localized("ui.todo.help.unpin")
                    : store.localized("ui.todo.help.pin")
            )

            Button {
                store.toggleTodoItemCompleted(item.id)
            } label: {
                Image(systemName: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
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
            selectedTodoItemID = item.id
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

    private var activePanelTextIsEmpty: Bool {
        switch store.activePanel {
        case .settings:
            return !hasMeaningfulText(store.searchText)
        case .clipboard:
            return !hasMeaningfulText(store.clipboardSearchText)
        case .todo:
            return !hasMeaningfulText(store.todoSearchText) && !hasMeaningfulText(store.todoInputText)
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

    private func handleDeleteShortcutInActivePanel() -> Bool {
        switch store.activePanel {
        case .clipboard:
            guard !hasMeaningfulText(store.clipboardSearchText) else {
                return false
            }
            deleteSelectedClipboardItem()
            return true
        case .todo:
            guard !isTodoInputEditing,
                  !hasMeaningfulText(store.todoSearchText),
                  !hasMeaningfulText(store.todoInputText) else {
                return false
            }
            deleteSelectedTodoItem()
            return true
        case .settings:
            return false
        }
    }

    private var isActivePanelSearchFieldFocused: Bool {
        switch store.activePanel {
        case .settings:
            return focusedField == .settings
        case .clipboard:
            return focusedField == .clipboard
        case .todo:
            return focusedField == .todo && !isTodoInputEditing
        }
    }

    private var isActivePanelSearchTextEmpty: Bool {
        switch store.activePanel {
        case .settings:
            return !hasMeaningfulText(store.searchText)
        case .clipboard:
            return !hasMeaningfulText(store.clipboardSearchText)
        case .todo:
            return !hasMeaningfulText(store.todoSearchText)
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let isLeftArrow = event.keyCode == 123
        let isRightArrow = event.keyCode == 124
        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117

        if flags.isEmpty, (isLeftArrow || isRightArrow),
           isActivePanelSearchFieldFocused, isActivePanelSearchTextEmpty {
            switchPanel(delta: isLeftArrow ? -1 : 1)
            return true
        }

        if flags.isEmpty, isDeleteKey, handleDeleteShortcutInActivePanel() {
            return true
        }

        if isAnyTextInputEditing() {
            return false
        }

        let isEditingTextInput = isEditingTextInput(for: event)

        if !isEditingTextInput, store.activePanel == .clipboard, flags == [.command],
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

        if isEditingTextInput {
            return false
        }

        switch event.keyCode {
        case 123: // left
            if activePanelTextIsEmpty {
                switchPanel(delta: -1)
                return true
            }
            return false // let text field handle cursor movement
        case 124: // right
            if activePanelTextIsEmpty {
                switchPanel(delta: 1)
                return true
            }
            return false // let text field handle cursor movement
        case 125: // down
            switch store.activePanel {
            case .settings: moveSettingsSelection(delta: 1)
            case .clipboard: moveClipboardSelection(delta: 1)
            case .todo: moveTodoSelection(delta: 1)
            }
            return true
        case 126: // up
            switch store.activePanel {
            case .settings: moveSettingsSelection(delta: -1)
            case .clipboard: moveClipboardSelection(delta: -1)
            case .todo: moveTodoSelection(delta: -1)
            }
            return true
        case 36, 76: // return / keypad enter
            switch store.activePanel {
            case .settings: openSelectedSetting()
            case .clipboard: copySelectedClipboardItem()
            case .todo: toggleSelectedTodoCompleted()
            }
            return true
        case 51, 117: // backspace / forward delete
            return handleDeleteShortcutInActivePanel()
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
            switch store.activePanel {
            case .settings: moveSettingsSelection(delta: -1)
            case .clipboard: moveClipboardSelection(delta: -1)
            case .todo: moveTodoSelection(delta: -1)
            }
        case .down:
            switch store.activePanel {
            case .settings: moveSettingsSelection(delta: 1)
            case .clipboard: moveClipboardSelection(delta: 1)
            case .todo: moveTodoSelection(delta: 1)
            }
        @unknown default:
            break
        }
    }

    private func switchPanel(delta: Int) {
        let panels = AppPanel.allCases
        guard let currentIndex = panels.firstIndex(of: store.activePanel),
              !panels.isEmpty else {
            return
        }

        let normalizedDelta = delta % panels.count
        let nextIndex = (currentIndex + normalizedDelta + panels.count) % panels.count
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

    private func deleteSelectedClipboardItem() {
        let items = clipboardNavigationItems
        guard !items.isEmpty,
              let selectedID = selectedClipboardItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedID })
        else {
            return
        }

        store.deleteClipboardItem(selectedID)

        // Select the next item, or the previous if we deleted the last one
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

    // MARK: - Todo Navigation

    private func moveTodoSelection(delta: Int) {
        let items = todoNavigationItems
        guard !items.isEmpty else {
            selectedTodoItemID = nil
            return
        }

        let currentIndex = selectedTodoItemID
            .flatMap { id in items.firstIndex(where: { $0.id == id }) } ?? 0
        let nextIndex = max(0, min(items.count - 1, currentIndex + delta))
        let newID = items[nextIndex].id
        selectedTodoItemID = newID
        withAnimation {
            scrollProxy?.scrollTo(newID, anchor: .center)
        }
    }

    private func toggleSelectedTodoCompleted() {
        let items = todoNavigationItems
        guard !items.isEmpty else { return }

        let selected = selectedTodoItemID
            .flatMap { id in items.first(where: { $0.id == id }) } ?? items[0]
        selectedTodoItemID = selected.id
        store.toggleTodoItemCompleted(selected.id)
    }

    private func deleteSelectedTodoItem() {
        let items = todoNavigationItems
        guard !items.isEmpty,
              let selectedID = selectedTodoItemID,
              let currentIndex = items.firstIndex(where: { $0.id == selectedID })
        else { return }

        store.deleteTodoItem(selectedID)

        let updatedItems = todoNavigationItems
        if updatedItems.isEmpty {
            selectedTodoItemID = nil
        } else {
            let nextIndex = min(currentIndex, updatedItems.count - 1)
            selectedTodoItemID = updatedItems[nextIndex].id
        }
    }

    private func syncSelectedTodoItem() {
        let items = todoNavigationItems
        guard !items.isEmpty else {
            selectedTodoItemID = nil
            return
        }

        if let selectedTodoItemID,
           items.contains(where: { $0.id == selectedTodoItemID }) {
            return
        }

        selectedTodoItemID = items[0].id
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
