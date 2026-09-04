import CoreGraphics
import Foundation
import Testing
@testable import MenuAll

@Suite("MenuBarRefreshCoordinator", .serialized)
@MainActor
struct MenuBarRefreshCoordinatorTests {
    @Test("更新処理時間を周期から差し引き超過時は待機しない")
    func calculatesFixedCadenceDelay() {
        #expect(
            MenuBarRefreshCadence.delay(
                interval: .seconds(2),
                refreshDuration: .milliseconds(1_400)
            ) == .milliseconds(600)
        )
        #expect(
            MenuBarRefreshCadence.delay(
                interval: .seconds(2),
                refreshDuration: .milliseconds(2_400)
            ) == .zero
        )
    }

    @Test("一部の取得に失敗しても成功項目と失敗情報を同時に更新する")
    func keepsSuccessfulItemsAlongsideFailures() async {
        let item = makeItem(id: "available-item", title: "Available")
        let failure = MenuBarDiscoveryFailure(
            id: "failed-app",
            ownerPID: 200,
            ownerName: "Unavailable",
            errorCode: -1,
            message: "項目を取得できませんでした"
        )
        let permission = FakeAccessibilityPermissionService(isTrusted: true)
        let discovery = FakeMenuBarDiscoveryService(
            results: [(items: [item], failures: [failure])]
        )
        let store = MenuBarStore()
        let coordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: permission,
            discoveryService: discovery
        )

        await coordinator.refresh()

        #expect(store.items == [item])
        #expect(store.failures.count == 1)
        #expect(store.failures.first?.id == failure.id)
        #expect(store.isAccessibilityTrusted)
        #expect(!store.isRefreshing)
        #expect(store.lastUpdatedAt != nil)
        #expect(discovery.discoverCallCount == 1)
    }

    @Test("権限が失われたら古い項目と失敗情報を残さない")
    func clearsStaleStateWhenPermissionIsMissing() async {
        let staleItem = makeItem(id: "stale-item", title: "Stale")
        let staleFailure = MenuBarDiscoveryFailure(
            id: "stale-failure",
            ownerPID: 300,
            ownerName: "Stale App",
            errorCode: -1,
            message: "古い失敗"
        )
        let store = MenuBarStore()
        store.items = [staleItem]
        store.failures = [staleFailure]
        store.lastUpdatedAt = .now
        store.actionErrorMessage = "古い操作エラー"
        let permission = FakeAccessibilityPermissionService(isTrusted: false)
        let discovery = FakeMenuBarDiscoveryService(results: [])
        let coordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: permission,
            discoveryService: discovery
        )

        await coordinator.refresh()

        #expect(store.items.isEmpty)
        #expect(store.failures.isEmpty)
        #expect(store.lastUpdatedAt == nil)
        #expect(store.actionErrorMessage == nil)
        #expect(!store.isAccessibilityTrusted)
        #expect(discovery.discoverCallCount == 0)
    }

    @Test("注入した短い周期で一覧を自動更新する")
    func refreshesPeriodicallyUsingInjectedInterval() async {
        let firstItem = makeItem(id: "first", title: "First")
        let secondItem = makeItem(id: "second", title: "Second")
        let permission = FakeAccessibilityPermissionService(isTrusted: true)
        let discovery = FakeMenuBarDiscoveryService(
            results: [
                (items: [firstItem], failures: []),
                (items: [secondItem], failures: [])
            ]
        )
        let store = MenuBarStore()
        let coordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: permission,
            discoveryService: discovery,
            refreshInterval: .milliseconds(20)
        )

        coordinator.start()
        defer { coordinator.stop() }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(1))
        while discovery.discoverCallCount < 2, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(discovery.discoverCallCount >= 2)
        #expect(store.items == [secondItem])
        #expect(store.lastUpdatedAt != nil)
    }

    @Test("表示変更前に開始した更新結果を破棄し変更後の再取得だけを反映する")
    func discardsRefreshResultSupersededByVisibilityMutation() async {
        let staleItem = makeItem(id: "stale", title: "Stale")
        let freshItem = makeItem(id: "fresh", title: "Fresh")
        let permission = FakeAccessibilityPermissionService(isTrusted: true)
        let discovery = FakeMenuBarDiscoveryService(
            results: [
                (items: [staleItem], failures: []),
                (items: [freshItem], failures: [])
            ],
            suspendsFirstDiscovery: true
        )
        let store = MenuBarStore()
        let coordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: permission,
            discoveryService: discovery
        )

        let staleRefresh = Task { @MainActor in
            await coordinator.refresh()
        }
        while discovery.discoverCallCount == 0 {
            await Task.yield()
        }

        coordinator.beginVisibilityMutation()
        discovery.resumeFirstDiscovery()
        await staleRefresh.value

        #expect(store.items.isEmpty)

        await coordinator.endVisibilityMutationAndRefresh()

        #expect(discovery.discoverCallCount == 2)
        #expect(store.items == [freshItem])
        #expect(!store.isRefreshing)
    }

    @Test("表示変更中の更新要求は保留して一覧を上書きしない")
    func defersRefreshWhileVisibilityMutationIsActive() async {
        let item = makeItem(id: "after-change", title: "After Change")
        let discovery = FakeMenuBarDiscoveryService(results: [(items: [item], failures: [])])
        let store = MenuBarStore()
        let coordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: FakeAccessibilityPermissionService(isTrusted: true),
            discoveryService: discovery
        )

        coordinator.beginVisibilityMutation()
        await coordinator.refresh()

        #expect(discovery.discoverCallCount == 0)
        #expect(store.items.isEmpty)

        await coordinator.endVisibilityMutationAndRefresh()

        #expect(discovery.discoverCallCount == 1)
        #expect(store.items == [item])
    }

    @Test("Undo対象はID変更後も一意な所有元fingerprintで解決する")
    func resolvesUndoItemByUniqueFingerprint() {
        let expected = makeItem(
            id: "new-id",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let unrelated = makeItem(
            id: "other",
            title: "Other",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let undo = MenuBarVisibilityUndo(
            itemID: "old-id",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu",
            itemTitle: "Menu",
            previousVisibility: .hidden,
            changedVisibility: .visible
        )

        #expect(MenuBarUndoItemResolver.resolve(undo, among: [unrelated, expected]) == expected)
    }

    @Test("Undo対象のfingerprintが曖昧なら別項目を選ばない")
    func rejectsAmbiguousUndoFingerprint() {
        let first = makeItem(
            id: "first",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let second = makeItem(
            id: "second",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let undo = MenuBarVisibilityUndo(
            itemID: "old-id",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu",
            itemTitle: "Menu",
            previousVisibility: .hidden,
            changedVisibility: .visible
        )

        #expect(MenuBarUndoItemResolver.resolve(undo, among: [first, second]) == nil)
    }

    @Test("境界はUIテスト外かつ権限許可・本体項目作成後だけ構成する")
    func gatesVisibilityInfrastructureActivation() {
        #expect(MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: false,
            isAccessibilityTrusted: true,
            hasMainStatusItem: true
        ))
        #expect(!MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: true,
            isAccessibilityTrusted: true,
            hasMainStatusItem: true
        ))
        #expect(!MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: false,
            isAccessibilityTrusted: false,
            hasMainStatusItem: true
        ))
        #expect(!MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: false,
            isAccessibilityTrusted: true,
            hasMainStatusItem: false
        ))
    }

    @Test("境界が同じ画面でMenuAll本体より左にある時だけ安全と判定する")
    func validatesBoundaryPlacementBeforeActivation() {
        let main = placementWindow(id: 1, x: 500, displayID: 7)
        let safeBoundary = placementWindow(id: 2, x: 400, displayID: 7)
        let reversedBoundary = placementWindow(id: 3, x: 600, displayID: 7)
        let otherDisplayBoundary = placementWindow(id: 4, x: 400, displayID: 8)
        let itemLeftOfBoundary = placementWindow(id: 5, x: 300, displayID: 7)
        let wideItemLeftOfBoundary = placementWindow(
            id: 6,
            x: 300,
            displayID: 7,
            width: 300
        )

        #expect(MenuAllBoundaryPlacementPolicy.isSafe(
            mainWindowID: 1,
            boundaryWindowID: 2,
            windows: [main, safeBoundary]
        ))
        #expect(!MenuAllBoundaryPlacementPolicy.isSafe(
            mainWindowID: 1,
            boundaryWindowID: 3,
            windows: [main, reversedBoundary]
        ))
        #expect(!MenuAllBoundaryPlacementPolicy.isSafe(
            mainWindowID: 1,
            boundaryWindowID: 4,
            windows: [main, otherDisplayBoundary]
        ))
        #expect(!MenuAllBoundaryPlacementPolicy.isSafe(
            mainWindowID: nil,
            boundaryWindowID: 2,
            windows: [main, safeBoundary]
        ))
        #expect(MenuAllBoundaryPlacementPolicy.isSafeForInitialConceal(
            mainWindowID: 1,
            boundaryWindowID: 2,
            windows: [main, safeBoundary]
        ))
        #expect(!MenuAllBoundaryPlacementPolicy.isSafeForInitialConceal(
            mainWindowID: 1,
            boundaryWindowID: 2,
            windows: [main, safeBoundary, itemLeftOfBoundary]
        ))
        #expect(!MenuAllBoundaryPlacementPolicy.isSafeForInitialConceal(
            mainWindowID: 1,
            boundaryWindowID: 2,
            windows: [main, safeBoundary, wideItemLeftOfBoundary]
        ))
    }

    @Test("rollback失敗時はID変更後の対象も位置不明かつ操作不可へ落とす")
    func failsClosedAfterRollbackFailure() {
        let original = makeItem(
            id: "old-id",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let refreshed = MenuBarItemSnapshot(
            id: "new-id",
            ownerPID: original.ownerPID,
            ownerName: original.ownerName,
            bundleIdentifier: original.bundleIdentifier,
            title: original.title,
            visibility: .visible
        )
        let store = MenuBarStore()
        store.items = [refreshed]
        store.visibilityAvailability[refreshed.id] = .available
        store.visibilityUndo = MenuBarVisibilityUndo(
            itemID: original.id,
            ownerPID: original.ownerPID,
            bundleIdentifier: original.bundleIdentifier,
            itemTitle: original.title,
            previousVisibility: .hidden,
            changedVisibility: .visible
        )

        MenuBarRollbackFailureState.apply(to: store, originalItem: original)

        #expect(store.items.first?.visibility == .unknown)
        #expect(
            store.visibilityAvailability[refreshed.id]
                == .unavailable(reason: MenuBarRollbackFailureState.unavailableReason)
        )
        #expect(store.visibilityUndo == nil)
        #expect(store.visibilityErrorMessage == MenuBarRollbackFailureState.errorMessage)
    }

    @Test("rollback失敗対象が曖昧でも全項目の再操作を止める")
    func quarantinesAllItemsWhenRollbackTargetIsAmbiguous() {
        let original = makeItem(
            id: "old-id",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let first = makeItem(
            id: "new-a",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let second = makeItem(
            id: "new-b",
            title: "Menu",
            ownerPID: 321,
            bundleIdentifier: "com.example.menu"
        )
        let unrelated = makeItem(id: "unrelated", title: "Other")
        let store = MenuBarStore()
        store.items = [first, second, unrelated]

        MenuBarRollbackFailureState.apply(to: store, originalItem: original)

        #expect(store.items.allSatisfy { $0.visibility == .hidden })
        #expect(store.visibilityAvailability.count == 3)
        #expect(store.visibilityAvailability.values.allSatisfy {
            $0 == .unavailable(reason: MenuBarRollbackFailureState.unavailableReason)
        })
    }
}

@MainActor
private final class FakeAccessibilityPermissionService: AccessibilityPermissionProviding {
    var isTrusted: Bool

    init(isTrusted: Bool) {
        self.isTrusted = isTrusted
    }

    func recheckPermission() -> Bool {
        isTrusted
    }

    func openSystemSettings() {}
}

@MainActor
private final class FakeMenuBarDiscoveryService: MenuBarDiscovering {
    private var results: [(items: [MenuBarItemSnapshot], failures: [MenuBarDiscoveryFailure])]
    private let suspendsFirstDiscovery: Bool
    private(set) var discoverCallCount = 0
    private var firstDiscoveryContinuation: CheckedContinuation<Void, Never>?

    init(
        results: [(items: [MenuBarItemSnapshot], failures: [MenuBarDiscoveryFailure])],
        suspendsFirstDiscovery: Bool = false
    ) {
        self.results = results
        self.suspendsFirstDiscovery = suspendsFirstDiscovery
    }

    func discover() async -> (items: [MenuBarItemSnapshot], failures: [MenuBarDiscoveryFailure]) {
        let resultIndex = min(discoverCallCount, max(results.count - 1, 0))
        discoverCallCount += 1
        if suspendsFirstDiscovery, discoverCallCount == 1 {
            await withCheckedContinuation { continuation in
                firstDiscoveryContinuation = continuation
            }
        }
        guard !results.isEmpty else {
            return (items: [], failures: [])
        }
        return results[resultIndex]
    }

    func performPrimaryAction(itemID: String) async throws {}

    func resumeFirstDiscovery() {
        firstDiscoveryContinuation?.resume()
        firstDiscoveryContinuation = nil
    }
}

private func makeItem(
    id: String,
    title: String,
    ownerPID: Int32 = 100,
    bundleIdentifier: String? = nil
) -> MenuBarItemSnapshot {
    MenuBarItemSnapshot(
        id: id,
        ownerPID: ownerPID,
        ownerName: "Test App",
        bundleIdentifier: bundleIdentifier,
        title: title,
        visibility: .hidden,
        actions: ["AXPress"]
    )
}

private func placementWindow(
    id: CGWindowID,
    x: CGFloat,
    displayID: CGDirectDisplayID,
    width: CGFloat = 30
) -> WindowServerMenuBarItemDescriptor {
    WindowServerMenuBarItemDescriptor(
        windowID: id,
        ownerPID: 100,
        ownerName: "MenuAll",
        ownerBundleIdentifier: "com.sinoda.MenuAll",
        windowName: nil,
        layer: 0,
        frame: CGRect(x: x, y: 0, width: width, height: 24),
        displayID: displayID
    )
}
