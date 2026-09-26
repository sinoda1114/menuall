import AppKit
import SwiftUI

enum MenuAllDisplayMode: String, CaseIterable, Identifiable {
    case iconAndName
    case iconOnly
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .iconAndName: "アイコン＋名前"
        case .iconOnly: "アイコンのみ"
        case .list: "リスト表示"
        }
    }
}

struct MenuAllPopoverView: View {
    @Bindable var store: MenuBarStore

    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void
    let onRequestPermission: () -> Void
    let onOpenItem: (String) -> Void
    let onChangeVisibility: @Sendable (String, Bool) -> Void
    let onUndoVisibilityChange: () -> Void
    let onStart: () -> Void
    let showsPermissionCompletion: Bool

    @AppStorage("displayMode") private var displayModeRaw = MenuAllDisplayMode.iconAndName.rawValue
    @AppStorage("prioritizeHidden") private var prioritizeHidden = true
    @AppStorage("showSystemItems") private var showSystemItems = false

    private var displayMode: MenuAllDisplayMode {
        MenuAllDisplayMode(rawValue: displayModeRaw) ?? .iconAndName
    }

    private var displayedItems: [MenuBarItemSnapshot] {
        store.items.filter { item in
            showSystemItems || !(item.bundleIdentifier?.hasPrefix("com.apple.") ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if showsPermissionCompletion, store.isAccessibilityTrusted {
                permissionGrantedContent
            } else if !store.isAccessibilityTrusted {
                permissionContent
            } else {
                discoveredContent
            }

            Divider()
            footer
        }
        .frame(width: 380)
        .background(MenuAllPalette.canvas)
        .environment(store)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("MenuAll")
        .accessibilityIdentifier(showsPermissionCompletion ? "menuall.onboarding" : "menuall.popover")
    }
}

private extension MenuAllPopoverView {
    var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("MenuAll")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.isAccessibilityTrusted ? "\(displayedItems.count)個のメニューバー項目" : "メニューバーを、ひとつに。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(store.isRefreshing ? .degrees(360) : .zero)
                    .animation(
                        store.isRefreshing
                            ? .linear(duration: 0.85).repeatForever(autoreverses: false)
                            : .default,
                        value: store.isRefreshing
                    )
            }
            .buttonStyle(HeaderIconButtonStyle())
            .disabled(!store.isAccessibilityTrusted || store.isRefreshing)
            .help("再読み込み")
            .accessibilityLabel("再読み込み")
            .accessibilityIdentifier("menuall.refresh")

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(HeaderIconButtonStyle())
            .help("設定")
            .accessibilityLabel("設定")
            .accessibilityIdentifier("menuall.settings")
        }
        .padding(.horizontal, 16)
        .frame(height: 54)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuall.popover.header")
    }

    var permissionContent: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(MenuAllPalette.hiddenTint)
                    .frame(width: 64, height: 64)
                Image(systemName: "rectangle.3.group.bubble.left.fill")
                    .font(.system(size: 27, weight: .medium))
                    .foregroundStyle(MenuAllPalette.accent)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 7) {
                Text("未許可")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MenuAllPalette.warning)
                    .accessibilityIdentifier("menuall.permission.state.denied")
                Text("メニューバーを、ひとつにまとめる。")
                    .font(.system(size: 17, weight: .semibold))
                Text("画面に収まらない項目を確認して操作するため、アクセシビリティ権限を使用します。情報は外部へ送信しません。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 320)
                    .accessibilityIdentifier("menuall.permission.reason")
            }

            Button("システム設定を開く", action: onRequestPermission)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("menuall.permission.open-system-settings")

            Button("権限を再確認", action: onRefresh)
                .buttonStyle(.link)
                .font(.system(size: 12))
                .accessibilityIdentifier("menuall.permission.recheck")
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, minHeight: 330)
    }

    var permissionGrantedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("設定完了")
                .font(.system(size: 17, weight: .semibold))
                .accessibilityIdentifier("menuall.permission.state.granted")
            Text("MenuAllを利用できるようになりました")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("MenuAllを開始", action: onStart)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, minHeight: 330)
        .padding(28)
    }

    var discoveredContent: some View {
        VStack(spacing: 0) {
            if !store.failures.isEmpty {
                failureBanner
            }

            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(sections, id: \.identifier) { section in
                        if !section.items.isEmpty {
                            itemSection(
                                section.title,
                                count: section.items.count,
                                items: section.items,
                                emphasis: section.emphasis,
                                identifier: section.identifier
                            )
                        }
                    }

                    if displayedItems.isEmpty, !store.isRefreshing {
                        emptyState
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 260, maxHeight: 460)

            if let error = store.visibilityErrorMessage {
                visibilityErrorBanner(error)
            } else if let undo = store.visibilityUndo {
                visibilityUndoBanner(undo)
            }

            if let openedItemName = store.lastOpenedItemName {
                Text("\(openedItemName)の元のメニューを開きました")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("menuall.item-opened")
            }
        }
    }

    var failureBanner: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MenuAllPalette.warning)
            Text("一部のアプリを確認できませんでした")
                .font(.system(size: 11, weight: .medium))
            Spacer()
            Text("\(store.failures.count)件")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(MenuAllPalette.warningTint)
        .accessibilityElement(children: .combine)
    }

    var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("取得できる項目がありません")
                .font(.system(size: 12, weight: .medium))
            Text("アプリを起動してから再読み込みしてください。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menuall.popover.empty")
    }

    var footer: some View {
        HStack(spacing: 10) {
            Text(store.actionErrorMessage ?? "名前でメニュー、スイッチで表示を切り替えます")
                .font(.system(size: 10))
                .foregroundStyle(store.actionErrorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(MenuAllPalette.warning))
                .lineLimit(1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(store.actionErrorMessage ?? "名前でメニュー、スイッチで表示を切り替えます")
                .accessibilityIdentifier(
                    store.actionErrorMessage == nil ? "menuall.action-guidance" : "menuall.action-error"
                )
            Spacer()
            Button("終了", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
                .accessibilityIdentifier("menuall.quit")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }

    var sections: [(
        title: String,
        items: [MenuBarItemSnapshot],
        emphasis: Bool,
        identifier: String
    )] {
        let unavailable = displayedItems.filter { item in
            item.visibility == .unknown || !isVisibilityChangeAvailable(for: item)
        }
        let unavailableIDs = Set(unavailable.map(\.id))
        let hidden = displayedItems.filter {
            $0.visibility == .hidden && !unavailableIDs.contains($0.id)
        }
        let visible = displayedItems.filter {
            $0.visibility == .visible && !unavailableIDs.contains($0.id)
        }

        let hiddenSection = (
            "メニューバーで非表示",
            hidden,
            true,
            "menuall.section.hidden"
        )
        let visibleSection = (
            "メニューバーに表示中",
            visible,
            false,
            "menuall.section.visible"
        )

        let availableSections = prioritizeHidden
            ? [hiddenSection, visibleSection]
            : [visibleSection, hiddenSection]
        return availableSections + [(
            "表示切り替えができない項目",
            unavailable,
            false,
            "menuall.section.unavailable"
        )]
    }

    func itemSection(
        _ title: String,
        count: Int,
        items: [MenuBarItemSnapshot],
        emphasis: Bool,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                if emphasis {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MenuAllPalette.accent)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(identifier)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)

            switch displayMode {
            case .iconAndName, .iconOnly:
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        MenuBarItemTile(item: item, mode: displayMode) {
                            onOpenItem(item.id)
                        } onChangeVisibility: { shouldShow in
                            onChangeVisibility(item.id, shouldShow)
                        }
                    }
                }
            case .list:
                VStack(spacing: 5) {
                    ForEach(items) { item in
                        MenuBarItemRow(item: item) {
                            onOpenItem(item.id)
                        } onChangeVisibility: { shouldShow in
                            onChangeVisibility(item.id, shouldShow)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(emphasis ? MenuAllPalette.hiddenTint : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    func isVisibilityChangeAvailable(for item: MenuBarItemSnapshot) -> Bool {
        guard item.visibility != .unknown else { return false }
        guard let availability = store.visibilityAvailability[item.id] else { return false }
        if case .available = availability { return true }
        return false
    }

    func visibilityErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(MenuAllPalette.warning)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 38)
        .background(MenuAllPalette.warningTint)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("menuall.visibility.error")
    }

    func visibilityUndoBanner(_ undo: MenuBarVisibilityUndo) -> some View {
        HStack(spacing: 8) {
            Text("\(undo.itemTitle)を\(undo.changedVisibility == .visible ? "表示" : "非表示")にしました")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("元に戻す", action: onUndoVisibilityChange)
                .buttonStyle(.borderless)
                .keyboardShortcut("z")
                .disabled(
                    !store.visibilityChangePhases.isEmpty
                        || store.isPerformingOriginalItemAction
                )
                .accessibilityIdentifier("menuall.visibility.undo.action")
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(MenuAllPalette.hiddenTint)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuall.visibility.undo")
    }
}

private struct MenuBarItemTile: View {
    let item: MenuBarItemSnapshot
    let mode: MenuAllDisplayMode
    let onOpen: () -> Void
    let onChangeVisibility: @Sendable (Bool) -> Void

    @Environment(MenuBarStore.self) private var store

    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onOpen) {
                VStack(spacing: mode == .iconOnly ? 0 : 7) {
                    ApplicationIcon(item: item, size: 27)
                    if mode != .iconOnly {
                        Text(item.title)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: mode == .iconOnly ? 52 : 72)
                .background(isHovering ? MenuAllPalette.hover : MenuAllPalette.tile)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MenuAllPalette.border, lineWidth: 0.5)
                }
            }
            .buttonStyle(.plain)
            .disabled(
                !store.visibilityChangePhases.isEmpty
                    || store.isPerformingOriginalItemAction
            )
            .onHover { isHovering = $0 }
            .help(item.detail ?? "\(item.ownerName) — \(item.title)")
            .accessibilityLabel("\(item.title)のメニューを開く")
            .accessibilityHint("\(item.ownerName)の元のメニューを開きます")
            .accessibilityIdentifier("menuall.item.\(item.id).open")

            VStack(alignment: .trailing, spacing: 2) {
                visibilityToggle
                if let reason = unavailableReason {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help(reason)
                        .accessibilityLabel(reason)
                        .accessibilityIdentifier("menuall.item.\(item.id).visibility-unsupported")
                } else if store.visibilityChangePhases[item.id] != nil {
                    ProgressView()
                        .controlSize(.mini)
                        .accessibilityLabel("\(item.title)の表示を変更中")
                        .accessibilityIdentifier("menuall.item.\(item.id).visibility-progress")
                }
            }
            .padding(5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuall.item.\(item.id)")
    }

    private var visibilityToggle: some View {
        Toggle(
            "\(item.title)をメニューバーに表示",
            isOn: Binding(
                get: { desiredVisibility },
                set: onChangeVisibility
            )
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.mini)
        .disabled(
            unavailableReason != nil
                || !store.visibilityChangePhases.isEmpty
                || store.isPerformingOriginalItemAction
        )
        .help(unavailableReason ?? (desiredVisibility ? "メニューバーから隠す" : "メニューバーに表示"))
        .accessibilityHint(unavailableReason ?? (desiredVisibility ? "オフにするとメニューバーから隠します" : "オンにするとメニューバーに表示します"))
        .accessibilityIdentifier("menuall.item.\(item.id).visibility-toggle")
    }

    private var desiredVisibility: Bool {
        if let phase = store.visibilityChangePhases[item.id] {
            switch phase {
            case let .changing(target), let .verifying(target):
                return target == .shown
            }
        }
        return item.visibility == .visible
    }

    private var unavailableReason: String? {
        if item.visibility == .unknown { return "現在の表示状態を確認できません。" }
        guard let availability = store.visibilityAvailability[item.id] else {
            return "表示切り替えの可否を確認中です。"
        }
        if case let .unavailable(reason) = availability { return reason }
        return nil
    }
}

private struct MenuBarItemRow: View {
    let item: MenuBarItemSnapshot
    let onOpen: () -> Void
    let onChangeVisibility: @Sendable (Bool) -> Void

    @Environment(MenuBarStore.self) private var store

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onOpen) {
            HStack(spacing: 10) {
                ApplicationIcon(item: item, size: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11, weight: .medium))
                    if item.ownerName != item.title {
                        Text(item.ownerName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            }
            .buttonStyle(.plain)
            .disabled(
                !store.visibilityChangePhases.isEmpty
                    || store.isPerformingOriginalItemAction
            )
            .onHover { isHovering = $0 }
            .accessibilityLabel("\(item.title)のメニューを開く")
            .accessibilityHint("\(item.ownerName)の元のメニューを開きます")
            .accessibilityIdentifier("menuall.item.\(item.id).open")

            Toggle(
                "\(item.title)をメニューバーに表示",
                isOn: Binding(
                    get: { desiredVisibility },
                    set: onChangeVisibility
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(
                unavailableReason != nil
                    || !store.visibilityChangePhases.isEmpty
                    || store.isPerformingOriginalItemAction
            )
            .accessibilityHint(unavailableReason ?? (desiredVisibility ? "オフにするとメニューバーから隠します" : "オンにするとメニューバーに表示します"))
            .accessibilityIdentifier("menuall.item.\(item.id).visibility-toggle")

            if store.visibilityChangePhases[item.id] != nil {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("\(item.title)の表示を変更中")
                    .accessibilityIdentifier("menuall.item.\(item.id).visibility-progress")
            } else if let unavailableReason {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                    .help(unavailableReason)
                    .accessibilityLabel(unavailableReason)
                    .accessibilityIdentifier("menuall.item.\(item.id).visibility-unsupported")
            }
        }
        .padding(.horizontal, 4)
        .background(isHovering ? MenuAllPalette.hover : MenuAllPalette.tile)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("menuall.item.\(item.id)")
    }

    private var desiredVisibility: Bool {
        if let phase = store.visibilityChangePhases[item.id] {
            switch phase {
            case let .changing(target), let .verifying(target): return target == .shown
            }
        }
        return item.visibility == .visible
    }

    private var unavailableReason: String? {
        if item.visibility == .unknown { return "現在の表示状態を確認できません。" }
        guard let availability = store.visibilityAvailability[item.id] else {
            return "表示切り替えの可否を確認中です。"
        }
        if case let .unavailable(reason) = availability { return reason }
        return nil
    }
}

private struct ApplicationIcon: View {
    let item: MenuBarItemSnapshot
    let size: CGFloat

    var body: some View {
        Group {
            if let bundleURL = item.bundleURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(configuration.isPressed ? MenuAllPalette.hover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

enum MenuAllPalette {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let tile = Color(nsColor: .controlBackgroundColor).opacity(0.78)
    static let hover = Color(nsColor: .selectedContentBackgroundColor).opacity(0.16)
    static let border = Color(nsColor: .separatorColor).opacity(0.72)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.35, green: 0.61, blue: 1.0, alpha: 1)
            : NSColor(calibratedRed: 0.13, green: 0.42, blue: 0.96, alpha: 1)
    })
    static let hiddenTint = accent.opacity(0.085)
    static let warning = Color(nsColor: .systemOrange)
    static let warningTint = warning.opacity(0.085)
}
