import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: MacBarStore
    @ObservedObject var localizationManager: LocalizationManager
    let navigator: SettingsNavigator
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchBar
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.isSearching, !store.favoriteDestinations.isEmpty {
                        destinationSection(
                            title: store.localized("ui.section.favorites"),
                            items: store.favoriteDestinations
                        )
                    }

                    if store.groupedSearchResults.isEmpty {
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
                        ForEach(store.groupedSearchResults) { section in
                            destinationSection(
                                title: store.localizedTitle(for: section.category),
                                items: section.items
                            )
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(minWidth: 420, idealWidth: 440, maxWidth: 460, minHeight: 560, idealHeight: 620)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MacBar")
                    .font(.title3.weight(.bold))
                Text(store.localized("app.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "switch.2")
                .font(.title2)
                .foregroundStyle(.orange)
        }
    }

    private var searchBar: some View {
        TextField(store.localized("ui.search.placeholder"), text: $store.searchText)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFieldFocused)
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
                destinationRow(destination)
            }
        }
    }

    private func destinationRow(_ destination: SettingsDestination) -> some View {
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
                open(destination)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.25))
        )
    }

    private func open(_ destination: SettingsDestination) {
        _ = navigator.open(destination)
    }

    private func languageLabel(for option: LanguageOption) -> String {
        if option.code == LocalizationManager.systemLanguageCode {
            let systemName = localizationManager.systemLanguageName
            return localizationManager.localized("ui.language.followSystem", systemName)
        }

        return option.label
    }
}
