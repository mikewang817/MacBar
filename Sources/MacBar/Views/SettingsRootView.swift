import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                languageSection
                behaviorSection
                captureSection
                ocrSection

                if BuildInfo.supportsExternalUpdates {
                    updateSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.refreshLaunchAtLoginStatus()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(store.localized("ui.settings.title"))
                .font(.title2.weight(.semibold))

            Text(store.localized("ui.settings.subtitle"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        settingsSection(title: store.localized("ui.language.menu")) {
            Picker(store.localized("ui.language.menu"), selection: selectedLanguageCodeBinding) {
                ForEach(localizationManager.languageOptions) { option in
                    Text(languageLabel(for: option)).tag(option.code)
                }
            }
            .pickerStyle(.menu)

            Text(store.localized("ui.settings.language.footer"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var behaviorSection: some View {
        settingsSection(
            title: store.localized("ui.settings.section.behavior"),
            footer: store.localized("ui.settings.section.behavior.footer")
        ) {
            Toggle(
                store.localized("ui.settings.option.closeAfterCopy"),
                isOn: closesPanelAfterCopyBinding
            )

            Toggle(
                store.localized("ui.settings.option.restoreAfterCopy"),
                isOn: restoresPreviousAppAfterCopyBinding
            )
            .disabled(!store.closesPanelAfterCopy)

            Toggle(
                store.localized("ui.settings.option.showPreviewPane"),
                isOn: showsPreviewPaneBinding
            )

            VStack(alignment: .leading, spacing: 8) {
                Toggle(
                    store.localized("ui.settings.option.launchAtLogin"),
                    isOn: launchesAtLoginBinding
                )

                Text(launchAtLoginStatusDescription)
                    .font(.caption)
                    .foregroundStyle(launchAtLoginStatusTint)
            }
        }
    }

    private var captureSection: some View {
        settingsSection(
            title: store.localized("ui.settings.section.capture"),
            footer: store.localized("ui.settings.section.capture.footer")
        ) {
            Toggle(
                store.localized("ui.settings.option.monitorClipboard"),
                isOn: clipboardMonitoringBinding
            )

            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: maxHistoryItemsBinding,
                    in: AppSettings.minimumHistoryItemLimit...AppSettings.maximumHistoryItemLimit,
                    step: AppSettings.historyItemStep
                ) {
                    settingsValueRow(
                        title: store.localized("ui.settings.option.maxHistoryItems"),
                        value: store.localized("ui.settings.value.historyItems", store.settings.maxHistoryItems)
                    )
                }

                Text(store.localized("ui.settings.caption.maxHistoryItems"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Stepper(
                    value: maxStoredImageCacheSizeBinding,
                    in: AppSettings.minimumImageStorageLimitMB...AppSettings.maximumImageStorageLimitMB,
                    step: AppSettings.imageStorageStepMB
                ) {
                    settingsValueRow(
                        title: store.localized("ui.settings.option.maxImageCache"),
                        value: store.localized("ui.settings.value.imageCacheMB", store.settings.maxStoredImageCacheSizeMB)
                    )
                }

                Text(store.localized("ui.settings.caption.maxImageCache"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var ocrSection: some View {
        settingsSection(
            title: store.localized("ui.settings.section.ocr"),
            footer: store.localized("ui.settings.section.ocr.footer")
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text(store.localized("ui.settings.option.ocrMode"))
                    .font(.subheadline.weight(.medium))

                Picker("", selection: ocrModeBinding) {
                    ForEach(ClipboardOCRMode.allCases) { mode in
                        Text(ocrModeLabel(for: mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var updateSection: some View {
        settingsSection(
            title: store.localized("ui.settings.section.update"),
            footer: store.localized("ui.settings.section.update.footer")
        ) {
            Toggle(
                store.localized("ui.settings.option.autoCheckUpdates"),
                isOn: automaticUpdateCheckBinding
            )

            HStack(spacing: 10) {
                Button {
                    triggerManualUpdateCheck()
                } label: {
                    Label(
                        store.localized("ui.settings.button.checkUpdates"),
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(store.isCheckingForUpdates)

                if store.isCheckingForUpdates {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(store.localized("feedback.update.checking"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if let release = store.pendingUpdateRelease {
                    Text(store.localized("ui.settings.update.available", release.versionNumber))
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Spacer(minLength: 0)

                if store.pendingUpdateRelease != nil {
                    Button {
                        Task { await store.installUpdate() }
                    } label: {
                        Label(store.localized("ui.settings.button.installUpdate"), systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.green)
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        title: String,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.quaternary.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func settingsValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private var closesPanelAfterCopyBinding: Binding<Bool> {
        Binding(
            get: { store.closesPanelAfterCopy },
            set: { store.setClosesPanelAfterCopy($0) }
        )
    }

    private var restoresPreviousAppAfterCopyBinding: Binding<Bool> {
        Binding(
            get: { store.restoresPreviousAppAfterCopy },
            set: { store.setRestoresPreviousAppAfterCopy($0) }
        )
    }

    private var showsPreviewPaneBinding: Binding<Bool> {
        Binding(
            get: { store.showsPreviewPane },
            set: { store.setShowsPreviewPane($0) }
        )
    }

    private var launchesAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.launchesAtLogin },
            set: { store.setLaunchesAtLogin($0) }
        )
    }

    private var clipboardMonitoringBinding: Binding<Bool> {
        Binding(
            get: { store.isClipboardMonitoringEnabled },
            set: { store.setClipboardMonitoringEnabled($0) }
        )
    }

    private var maxHistoryItemsBinding: Binding<Int> {
        Binding(
            get: { store.settings.maxHistoryItems },
            set: { store.setMaxHistoryItems($0) }
        )
    }

    private var maxStoredImageCacheSizeBinding: Binding<Int> {
        Binding(
            get: { store.settings.maxStoredImageCacheSizeMB },
            set: { store.setMaxStoredImageCacheSizeMB($0) }
        )
    }

    private var ocrModeBinding: Binding<ClipboardOCRMode> {
        Binding(
            get: { store.ocrMode },
            set: { store.setOCRMode($0) }
        )
    }

    private var automaticUpdateCheckBinding: Binding<Bool> {
        Binding(
            get: { store.automaticallyChecksForUpdates },
            set: { store.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var selectedLanguageCodeBinding: Binding<String> {
        Binding(
            get: { localizationManager.selectedLanguageCode },
            set: { localizationManager.selectLanguage(code: $0) }
        )
    }

    private var launchAtLoginStatusDescription: String {
        switch store.launchAtLoginStatus {
        case .enabled:
            return store.localized("ui.settings.caption.launchAtLogin.enabled")
        case .disabled:
            return store.localized("ui.settings.caption.launchAtLogin.disabled")
        case .requiresApproval:
            return store.localized("ui.settings.caption.launchAtLogin.requiresApproval")
        case .unavailable:
            return store.localized("ui.settings.caption.launchAtLogin.unavailable")
        }
    }

    private var launchAtLoginStatusTint: AnyShapeStyle {
        switch store.launchAtLoginStatus {
        case .enabled, .disabled, .unavailable:
            return AnyShapeStyle(Color.secondary)
        case .requiresApproval:
            return AnyShapeStyle(Color.orange)
        }
    }

    private func languageLabel(for option: LanguageOption) -> String {
        if option.code == LocalizationManager.systemLanguageCode {
            let systemName = localizationManager.systemLanguageName
            return localizationManager.localized("ui.language.followSystem", systemName)
        }

        return option.label
    }

    private func ocrModeLabel(for mode: ClipboardOCRMode) -> String {
        switch mode {
        case .automatic:
            return store.localized("ui.settings.ocrMode.automatic")
        case .selectedOnly:
            return store.localized("ui.settings.ocrMode.selectedOnly")
        case .disabled:
            return store.localized("ui.settings.ocrMode.disabled")
        }
    }

    private func triggerManualUpdateCheck() {
        Task {
            _ = await store.checkForUpdatesManually()
        }
    }
}
