import CoreGraphics
import Foundation

/// 最新のAXスナップショットをWindowServer上のstatus windowへ安全側で結合する。
/// キャッシュしたwindow IDは安定identityを毎回再確認し、消失・再利用時は安全側で再解決する。
@MainActor
final class LiveMenuBarVisibilityEndpointResolver: MenuBarVisibilityEndpointResolving {
    private let sectionController: MenuBarSectionController
    private let windowProvider: any WindowServerMenuBarItemDescriptorProviding
    private let matcher: WindowServerMenuBarItemMatcher
    private var itemsByID: [String: MenuBarItemSnapshot] = [:]
    /// Window IDはWindowServerにより再利用されるため、IDだけでは対象を信用しない。
    /// キャッシュを使う場合も、現在のdescriptorが項目の安定identityと一致することを毎回確認する。
    private var matchedWindows: [String: WindowServerMenuBarItemDescriptor] = [:]
    private var isLayoutTransactionActive = false

    init(
        sectionController: MenuBarSectionController,
        windowProvider: any WindowServerMenuBarItemDescriptorProviding = WindowServerMenuBarItemDescriptorProvider(),
        matcher: WindowServerMenuBarItemMatcher = .init(frameTolerance: 1)
    ) {
        self.sectionController = sectionController
        self.windowProvider = windowProvider
        self.matcher = matcher
    }

    func update(items: [MenuBarItemSnapshot]) {
        var next: [String: MenuBarItemSnapshot] = [:]
        var duplicateIDs = Set<String>()
        for item in items {
            guard !duplicateIDs.contains(item.id) else { continue }
            if next.updateValue(item, forKey: item.id) != nil {
                next[item.id] = nil
                duplicateIDs.insert(item.id)
            }
        }
        itemsByID = next
        // AXの再取得を世代境界とし、WindowServer ID再利用の影響を持ち越さない。
        matchedWindows.removeAll()
    }

    func availabilitySnapshot() -> [String: VisibilityControlAvailability] {
        sectionController.refreshAvailability()
        let windows = windowProvider.descriptors()
        return itemsByID.reduce(into: [:]) { result, entry in
            result[entry.key] = evaluateAvailability(for: entry.value, windows: windows)
        }
    }

    func availability(for itemID: String) -> VisibilityControlAvailability {
        sectionController.refreshAvailability()
        guard let item = itemsByID[itemID] else {
            return .unavailable(reason: "項目が更新されたため、もう一度お試しください。")
        }
        return evaluateAvailability(for: item, windows: windowProvider.descriptors())
    }

    private func evaluateAvailability(
        for item: MenuBarItemSnapshot,
        windows: [WindowServerMenuBarItemDescriptor]
    ) -> VisibilityControlAvailability {
        if let conflict = sectionController.conflicts.first {
            return .unavailable(
                reason: "\(conflict.displayName)が起動中のため、同時に表示を変更できません。"
            )
        }
        guard sectionController.isSafeForVisibilityChange else {
            return .unavailable(reason: "表示・非表示の境界を準備できません。")
        }
        guard item.visibility != .unknown else {
            return .unavailable(reason: "現在の表示状態を確認できません。")
        }

        guard let boundary = boundaryWindow(in: windows) else {
            return .unavailable(reason: "表示・非表示の境界を特定できません。")
        }

        switch resolveOperationalWindow(for: item, windows: windows) {
        case let .matched(window):
            if item.visibility == .hidden,
               window.displayID == nil,
               inferredDisplayID(
                   for: window,
                   snapshot: item,
                   boundary: boundary,
                   windows: windows
               ) != nil {
                // 単一画面で安定identityが一意なら、画面外windowへPID限定イベントを
                // 送れる。複数画面で帰属が曖昧な場合は推定しない。
                return .available
            }
            guard let itemDisplayID = window.displayID,
                  let boundaryDisplayID = boundary.displayID,
                  itemDisplayID == boundaryDisplayID
            else {
                return .unavailable(reason: "この画面の表示切り替えはまだ利用できません。")
            }
            return .available
        case let .unsupported(reason):
            return .unavailable(reason: reason)
        }
    }

    func endpoint(for itemID: String) -> MenuBarVisibilityEndpoint? {
        let windows = windowProvider.descriptors()
        guard let item = itemsByID[itemID],
              case let .matched(window) = resolveOperationalWindow(for: item, windows: windows)
        else { return nil }
        matchedWindows[itemID] = window
        return endpoint(from: window, itemID: itemID)
    }

    func boundaryEndpoint() -> MenuBarVisibilityEndpoint? {
        guard let boundary = boundaryWindow(in: windowProvider.descriptors()) else { return nil }
        return endpoint(from: boundary, itemID: "menuall.hidden-section-boundary")
    }

    func endpoints(
        for itemID: String
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)? {
        endpoints(for: itemID, assumedVisibility: nil)
    }

    func rollbackAvailability(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> VisibilityControlAvailability {
        sectionController.refreshAvailability()
        guard let item = itemsByID[itemID] else {
            return .unavailable(reason: "項目が更新されたため、もう一度お試しください。")
        }
        return evaluateAvailability(
            for: item.replacingVisibility(with: visibility),
            windows: windowProvider.descriptors()
        )
    }

    func rollbackEndpoints(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)? {
        endpoints(for: itemID, assumedVisibility: visibility)
    }

    private func endpoints(
        for itemID: String,
        assumedVisibility: MenuBarItemVisibility?
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)? {
        let windows = windowProvider.descriptors()
        guard let storedSnapshot = itemsByID[itemID] else { return nil }
        let snapshot = assumedVisibility.map {
            storedSnapshot.replacingVisibility(with: $0)
        } ?? storedSnapshot
        guard
              case let .matched(itemWindow) = resolveOperationalWindow(
                  for: snapshot,
                  windows: windows
              ),
              let boundaryWindow = boundaryWindow(in: windows),
              let boundaryDisplayID = boundaryWindow.displayID,
              let itemDisplayID = inferredDisplayID(
                  for: itemWindow,
                  snapshot: snapshot,
                  boundary: boundaryWindow,
                  windows: windows
              ),
              itemDisplayID == boundaryDisplayID
        else { return nil }

        matchedWindows[itemID] = itemWindow
        return (
            endpoint(from: itemWindow, itemID: itemID, displayID: itemDisplayID),
            endpoint(from: boundaryWindow, itemID: "menuall.hidden-section-boundary")
        )
    }

    func observedVisibility(itemID: String) -> MenuBarItemVisibility {
        let windows = windowProvider.descriptors()
        guard let snapshot = itemsByID[itemID],
              case let .matched(item) = resolveOperationalWindow(
                  for: snapshot,
                  windows: windows
              ),
              let boundary = boundaryWindow(in: windows),
              let boundaryDisplayID = boundary.displayID
        else {
            return .unknown
        }

        matchedWindows[itemID] = item

        // 安定identityを持つstatus windowがどの画面にも属さない場合は、
        // 画面外へ退避された非表示項目として安全に観測できる。
        guard let itemDisplayID = item.displayID else {
            return .hidden
        }
        guard itemDisplayID == boundaryDisplayID else { return .unknown }

        return item.frame.midX < boundary.frame.midX ? .hidden : .visible
    }

    /// 初回の厳密なフレーム結合と、再レイアウト後の再結合を分けて判定する。
    /// 再結合では項目名、またはsnapshot内で一意なbundle primaryを必須にし、
    /// 同一アプリの別項目へイベントを送ることを防ぐ。
    private func resolveOperationalWindow(
        for item: MenuBarItemSnapshot,
        windows: [WindowServerMenuBarItemDescriptor]
    ) -> WindowServerMenuBarItemMatch {
        let candidates = windows.filter { $0.windowID != sectionController.boundaryWindowID }
        let frameMatch = resolveWindow(for: item, windows: candidates)
        if case let .unsupported(reason) = frameMatch,
           reason == "macOSにより位置が固定されている項目です。" {
            return frameMatch
        }

        guard let cachedWindow = matchedWindows[item.id] else {
            if case let .matched(window) = frameMatch,
               hasInitialIdentity(window, for: item) {
                return .matched(window)
            }
            if let bundleIdentifier = item.bundleIdentifier {
                let sameBundleItemCount = itemsByID.values.filter {
                    equalsIgnoringCase($0.bundleIdentifier, bundleIdentifier)
                }.count
                let primaryCandidates = candidates.filter {
                    equalsIgnoringCase($0.windowName, bundleIdentifier)
                }
                if sameBundleItemCount == 1,
                   primaryCandidates.count == 1,
                   let primary = primaryCandidates.first {
                    return .matched(primary)
                }
                if primaryCandidates.count > 1 {
                    return .unsupported(reason: "対応するメニューバー項目を一意に特定できません。")
                }
            }
            if case let .unsupported(reason) = frameMatch {
                return .unsupported(reason: reason)
            }
            return .unsupported(reason: "対応するメニューバー項目を安全に特定できません。")
        }

        if let currentWindow = candidates.first(where: {
            $0.windowID == cachedWindow.windowID
        }), hasSameStableWindowProperties(currentWindow, as: cachedWindow) {
            let frameStillIdentifiesCachedWindow: Bool
            if case let .matched(window) = frameMatch {
                frameStillIdentifiesCachedWindow = window.windowID == currentWindow.windowID
            } else {
                frameStillIdentifiesCachedWindow = false
            }
            if frameStillIdentifiesCachedWindow
                || currentWindow.frame == cachedWindow.frame
                || (isLayoutTransactionActive && hasRebindIdentity(currentWindow, for: item)) {
                return .matched(currentWindow)
            }
        }

        let rebindCandidates = candidates.filter { hasRebindIdentity($0, for: item) }
        if rebindCandidates.count == 1, let match = rebindCandidates.first {
            return .matched(match)
        }
        if rebindCandidates.count > 1 {
            return .unsupported(reason: "対応するメニューバー項目を一意に特定できません。")
        }

        if case let .unsupported(reason) = frameMatch {
            return .unsupported(reason: reason)
        }
        return .unsupported(reason: "対応するメニューバー項目を安全に特定できません。")
    }

    private func hasInitialIdentity(
        _ window: WindowServerMenuBarItemDescriptor,
        for item: MenuBarItemSnapshot
    ) -> Bool {
        if window.ownerPID == item.ownerPID { return true }
        if let bundleIdentifier = item.bundleIdentifier,
           equalsIgnoringCase(window.ownerBundleIdentifier, bundleIdentifier) {
            return true
        }
        return item.bundleIdentifier.map { equalsIgnoringCase(window.windowName, $0) } ?? false
    }

    private func hasRebindIdentity(
        _ window: WindowServerMenuBarItemDescriptor,
        for item: MenuBarItemSnapshot
    ) -> Bool {
        guard item.hasExplicitName else { return false }
        let sameNamedItemCount = itemsByID.values.filter {
            $0.hasExplicitName
                && $0.ownerPID == item.ownerPID
                && normalized($0.title) == normalized(item.title)
        }.count
        if sameNamedItemCount == 1,
           window.ownerPID == item.ownerPID,
           normalized(window.windowName) == normalized(item.title),
           normalized(item.title) != nil {
            return true
        }
        return false
    }

    private func hasSameStableWindowProperties(
        _ current: WindowServerMenuBarItemDescriptor,
        as cached: WindowServerMenuBarItemDescriptor
    ) -> Bool {
        current.ownerPID == cached.ownerPID
            && normalized(current.ownerBundleIdentifier) == normalized(cached.ownerBundleIdentifier)
            && normalized(current.windowName) == normalized(cached.windowName)
    }

    private func equalsIgnoringCase(_ lhs: String?, _ rhs: String) -> Bool {
        lhs?.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func inferredDisplayID(
        for window: WindowServerMenuBarItemDescriptor,
        snapshot: MenuBarItemSnapshot,
        boundary: WindowServerMenuBarItemDescriptor,
        windows: [WindowServerMenuBarItemDescriptor]
    ) -> CGDirectDisplayID? {
        if let displayID = window.displayID { return displayID }
        guard snapshot.visibility == .hidden,
              let boundaryDisplayID = boundary.displayID
        else { return nil }

        guard windowProvider.activeDisplayIDs() == Set([boundaryDisplayID]) else { return nil }
        return boundaryDisplayID
    }

    func beginLayoutTransaction(to target: MenuBarVisibilityTarget) -> Bool {
        let didBegin = sectionController.beginVisibilityChange(to: target)
        isLayoutTransactionActive = didBegin
        return didBegin
    }

    func endLayoutTransaction() {
        isLayoutTransactionActive = false
        sectionController.endVisibilityChange()
    }

    private func resolveWindow(
        for item: MenuBarItemSnapshot,
        windows: [WindowServerMenuBarItemDescriptor]? = nil
    ) -> WindowServerMenuBarItemMatch {
        matcher.match(
            item: AccessibilityMenuBarItemDescriptor(
                itemID: item.id,
                ownerPID: item.ownerPID,
                ownerName: item.ownerName,
                bundleIdentifier: item.bundleIdentifier,
                title: item.title,
                frame: item.frame
            ),
            among: windows ?? windowProvider.descriptors()
        )
    }

    private func boundaryWindow(
        in windows: [WindowServerMenuBarItemDescriptor]
    ) -> WindowServerMenuBarItemDescriptor? {
        guard let windowID = sectionController.boundaryWindowID else { return nil }
        return windows.first { $0.windowID == windowID }
    }

    private func endpoint(
        from window: WindowServerMenuBarItemDescriptor,
        itemID: String,
        displayID: CGDirectDisplayID? = nil
    ) -> MenuBarVisibilityEndpoint {
        MenuBarVisibilityEndpoint(
            itemID: itemID,
            windowID: window.windowID,
            sourcePID: window.ownerPID,
            frame: window.frame,
            displayID: displayID ?? window.displayID
        )
    }
}
