@preconcurrency import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MenuBarStore {
    var items: [MenuBarItemSnapshot] = []
    var failures: [MenuBarDiscoveryFailure] = []
    var isRefreshing = false
    var isAccessibilityTrusted = false
    var lastUpdatedAt: Date?
    var actionErrorMessage: String?
    var visibilityChangePhases: [String: VisibilityChangePhase] = [:]
    var visibilityAvailability: [String: VisibilityControlAvailability] = [:]
    var visibilityErrorMessage: String?
    var visibilityUndo: MenuBarVisibilityUndo?
    var lastOpenedItemName: String?
    var isPerformingOriginalItemAction = false

    var hiddenItems: [MenuBarItemSnapshot] {
        items.filter { $0.visibility == .hidden }
    }

    var visibleItems: [MenuBarItemSnapshot] {
        items.filter { $0.visibility == .visible }
    }

    var unknownItems: [MenuBarItemSnapshot] {
        items.filter { $0.visibility == .unknown }
    }
}

struct MenuBarVisibilityUndo: Equatable, Sendable {
    let itemID: String
    let ownerPID: Int32
    let bundleIdentifier: String?
    let itemTitle: String
    let previousVisibility: MenuBarItemVisibility
    let changedVisibility: MenuBarItemVisibility
}

enum MenuBarUndoItemResolver {
    static func resolve(
        _ undo: MenuBarVisibilityUndo,
        among items: [MenuBarItemSnapshot]
    ) -> MenuBarItemSnapshot? {
        if let exactMatch = items.first(where: { $0.id == undo.itemID }) {
            return exactMatch
        }

        let fingerprintMatches = items.filter {
            $0.ownerPID == undo.ownerPID
                && $0.bundleIdentifier == undo.bundleIdentifier
                && $0.title == undo.itemTitle
        }
        guard fingerprintMatches.count == 1 else { return nil }
        return fingerprintMatches[0]
    }
}

@MainActor
protocol MenuBarDiscovering: AnyObject {
    func discover() async -> (items: [MenuBarItemSnapshot], failures: [MenuBarDiscoveryFailure])
    func performPrimaryAction(itemID: String) async throws
}

@MainActor
final class MenuBarDiscoveryService: MenuBarDiscovering {
    private let client: AXMenuBarClient

    init(client: AXMenuBarClient = AXMenuBarClient()) {
        self.client = client
    }

    func discover() async -> (items: [MenuBarItemSnapshot], failures: [MenuBarDiscoveryFailure]) {
        let applications: [RunningApplicationDescriptor] = NSWorkspace.shared.runningApplications.compactMap { application -> RunningApplicationDescriptor? in
            guard
                !application.isTerminated,
                application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                let name = application.localizedName,
                application.bundleURL != nil
            else {
                return nil
            }
            guard let sanitizedName = AXDiscoveryLimits.sanitized(name),
                  !sanitizedName.isEmpty
            else { return nil }

            return RunningApplicationDescriptor(
                pid: application.processIdentifier,
                name: sanitizedName,
                bundleIdentifier: AXDiscoveryLimits.sanitized(application.bundleIdentifier),
                bundleURL: application.bundleURL
            )
        }

        let screenRegions = makeScreenRegions()
        let report = await client.discover(applications: applications)
        let snapshots = MenuBarItemDeduplicator.deduplicating(report.items.map { item in
            MenuBarItemSnapshot(
                id: item.id,
                ownerPID: item.ownerPID,
                ownerName: item.ownerName,
                bundleIdentifier: item.bundleIdentifier,
                bundleURL: item.bundleURL,
                title: item.title,
                hasExplicitName: item.hasExplicitName,
                detail: item.detail,
                role: item.role,
                visibility: MenuBarVisibilityClassifier.classify(
                    frame: item.frame,
                    isAXHidden: item.isAXHidden,
                    screens: screenRegions
                ),
                actions: item.actions,
                frame: item.frame
            )
        })

        return (
            snapshots.sorted(by: sortItems),
            report.failures.sorted { $0.ownerName.localizedStandardCompare($1.ownerName) == .orderedAscending }
        )
    }

    func performPrimaryAction(itemID: String) async throws {
        try await client.performPrimaryAction(itemID: itemID)
    }
}

private extension MenuBarDiscoveryService {
    func makeScreenRegions() -> [MenuBarScreenRegion] {
        guard let primaryScreen = NSScreen.screens.first else { return [] }
        let primaryTop = primaryScreen.frame.maxY

        return NSScreen.screens.map { screen in
            let menuBarHeight = MenuBarScreenGeometry.menuBarHeight(
                screenFrame: screen.frame,
                visibleFrame: screen.visibleFrame,
                statusBarThickness: NSStatusBar.system.thickness
            )
            let appKitMenuBarFrame = CGRect(
                x: screen.frame.minX,
                y: screen.frame.maxY - menuBarHeight,
                width: screen.frame.width,
                height: menuBarHeight
            )

            var obstructions: [CGRect] = []
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea,
               !leftArea.isEmpty,
               !rightArea.isEmpty,
               leftArea.maxX < rightArea.minX {
                let notch = CGRect(
                    x: leftArea.maxX,
                    y: appKitMenuBarFrame.minY,
                    width: rightArea.minX - leftArea.maxX,
                    height: appKitMenuBarFrame.height
                )
                obstructions.append(convertToAXCoordinates(notch, primaryTop: primaryTop))
            }

            return MenuBarScreenRegion(
                id: screen.localizedName,
                menuBarFrame: convertToAXCoordinates(appKitMenuBarFrame, primaryTop: primaryTop),
                obstructionFrames: obstructions
            )
        }
    }

    func convertToAXCoordinates(_ frame: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(
            x: frame.minX,
            y: primaryTop - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    func sortItems(_ lhs: MenuBarItemSnapshot, _ rhs: MenuBarItemSnapshot) -> Bool {
        if lhs.visibility != rhs.visibility {
            let priority: [MenuBarItemVisibility: Int] = [.hidden: 0, .visible: 1, .unknown: 2]
            return priority[lhs.visibility, default: 3] < priority[rhs.visibility, default: 3]
        }
        let ownerComparison = lhs.ownerName.localizedStandardCompare(rhs.ownerName)
        if ownerComparison != .orderedSame {
            return ownerComparison == .orderedAscending
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

enum MenuBarRefreshCadence {
    static func delay(interval: Duration, refreshDuration: Duration) -> Duration {
        max(interval - refreshDuration, .zero)
    }
}

@MainActor
final class MenuBarRefreshCoordinator: NSObject {
    let store: MenuBarStore

    private let permissionService: any AccessibilityPermissionProviding
    private let discoveryService: any MenuBarDiscovering
    private let refreshInterval: Duration
    private let onItemsUpdated: ([MenuBarItemSnapshot]) -> Void
    private let onAccessibilityTrustChanged: (Bool) -> Void
    private var periodicTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var refreshGeneration: UInt64 = 0
    private var visibilityMutationDepth = 0
    private var needsRefresh = false
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var isStopped = false

    var pendingRefreshCount: Int { refreshWaiters.count }

    init(
        store: MenuBarStore,
        permissionService: any AccessibilityPermissionProviding,
        discoveryService: any MenuBarDiscovering,
        refreshInterval: Duration = .seconds(2),
        onItemsUpdated: @escaping ([MenuBarItemSnapshot]) -> Void = { _ in },
        onAccessibilityTrustChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.store = store
        self.permissionService = permissionService
        self.discoveryService = discoveryService
        self.refreshInterval = refreshInterval
        self.onItemsUpdated = onItemsUpdated
        self.onAccessibilityTrustChanged = onAccessibilityTrustChanged
    }

    func start() {
        guard periodicTask == nil else { return }
        isStopped = false

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.refresh()
                    }
                }
            )
        }

        let interval = refreshInterval
        let clock = ContinuousClock()
        periodicTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let refreshStartedAt = clock.now
                await self?.refresh()
                guard self != nil, !Task.isCancelled else { return }

                let refreshDuration = refreshStartedAt.duration(to: clock.now)
                let delay = MenuBarRefreshCadence.delay(
                    interval: interval,
                    refreshDuration: refreshDuration
                )
                guard delay > .zero else { continue }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
            }
        }
    }

    func stop() {
        isStopped = true
        periodicTask?.cancel()
        periodicTask = nil
        refreshGeneration &+= 1
        needsRefresh = false
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        waiters.forEach { $0.resume() }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    /// 表示切り替え中に開始済みのAX取得結果が新しい配置を上書きしないよう、
    /// 現在世代を無効化して自動更新の反映を一時停止する。
    func beginVisibilityMutation() {
        visibilityMutationDepth += 1
        refreshGeneration &+= 1
        needsRefresh = true
    }

    /// 最後の表示切り替え終了後、新しい配置を必ず取り直してから戻る。
    func endVisibilityMutationAndRefresh() async {
        guard visibilityMutationDepth > 0 else { return }
        visibilityMutationDepth -= 1
        refreshGeneration &+= 1
        guard visibilityMutationDepth == 0 else { return }
        await refresh()
    }

    func refresh() async {
        guard !isStopped else { return }
        let trusted = permissionService.isTrusted
        updateAccessibilityTrust(trusted)
        guard trusted else {
            refreshGeneration &+= 1
            needsRefresh = false
            clearDiscoveredState()
            return
        }

        guard visibilityMutationDepth == 0 else {
            needsRefresh = true
            return
        }

        if store.isRefreshing {
            needsRefresh = true
            await withCheckedContinuation { continuation in
                refreshWaiters.append(continuation)
            }
            return
        }

        store.isRefreshing = true
        defer {
            store.isRefreshing = false
            let waiters = refreshWaiters
            refreshWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        repeat {
            needsRefresh = false
            let generation = refreshGeneration
            let result = await discoveryService.discover()
            guard !isStopped else { return }
            let remainsTrusted = permissionService.isTrusted
            updateAccessibilityTrust(remainsTrusted)

            guard remainsTrusted else {
                refreshGeneration &+= 1
                clearDiscoveredState()
                return
            }

            guard visibilityMutationDepth == 0,
                  generation == refreshGeneration
            else {
                needsRefresh = true
                if visibilityMutationDepth > 0 { return }
                continue
            }

            store.items = result.items
            onItemsUpdated(result.items)
            store.failures = result.failures
            store.lastUpdatedAt = .now
            AppLogger.discovery.info("メニューバー項目を \(result.items.count, privacy: .public) 件取得")
        } while needsRefresh && visibilityMutationDepth == 0
    }

    func requestPermission() {
        permissionService.openSystemSettings()
        updateAccessibilityTrust(permissionService.isTrusted)
    }

    func recheckPermissionAndRefresh() async {
        updateAccessibilityTrust(permissionService.recheckPermission())
        await refresh()
    }

    func performPrimaryAction(itemID: String) async {
        guard permissionService.isTrusted else {
            updateAccessibilityTrust(false)
            clearDiscoveredState()
            return
        }

        do {
            try await discoveryService.performPrimaryAction(itemID: itemID)
            store.actionErrorMessage = nil
        } catch {
            store.actionErrorMessage = error.localizedDescription
            AppLogger.action.error("項目操作に失敗: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearDiscoveredState() {
        store.items = []
        onItemsUpdated([])
        store.failures = []
        store.lastUpdatedAt = nil
        store.actionErrorMessage = nil
    }

    private func updateAccessibilityTrust(_ trusted: Bool) {
        guard store.isAccessibilityTrusted != trusted else { return }
        store.isAccessibilityTrusted = trusted
        onAccessibilityTrustChanged(trusted)
    }
}
