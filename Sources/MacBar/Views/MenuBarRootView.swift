import AppKit
import SwiftUI

struct MenuBarRootView: View {
    @ObservedObject var store: MacBarStore
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
                        destinationSection(title: "收藏", items: store.favoriteDestinations)
                    }

                    if store.groupedSearchResults.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("没有匹配结果")
                                .font(.subheadline.weight(.semibold))
                            Text("试试关键字：触控板、Wi-Fi、隐私")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                    } else {
                        ForEach(store.groupedSearchResults) { section in
                            destinationSection(title: section.category.title, items: section.items)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()
            footer

            if !store.statusMessage.isEmpty {
                Text(store.statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }
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
                Text("快速进入 macOS 常用设置")
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
        TextField("搜索设置项（例如：触控板 / Wi-Fi / 隐私）", text: $store.searchText)
            .textFieldStyle(.roundedBorder)
            .focused($isSearchFieldFocused)
    }

    private var footer: some View {
        HStack {
            Button("系统设置主页") {
                let result = navigator.openSystemSettingsHome()
                store.setStatus(result.message)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Spacer()

            Button("退出 MacBar") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private var statusColor: Color {
        if store.statusMessage.contains("失败") || store.statusMessage.contains("无法") {
            return .red
        }

        if store.statusMessage.contains("手动") || store.statusMessage.contains("未检测到") {
            return .orange
        }

        return .secondary
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
                Text(destination.title)
                    .font(.subheadline.weight(.semibold))
                Text(destination.subtitle)
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
            .help(store.isFavorite(destination.id) ? "取消收藏" : "加入收藏")

            Button("打开") {
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
        let result = navigator.open(destination)
        store.setStatus(result.message)
    }
}
