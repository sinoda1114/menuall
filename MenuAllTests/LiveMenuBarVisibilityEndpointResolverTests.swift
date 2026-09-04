import AppKit
import Testing
@testable import MenuAll

@Suite("LiveMenuBarVisibilityEndpointResolver")
@MainActor
struct LiveMenuBarVisibilityEndpointResolverTests {
    @Test("同じ画面の一意な項目と境界を操作可能にする")
    func resolvesUniqueEndpointOnSameDisplay() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])

        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)
        #expect(resolver.boundaryEndpoint()?.windowID == 77)
        #expect(resolver.observedVisibility(itemID: "item") == .visible)
    }

    @Test("変更後は同じwindow IDの位置を再観測する")
    func observesCachedWindowAfterMovement() {
        let initial = itemWindow(windowName: "Example")
            .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [initial, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(
                frame: CGRect(x: 300, y: 0, width: 38, height: 30),
                windowName: "Example"
            ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu"),
            boundaryWindow()
        ]

        #expect(resolver.observedVisibility(itemID: "item") == .hidden)
    }

    @Test("移動後にwindow IDが変わっても一意な明示名で再解決する")
    func rebindsAfterWindowIDChanges() {
        let initial = itemWindow(windowName: "Example")
            .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [initial, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(
                windowID: 11,
                frame: CGRect(x: 300, y: 0, width: 38, height: 30),
                windowName: "Example"
            ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu"),
            boundaryWindow()
        ]

        #expect(resolver.observedVisibility(itemID: "item") == .hidden)
        #expect(resolver.endpoint(for: "item")?.windowID == 11)
    }

    @Test("同じwindow IDが別項目へ再利用された場合はキャッシュを信用しない")
    func rejectsReusedWindowIDWithDifferentIdentity() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(
                windowID: 10,
                frame: CGRect(x: 300, y: 0, width: 38, height: 30),
                windowName: "com.example.Other"
            ),
            boundaryWindow()
        ]

        #expect(resolver.observedVisibility(itemID: "item") == .unknown)
        #expect(resolver.endpoint(for: "item") == nil)
    }

    @Test("同じPIDの別項目へwindow IDが切り替わっても再結合しない")
    func rejectsRebindingToDifferentItemFromSameProcess() {
        let initial = itemWindow(
            windowID: 10,
            frame: CGRect(x: 493, y: 0, width: 38, height: 30),
            windowName: "Example"
        ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [initial, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        let replacement = itemWindow(
            windowID: 11,
            frame: CGRect(x: 493, y: 0, width: 38, height: 30),
            windowName: "Different Item"
        ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        provider.windows = [replacement, boundaryWindow()]

        #expect(resolver.endpoint(for: "item") == nil)
        #expect(resolver.observedVisibility(itemID: "item") == .unknown)
    }

    @Test("名前なし項目は初回frameで結合し位置が変わったら安全側で停止する")
    func resolvesUnnamedWindowOnlyWhileFrameRemainsStable() {
        let unnamed = itemWindow(
            windowID: 10,
            windowName: nil
        ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [unnamed, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])

        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.observedVisibility(itemID: "item") == .visible)
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.beginLayoutTransaction(to: .hidden))
        provider.windows = [
            unnamed.replacingFrame(CGRect(x: 300, y: 0, width: 38, height: 30)),
            boundaryWindow()
        ]
        #expect(resolver.availability(for: "item") != .available)
        #expect(resolver.endpoints(for: "item") == nil)
        resolver.endLayoutTransaction()
    }

    @Test("名前なしwindowのIDが変わった場合は別項目へ再結合しない")
    func rejectsUnnamedWindowAfterIDChanges() {
        let initial = itemWindow(windowID: 10, windowName: nil)
            .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [initial, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(windowID: 11, windowName: nil)
                .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu"),
            boundaryWindow()
        ]

        #expect(resolver.endpoint(for: "item") == nil)
    }

    @Test("同一bundleの複数項目ではbundle名だけで別windowへ再結合しない")
    func rejectsBundleOnlyRebindWhenAppHasMultipleItems() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        let second = MenuBarItemSnapshot(
            id: "second",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Second",
            visibility: .visible,
            frame: CGRect(x: 550, y: 3, width: 24, height: 24)
        )
        resolver.update(items: [snapshot(), second])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(windowID: 11),
            boundaryWindow()
        ]

        #expect(resolver.endpoint(for: "item") == nil)
        #expect(resolver.observedVisibility(itemID: "item") == .unknown)
    }

    @Test("snapshotが1件でもbundle名だけの別windowへ再結合しない")
    func rejectsBundleOnlyRebindWithSingleStaleSnapshot() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [itemWindow(windowID: 11), boundaryWindow()]

        #expect(resolver.endpoint(for: "item") == nil)
        #expect(resolver.observedVisibility(itemID: "item") == .unknown)
    }

    @Test("fallback名が同じ同一PIDの別項目へ再結合しない")
    func rejectsFallbackTitleRebindWithinSameProcess() {
        let initial = itemWindow(windowID: 10, windowName: "Example")
            .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu")
        let provider = ResolverWindowProvider(windows: [initial, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        let unnamedItem = MenuBarItemSnapshot(
            id: "item",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Example",
            hasExplicitName: false,
            visibility: .visible,
            frame: CGRect(x: 500, y: 3, width: 24, height: 24)
        )
        resolver.update(items: [unnamedItem])
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(windowID: 11, windowName: "Example")
                .replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu"),
            boundaryWindow()
        ]

        #expect(resolver.endpoint(for: "item") == nil)
        #expect(
            resolver.rollbackEndpoints(
                for: "item",
                assumingCurrentVisibility: .hidden
            ) == nil
        )
    }

    @Test("境界展開前に確定した項目が消えたら旧frameの隣接項目を採用しない")
    func rejectsAdjacentItemMovingIntoStaleFrameAfterLayoutBegins() {
        let itemA = snapshot()
        let itemB = MenuBarItemSnapshot(
            id: "second",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Second",
            visibility: .visible,
            frame: CGRect(x: 550, y: 3, width: 24, height: 24)
        )
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [itemA, itemB])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoints(for: "item")?.item.windowID == 10)
        #expect(resolver.beginLayoutTransaction(to: .hidden))

        provider.windows = [
            itemWindow(windowID: 11, frame: CGRect(x: 493, y: 0, width: 38, height: 30)),
            boundaryWindow()
        ]

        #expect(resolver.availability(for: "item") != .available)
        #expect(resolver.endpoints(for: "item") == nil)
        resolver.endLayoutTransaction()
    }

    @Test("表示から非表示へ移動後は古いsnapshotに依存せずrollback endpointを解決する")
    func resolvesRollbackEndpointUsingExpectedCurrentVisibility() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot(visibility: .visible)])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(
                windowID: 10,
                frame: CGRect(x: 300, y: -122, width: 38, height: 30),
                displayID: nil,
                windowName: "Example"
            ).replacingOwner(pid: 42, bundleIdentifier: "com.example.Menu"),
            boundaryWindow()
        ]

        #expect(
            resolver.rollbackAvailability(
                for: "item",
                assumingCurrentVisibility: .hidden
            ) == .available
        )
        #expect(
            resolver.rollbackEndpoints(
                for: "item",
                assumingCurrentVisibility: .hidden
            )?.item.windowID == 10
        )
    }

    @Test("同じbundle内でwindow IDが別項目へ再利用された可能性がある場合も操作しない")
    func rejectsAmbiguousReusedWindowIDWithinSameBundle() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])
        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 10)

        provider.windows = [
            itemWindow(windowID: 10, frame: CGRect(x: 300, y: 0, width: 38, height: 30)),
            itemWindow(windowID: 11, frame: CGRect(x: 250, y: 0, width: 38, height: 30)),
            boundaryWindow()
        ]

        #expect(resolver.observedVisibility(itemID: "item") == .unknown)
        #expect(resolver.endpoint(for: "item") == nil)
    }

    @Test("画面外mirrorは同じbundleのprimary windowが一意なら安全に結合する")
    func resolvesOffscreenMirrorThroughUniquePrimaryWindow() {
        let offscreenMirror = itemWindow(
            windowID: 12,
            frame: CGRect(x: 493, y: -122, width: 38, height: 30),
            displayID: nil,
            windowName: "Item-0"
        )
        let primary = itemWindow(
            windowID: 13,
            frame: CGRect(x: 300, y: 0, width: 38, height: 30)
        )
        let provider = ResolverWindowProvider(windows: [offscreenMirror, primary, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot(
            visibility: .hidden,
            frame: CGRect(x: 500, y: -119, width: 24, height: 24)
        )])

        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.endpoint(for: "item")?.windowID == 13)
        #expect(resolver.observedVisibility(itemID: "item") == .hidden)
    }

    @Test("単一画面では安定identityの画面外hidden項目へPID限定endpointを作る")
    func resolvesHiddenPrimaryThatIsOffscreenOnSingleDisplay() {
        let offscreenPrimary = itemWindow(
            windowID: 13,
            frame: CGRect(x: 300, y: -122, width: 38, height: 30),
            displayID: nil
        )
        let provider = ResolverWindowProvider(windows: [offscreenPrimary, boundaryWindow()])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot(
            visibility: .hidden,
            frame: CGRect(x: 307, y: -119, width: 24, height: 24)
        )])

        #expect(resolver.availability(for: "item") == .available)
        #expect(resolver.observedVisibility(itemID: "item") == .hidden)
        #expect(resolver.endpoints(for: "item")?.item.windowID == 13)
        #expect(resolver.endpoints(for: "item")?.item.displayID == 1)
    }

    @Test("複数画面では画面外hidden項目の帰属を推定しない")
    func rejectsOffscreenHiddenPrimaryWhenMultipleDisplaysArePresent() {
        let offscreenPrimary = itemWindow(
            windowID: 13,
            frame: CGRect(x: 300, y: -122, width: 38, height: 30),
            displayID: nil
        )
        let provider = ResolverWindowProvider(windows: [
            offscreenPrimary,
            boundaryWindow()
        ], activeDisplayIDs: [1, 2])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot(
            visibility: .hidden,
            frame: CGRect(x: 307, y: -119, width: 24, height: 24)
        )])

        #expect(
            resolver.availability(for: "item")
                == .unavailable(reason: "この画面の表示切り替えはまだ利用できません。")
        )
        #expect(resolver.endpoints(for: "item") == nil)
    }

    @Test("画面外mirrorに対するprimary候補が複数なら操作しない")
    func rejectsAmbiguousPrimaryWindowsForOffscreenMirror() {
        let provider = ResolverWindowProvider(windows: [
            itemWindow(
                windowID: 12,
                frame: CGRect(x: 493, y: -122, width: 38, height: 30),
                displayID: nil,
                windowName: "Item-0"
            ),
            itemWindow(windowID: 13, frame: CGRect(x: 300, y: 0, width: 38, height: 30)),
            itemWindow(windowID: 14, frame: CGRect(x: 250, y: 0, width: 38, height: 30)),
            boundaryWindow()
        ])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot(
            visibility: .hidden,
            frame: CGRect(x: 500, y: -119, width: 24, height: 24)
        )])

        #expect(
            resolver.availability(for: "item")
                == .unavailable(reason: "対応するメニューバー項目を一意に特定できません。")
        )
    }

    @Test("別画面の境界にはイベントを送らない")
    func rejectsCrossDisplayBoundary() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow(displayID: 2)])
        let resolver = makeResolver(provider: provider)
        resolver.update(items: [snapshot()])

        #expect(
            resolver.availability(for: "item")
                == .unavailable(reason: "この画面の表示切り替えはまだ利用できません。")
        )
    }

    @Test("競合管理アプリの稼働中は具体名を理由に含める")
    func rejectsRunningManager() {
        let detector = ResolverConflictDetector(conflicts: [
            MenuBarManagerConflict(bundleIdentifier: "com.jordanbaird.Ice", displayName: "Ice")
        ])
        let section = MenuBarSectionController(
            conflictDetector: detector,
            statusItemFactory: ResolverBoundaryFactory()
        )
        let resolver = LiveMenuBarVisibilityEndpointResolver(
            sectionController: section,
            windowProvider: ResolverWindowProvider(windows: [])
        )
        resolver.update(items: [snapshot()])

        #expect(
            resolver.availability(for: "item")
                == .unavailable(reason: "Iceが起動中のため、同時に表示を変更できません。")
        )
    }

    @Test("同一IDが重複して届いてもクラッシュせず操作対象から除外する")
    func rejectsDuplicateItemIDs() {
        let provider = ResolverWindowProvider(windows: [itemWindow(), boundaryWindow()])
        let resolver = makeResolver(provider: provider)

        resolver.update(items: [snapshot(), snapshot()])

        #expect(
            resolver.availability(for: "item")
                == .unavailable(reason: "項目が更新されたため、もう一度お試しください。")
        )
        #expect(resolver.endpoint(for: "item") == nil)
    }

    private func makeResolver(
        provider: ResolverWindowProvider
    ) -> LiveMenuBarVisibilityEndpointResolver {
        let section = MenuBarSectionController(
            conflictDetector: ResolverConflictDetector(conflicts: []),
            statusItemFactory: ResolverBoundaryFactory()
        )
        return LiveMenuBarVisibilityEndpointResolver(
            sectionController: section,
            windowProvider: provider
        )
    }

    private func snapshot(
        visibility: MenuBarItemVisibility = .visible,
        frame: CGRect = CGRect(x: 500, y: 3, width: 24, height: 24)
    ) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(
            id: "item",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Example",
            visibility: visibility,
            frame: frame
        )
    }

    private func itemWindow(
        windowID: CGWindowID = 10,
        frame: CGRect = CGRect(x: 493, y: 0, width: 38, height: 30),
        displayID: CGDirectDisplayID? = 1,
        windowName: String? = "com.example.Menu"
    ) -> WindowServerMenuBarItemDescriptor {
        WindowServerMenuBarItemDescriptor(
            windowID: windowID,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: windowName,
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: frame,
            displayID: displayID
        )
    }

    private func boundaryWindow(
        displayID: CGDirectDisplayID = 1
    ) -> WindowServerMenuBarItemDescriptor {
        WindowServerMenuBarItemDescriptor(
            windowID: 77,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: "Item-0",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 400, y: 0, width: 40, height: 30),
            displayID: displayID
        )
    }
}

@MainActor
private final class ResolverConflictDetector: MenuBarManagerConflictDetecting {
    var conflicts: [MenuBarManagerConflict]

    init(conflicts: [MenuBarManagerConflict]) {
        self.conflicts = conflicts
    }

    func runningConflicts() -> [MenuBarManagerConflict] { conflicts }
}

@MainActor
private final class ResolverBoundaryItem: MenuBarBoundaryStatusItem {
    var length: CGFloat
    var autosaveName: String?
    let windowID: CGWindowID? = 77

    init(length: CGFloat) {
        self.length = length
    }
}

@MainActor
private final class ResolverBoundaryFactory: MenuBarBoundaryStatusItemFactory {
    func makeStatusItem(length: CGFloat) -> any MenuBarBoundaryStatusItem {
        ResolverBoundaryItem(length: length)
    }

    func removeStatusItem(_ item: any MenuBarBoundaryStatusItem) {}
}

private final class ResolverWindowProvider: WindowServerMenuBarItemDescriptorProviding {
    var windows: [WindowServerMenuBarItemDescriptor]
    var displays: Set<CGDirectDisplayID>

    init(
        windows: [WindowServerMenuBarItemDescriptor],
        activeDisplayIDs: Set<CGDirectDisplayID> = [1]
    ) {
        self.windows = windows
        displays = activeDisplayIDs
    }

    func descriptors() -> [WindowServerMenuBarItemDescriptor] { windows }
    func activeDisplayIDs() -> Set<CGDirectDisplayID> { displays }
}

private extension WindowServerMenuBarItemDescriptor {
    func replacingOwner(
        pid: pid_t,
        bundleIdentifier: String?
    ) -> WindowServerMenuBarItemDescriptor {
        WindowServerMenuBarItemDescriptor(
            windowID: windowID,
            ownerPID: pid,
            ownerName: ownerName,
            ownerBundleIdentifier: bundleIdentifier,
            windowName: windowName,
            layer: layer,
            frame: frame,
            displayID: displayID
        )
    }

    func replacingFrame(_ frame: CGRect) -> WindowServerMenuBarItemDescriptor {
        WindowServerMenuBarItemDescriptor(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            ownerBundleIdentifier: ownerBundleIdentifier,
            windowName: windowName,
            layer: layer,
            frame: frame,
            displayID: displayID
        )
    }
}
