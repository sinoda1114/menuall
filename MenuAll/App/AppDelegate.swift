@preconcurrency import AppKit
import SwiftUI

enum MenuAllStatusItemIdentity {
    static let mainAutosaveName = "MenuAll.MainStatusItem"
    static let boundaryActivationDelay: Duration = .milliseconds(100)
}

enum MenuAllVisibilityInfrastructurePolicy {
    static func shouldActivate(
        isUITesting: Bool,
        isAccessibilityTrusted: Bool,
        hasMainStatusItem: Bool
    ) -> Bool {
        !isUITesting && isAccessibilityTrusted && hasMainStatusItem
    }
}

enum MenuAllBoundaryPlacementPolicy {
    static func isSafe(
        mainWindowID: CGWindowID?,
        boundaryWindowID: CGWindowID?,
        windows: [WindowServerMenuBarItemDescriptor]
    ) -> Bool {
        guard let mainWindowID,
              let boundaryWindowID,
              let main = windows.first(where: { $0.windowID == mainWindowID }),
              let boundary = windows.first(where: { $0.windowID == boundaryWindowID }),
              let mainDisplayID = main.displayID,
              let boundaryDisplayID = boundary.displayID,
              mainDisplayID == boundaryDisplayID
        else { return false }

        // 隠す対象は境界より左側。MenuAll本体が必ず表示側（右側）にある時だけ有効化する。
        return boundary.frame.midX < main.frame.midX
    }

    static func isSafeForInitialConceal(
        mainWindowID: CGWindowID?,
        boundaryWindowID: CGWindowID?,
        windows: [WindowServerMenuBarItemDescriptor]
    ) -> Bool {
        guard isSafe(
            mainWindowID: mainWindowID,
            boundaryWindowID: boundaryWindowID,
            windows: windows
        ),
        let mainWindowID,
        let boundaryWindowID,
        let main = windows.first(where: { $0.windowID == mainWindowID }),
        let boundary = windows.first(where: { $0.windowID == boundaryWindowID }),
        let displayID = main.displayID
        else { return false }

        let otherStatusItems = windows.filter {
            $0.windowID != mainWindowID
                && $0.windowID != boundaryWindowID
                && $0.displayID == displayID
                && $0.frame.width > 0
                && $0.frame.height > 0
                && $0.frame.origin.x.isFinite
                && $0.frame.origin.y.isFinite
                && $0.frame.width.isFinite
                && $0.frame.height.isFinite
        }
        return otherStatusItems.allSatisfy { boundary.frame.midX < $0.frame.minX }
    }
}

@MainActor
enum MenuBarRollbackFailureState {
    static let unavailableReason = "元の状態を確認できません。再読み込みしてください。"
    static let errorMessage = "元の状態へ戻せませんでした。再読み込みして実際の状態を確認してください。"

    static func apply(
        to store: MenuBarStore,
        originalItem: MenuBarItemSnapshot
    ) {
        let resolvedItem = store.items.first(where: { $0.id == originalItem.id }) ?? {
            let candidates = store.items.filter {
                $0.ownerPID == originalItem.ownerPID
                    && $0.bundleIdentifier == originalItem.bundleIdentifier
                    && $0.title == originalItem.title
            }
            return candidates.count == 1 ? candidates[0] : nil
        }()

        if let resolvedItem,
           let index = store.items.firstIndex(where: { $0.id == resolvedItem.id }) {
            store.items[index] = resolvedItem.replacingVisibility(with: .unknown)
            store.visibilityAvailability[resolvedItem.id] = .unavailable(reason: unavailableReason)
        }
        store.visibilityAvailability = Dictionary(
            uniqueKeysWithValues: store.items.map {
                ($0.id, .unavailable(reason: unavailableReason))
            }
        )
        store.visibilityUndo = nil
        store.visibilityErrorMessage = errorMessage
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MenuBarStore()
    private let permissionService = AccessibilityPermissionService()
    private let discoveryService = MenuBarDiscoveryService()

    private var refreshCoordinator: MenuBarRefreshCoordinator!
    private var visibilityChangeCoordinator: MenuBarVisibilityChangeCoordinator!
    private var menuBarSectionController: MenuBarSectionController?
    private var liveVisibilityResolver: LiveMenuBarVisibilityEndpointResolver?
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindowController: SettingsWindowController!
    private var onboardingWindow: NSWindow?
    private var uiTestPopoverAnchorWindow: NSWindow?
    private var visibilityInfrastructureActivationTask: Task<Void, Never>?
    private var visibilityInfrastructureRequiresManualReset = false
    private var visibilityOperationGate = MenuBarVisibilityOperationGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)

        store.isAccessibilityTrusted = permissionService.isTrusted
        configureVisibilityFixtureIfNeeded()
        // 非表示境界より先に本体項目を登録し、MenuAll自身が境界の左へ
        // 押し出される初回配置を避ける。
        configureStatusItem()
        visibilityChangeCoordinator = MenuBarVisibilityChangeCoordinator(
            changer: makeVisibilityChanger()
        )
        refreshCoordinator = MenuBarRefreshCoordinator(
            store: store,
            permissionService: permissionService,
            discoveryService: discoveryService,
            onItemsUpdated: { [weak self] items in
                self?.updateVisibilityInfrastructure(items: items)
            },
            onAccessibilityTrustChanged: { [weak self] trusted in
                self?.handleAccessibilityTrustChange(trusted)
            }
        )

        configurePopover()
        settingsWindowController = SettingsWindowController(
            store: store,
            permissionService: permissionService
        )
        if LaunchEnvironment.uiTestRoute == .popover {
            presentPopoverForUITesting()
            if LaunchEnvironment.shouldRunLivePopoverDiscovery {
                refreshCoordinator.start()
            }
        } else {
            refreshCoordinator.start()
        }

        if LaunchEnvironment.uiTestRoute == .onboarding ||
            (LaunchEnvironment.uiTestRoute == nil && !store.isAccessibilityTrusted) {
            presentOnboardingWindow()
        }

        AppLogger.lifecycle.info("MenuAllを起動しました")
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilityInfrastructureActivationTask?.cancel()
        refreshCoordinator.stop()
        menuBarSectionController?.stop()
    }
}

private extension AppDelegate {
    func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = MenuAllStatusItemIdentity.mainAutosaveName
        guard let button = statusItem.button else { return }
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(
            systemSymbolName: "rectangle.3.group.bubble.left",
            accessibilityDescription: "MenuAll"
        )
        image?.isTemplate = true
        image?.size = NSSize(width: 18, height: 18)
        button.image = image
        button.toolTip = "MenuAll — メニューバー項目を表示"
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.setAccessibilityIdentifier("menuall.status-item")
    }

    func configurePopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 380, height: 540)
        popover.contentViewController = NSHostingController(rootView: makeRootView())
    }

    func presentPopoverForUITesting() {
        guard LaunchEnvironment.isUITesting, let screen = NSScreen.main else { return }

        // 実際のAX列挙に依存せず、空状態のポップアップを決定的に検証する。
        // メニューバー項目が画面外に押し出されていても、実物のNSPopoverを
        // 画面内に表示できるよう、透明なテスト専用アンカーを使用する。
        let anchorRect = NSRect(
            x: screen.visibleFrame.midX - 1,
            y: screen.visibleFrame.maxY - 2,
            width: 2,
            height: 2
        )
        let anchorWindow = NSWindow(
            contentRect: anchorRect,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        anchorWindow.isOpaque = false
        anchorWindow.backgroundColor = .clear
        anchorWindow.level = .statusBar
        anchorWindow.ignoresMouseEvents = true
        anchorWindow.isReleasedWhenClosed = false
        uiTestPopoverAnchorWindow = anchorWindow

        NSApplication.shared.activate(ignoringOtherApps: true)
        anchorWindow.orderFront(nil)
        guard let anchorView = anchorWindow.contentView else { return }
        popover.behavior = .applicationDefined
        popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func makeRootView(showsPermissionCompletion: Bool = false) -> MenuAllPopoverView {
        MenuAllPopoverView(
            store: store,
            onRefresh: { [weak self] in
                guard let self else { return }
                guard LaunchEnvironment.uiTestRoute != .popover ||
                    LaunchEnvironment.shouldRunLivePopoverDiscovery else { return }
                Task { @MainActor in
                    self.visibilityInfrastructureRequiresManualReset = false
                    if self.store.isAccessibilityTrusted {
                        await self.refreshCoordinator.refresh()
                    } else {
                        await self.refreshCoordinator.recheckPermissionAndRefresh()
                    }
                }
            },
            onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                self?.settingsWindowController.present()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            },
            onRequestPermission: { [weak self] in
                self?.refreshCoordinator.requestPermission()
            },
            onOpenItem: { [weak self] itemID in
                self?.openOriginalItem(itemID: itemID)
            },
            onChangeVisibility: { [weak self] itemID, shouldShow in
                Task { @MainActor in
                    self?.requestVisibilityChange(itemID: itemID, shouldShow: shouldShow)
                }
            },
            onUndoVisibilityChange: { [weak self] in
                self?.undoVisibilityChange()
            },
            onStart: { [weak self] in
                self?.onboardingWindow?.orderOut(nil)
            },
            showsPermissionCompletion: showsPermissionCompletion
        )
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
            return
        }

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        Task { @MainActor [weak self] in
            await self?.refreshCoordinator.refresh()
        }
    }

    func openOriginalItem(itemID: String) {
        guard store.visibilityChangePhases.isEmpty,
              !visibilityOperationGate.isActive,
              !store.isPerformingOriginalItemAction
        else { return }
        store.isPerformingOriginalItemAction = true
        if LaunchEnvironment.visibilityChangeScenario != nil,
           let item = store.items.first(where: { $0.id == itemID }) {
            store.lastOpenedItemName = item.title
            store.isPerformingOriginalItemAction = false
            return
        }
        popover.performClose(nil)
        onboardingWindow?.orderOut(nil)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.store.isPerformingOriginalItemAction = false }
            try? await Task.sleep(for: .milliseconds(80))
            guard self.store.visibilityChangePhases.isEmpty,
                  !self.visibilityOperationGate.isActive
            else { return }
            await self.refreshCoordinator.performPrimaryAction(itemID: itemID)
            self.applyUITestAccessibilityLossAfterItemActionIfNeeded()
            guard self.store.actionErrorMessage == nil,
                  self.store.isAccessibilityTrusted else {
                self.presentPopoverAfterFailedAction()
                return
            }
        }
    }

    func requestVisibilityChange(itemID: String, shouldShow: Bool) {
        guard let item = store.items.first(where: { $0.id == itemID }) else { return }
        let target: MenuBarVisibilityTarget = shouldShow ? .shown : .hidden
        guard let operationID = beginVisibilityOperation(item: item, target: target) else { return }
        Task { @MainActor [weak self] in
            await self?.performVisibilityChange(
                item: item,
                target: target,
                recordsUndo: true,
                operationID: operationID
            )
        }
    }

    func undoVisibilityChange() {
        guard let undo = store.visibilityUndo else { return }
        guard !visibilityOperationGate.isActive, !visibilityChangeCoordinator.isChanging else {
            store.visibilityErrorMessage = "表示変更の完了後に、もう一度元に戻してください。"
            return
        }
        guard let item = MenuBarUndoItemResolver.resolve(undo, among: store.items) else {
            store.visibilityUndo = nil
            store.visibilityErrorMessage = "元に戻す対象を一意に確認できません。再読み込みしてください。"
            return
        }
        let target: MenuBarVisibilityTarget = undo.previousVisibility == .visible ? .shown : .hidden
        guard let operationID = beginVisibilityOperation(item: item, target: target) else { return }
        Task { @MainActor [weak self] in
            await self?.performVisibilityChange(
                item: item,
                target: target,
                recordsUndo: false,
                operationID: operationID
            )
        }
    }

    func beginVisibilityOperation(
        item: MenuBarItemSnapshot,
        target: MenuBarVisibilityTarget
    ) -> UUID? {
        guard store.visibilityChangePhases.isEmpty,
              !store.isPerformingOriginalItemAction,
              !visibilityChangeCoordinator.isChanging
        else { return nil }

        guard let operationID = visibilityOperationGate.begin() else { return nil }
        store.visibilityUndo = nil
        store.visibilityErrorMessage = nil
        store.visibilityChangePhases[item.id] = .changing(target)
        return operationID
    }

    func performVisibilityChange(
        item: MenuBarItemSnapshot,
        target: MenuBarVisibilityTarget,
        recordsUndo: Bool,
        operationID: UUID
    ) async {
        guard visibilityOperationGate.owns(operationID) else { return }
        let coordinatesRefreshes = !LaunchEnvironment.isUITesting
        if coordinatesRefreshes {
            refreshCoordinator.beginVisibilityMutation()
        }
        let outcome = await visibilityChangeCoordinator.change(item: item, to: target)
        guard visibilityOperationGate.owns(operationID) else {
            if coordinatesRefreshes {
                await refreshCoordinator.endVisibilityMutationAndRefresh()
            }
            return
        }

        switch outcome {
        case let .changed(changedTarget):
            let newVisibility: MenuBarItemVisibility = changedTarget == .shown ? .visible : .hidden
            replaceVisibility(itemID: item.id, with: newVisibility)
            if recordsUndo {
                store.visibilityUndo = MenuBarVisibilityUndo(
                    itemID: item.id,
                    ownerPID: item.ownerPID,
                    bundleIdentifier: item.bundleIdentifier,
                    itemTitle: item.title,
                    previousVisibility: item.visibility,
                    changedVisibility: newVisibility
                )
            }
        case .unchanged:
            break
        case let .unavailable(reason):
            store.visibilityAvailability[item.id] = .unavailable(reason: reason)
            store.visibilityErrorMessage = reason
        case let .failed(message), let .rolledBack(message):
            store.visibilityErrorMessage = message
        case .rollbackFailed:
            visibilityInfrastructureRequiresManualReset = true
            deactivateVisibilityInfrastructure()
            markVisibilityAsUnknownAfterRollbackFailure(item)
        case .busy:
            store.visibilityErrorMessage = "別の項目を変更中です。完了後にもう一度お試しください。"
        }

        if coordinatesRefreshes {
            await refreshCoordinator.endVisibilityMutationAndRefresh()
        }
        if case .rollbackFailed = outcome {
            // 自動再取得が状態を読めても、rollback失敗直後は利用者が明示的に
            // 再確認するまで同じ対象へイベントを重ねない。
            markVisibilityAsUnknownAfterRollbackFailure(item)
        }
        store.visibilityChangePhases[item.id] = nil
        _ = visibilityOperationGate.finish(operationID)
    }

    func replaceVisibility(itemID: String, with visibility: MenuBarItemVisibility) {
        guard let index = store.items.firstIndex(where: { $0.id == itemID }) else { return }
        store.items[index] = store.items[index].replacingVisibility(with: visibility)
    }

    func markVisibilityAsUnknownAfterRollbackFailure(_ originalItem: MenuBarItemSnapshot) {
        MenuBarRollbackFailureState.apply(to: store, originalItem: originalItem)
    }

    func configureVisibilityFixtureIfNeeded() {
        guard LaunchEnvironment.shouldUseVisibilityFixture else { return }
        store.items = [
            MenuBarItemSnapshot(
                id: "ui-test-hidden",
                ownerPID: 0,
                ownerName: "Hidden Fixture",
                title: "隠れているテスト項目",
                visibility: .hidden
            ),
            MenuBarItemSnapshot(
                id: "ui-test-visible",
                ownerPID: 0,
                ownerName: "Visible Fixture",
                title: "表示中のテスト項目",
                visibility: .visible
            ),
            MenuBarItemSnapshot(
                id: "ui-test-position-unknown",
                ownerPID: 0,
                ownerName: "Unknown Fixture",
                title: "位置不明のテスト項目",
                visibility: .unknown
            ),
            MenuBarItemSnapshot(
                id: "ui-test-unsupported",
                ownerPID: 0,
                ownerName: "Unsupported Fixture",
                title: "切り替え非対応のテスト項目",
                visibility: .visible
            )
        ]
        store.visibilityAvailability = [
            "ui-test-hidden": .available,
            "ui-test-visible": .available,
            "ui-test-position-unknown": .unavailable(reason: "現在の表示状態を確認できません。"),
            "ui-test-unsupported": .unavailable(reason: "この項目は表示切り替えに対応していません。")
        ]
    }

    func scheduleVisibilityInfrastructureActivationIfNeeded() {
        guard MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: LaunchEnvironment.isUITesting,
            isAccessibilityTrusted: store.isAccessibilityTrusted,
            hasMainStatusItem: statusItem != nil
        ), menuBarSectionController == nil,
           visibilityInfrastructureActivationTask == nil,
           !visibilityInfrastructureRequiresManualReset
        else { return }

        visibilityInfrastructureActivationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: MenuAllStatusItemIdentity.boundaryActivationDelay)
            guard !Task.isCancelled, let self else { return }
            await self.activateVisibilityInfrastructureIfPossible()
            self.visibilityInfrastructureActivationTask = nil
        }
    }

    func activateVisibilityInfrastructureIfPossible() async {
        guard MenuAllVisibilityInfrastructurePolicy.shouldActivate(
            isUITesting: LaunchEnvironment.isUITesting,
            isAccessibilityTrusted: store.isAccessibilityTrusted,
            hasMainStatusItem: statusItem != nil
        ), menuBarSectionController == nil
        else { return }

        let provider = WindowServerMenuBarItemDescriptorProvider()
        let sectionController = MenuBarSectionController(
            operationSafetyCheck: { [weak self] boundaryWindowID in
                guard let self else { return false }
                guard self.permissionService.isTrusted else { return false }
                return MenuAllBoundaryPlacementPolicy.isSafe(
                    mainWindowID: self.statusItem.button?.window.map {
                        CGWindowID($0.windowNumber)
                    },
                    boundaryWindowID: boundaryWindowID,
                    windows: provider.descriptors()
                )
            },
            initialOperationSafetyCheck: { [weak self] boundaryWindowID in
                guard let self, self.permissionService.isTrusted else { return false }
                return MenuAllBoundaryPlacementPolicy.isSafeForInitialConceal(
                    mainWindowID: self.statusItem.button?.window.map {
                        CGWindowID($0.windowNumber)
                    },
                    boundaryWindowID: boundaryWindowID,
                    windows: provider.descriptors()
                )
            }
        )
        let resolver = LiveMenuBarVisibilityEndpointResolver(
            sectionController: sectionController
        )

        sectionController.refreshAvailability()
        if let conflict = sectionController.conflicts.first {
            sectionController.stop()
            let reason = "\(conflict.displayName)が起動中のため、同時に表示を変更できません。"
            store.visibilityAvailability = Dictionary(
                uniqueKeysWithValues: store.items.map { ($0.id, .unavailable(reason: reason)) }
            )
            return
        }

        var placementIsSafe = false
        for _ in 0..<5 {
            try? await Task.sleep(for: MenuAllStatusItemIdentity.boundaryActivationDelay)
            guard !Task.isCancelled, store.isAccessibilityTrusted else {
                sectionController.stop()
                return
            }
            placementIsSafe = MenuAllBoundaryPlacementPolicy.isSafeForInitialConceal(
                mainWindowID: statusItem.button?.window.map { CGWindowID($0.windowNumber) },
                boundaryWindowID: sectionController.boundaryWindowID,
                windows: provider.descriptors()
            )
            if placementIsSafe { break }
        }
        guard placementIsSafe else {
            sectionController.stop()
            let reason = "MenuAll本体を安全な表示側に確認できないため、表示切り替えを無効にしました。"
            store.visibilityAvailability = Dictionary(
                uniqueKeysWithValues: store.items.map {
                    ($0.id, .unavailable(reason: reason))
                }
            )
            return
        }

        menuBarSectionController = sectionController
        liveVisibilityResolver = resolver
        resolver.update(items: store.items)
        store.visibilityAvailability = resolver.availabilitySnapshot()
        visibilityChangeCoordinator = MenuBarVisibilityChangeCoordinator(
            changer: CGEventMenuBarVisibilityChanger(resolver: resolver)
        )
    }

    func deactivateVisibilityInfrastructure() {
        visibilityInfrastructureActivationTask?.cancel()
        visibilityInfrastructureActivationTask = nil
        menuBarSectionController?.stop()
        menuBarSectionController = nil
        liveVisibilityResolver = nil
        guard !LaunchEnvironment.isUITesting else { return }
        visibilityChangeCoordinator = MenuBarVisibilityChangeCoordinator(
            changer: UnavailableMenuBarVisibilityChanger()
        )
    }

    func handleAccessibilityTrustChange(_ trusted: Bool) {
        if trusted {
            // 許可直後のAX取得が完了し、onItemsUpdatedで新しい一覧を受け取ってから
            // 境界を遅延作成する。取得途中の座標系を変えない。
            if !store.items.isEmpty {
                scheduleVisibilityInfrastructureActivationIfNeeded()
            }
        } else {
            deactivateVisibilityInfrastructure()
        }
    }

    func updateVisibilityInfrastructure(items: [MenuBarItemSnapshot]) {
        if visibilityInfrastructureRequiresManualReset {
            store.visibilityAvailability = Dictionary(
                uniqueKeysWithValues: items.map {
                    ($0.id, .unavailable(reason: MenuBarRollbackFailureState.unavailableReason))
                }
            )
            return
        }
        guard let liveVisibilityResolver else {
            scheduleVisibilityInfrastructureActivationIfNeeded()
            return
        }
        liveVisibilityResolver.update(items: items)
        store.visibilityAvailability = liveVisibilityResolver.availabilitySnapshot()
    }

    func makeVisibilityChanger() -> any MenuBarVisibilityChanging {
#if DEBUG
        if let scenario = LaunchEnvironment.visibilityChangeScenario {
            return UITestMenuBarVisibilityChanger(
                scenario: scenario,
                initialItems: store.items
            )
        }
#endif
        if let liveVisibilityResolver {
            return CGEventMenuBarVisibilityChanger(resolver: liveVisibilityResolver)
        }
        return UnavailableMenuBarVisibilityChanger()
    }

    func applyUITestAccessibilityLossAfterItemActionIfNeeded() {
#if DEBUG
        guard LaunchEnvironment.shouldRevokeAccessibilityOnItemAction else { return }
        store.isAccessibilityTrusted = false
        store.actionErrorMessage = nil
#endif
    }

    func presentPopoverAfterFailedAction() {
        if LaunchEnvironment.uiTestRoute == .popover,
           let anchorWindow = uiTestPopoverAnchorWindow,
           let anchorView = anchorWindow.contentView {
            NSApplication.shared.activate(ignoringOtherApps: true)
            anchorWindow.orderFront(nil)
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover.contentViewController?.view.window?.makeKey()
    }

    func presentOnboardingWindow() {
        let hostingController = NSHostingController(rootView: makeRootView(showsPermissionCompletion: true))
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MenuAll"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 470))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
private final class UnavailableMenuBarVisibilityChanger: MenuBarVisibilityChanging {
    func availability(for itemID: String) async -> VisibilityControlAvailability {
        .unavailable(reason: "この項目は表示切り替えに対応していません。")
    }

    func beginChange(
        itemID: String,
        from: MenuBarItemVisibility,
        to target: MenuBarVisibilityTarget
    ) async throws -> VisibilityChangeReceipt {
        throw VisibilityChangeCompositionError.unavailable
    }

    func observedVisibility(itemID: String) async throws -> MenuBarItemVisibility { .unknown }
    func rollback(operationID: UUID) async throws {}
}

private enum VisibilityChangeCompositionError: LocalizedError {
    case unavailable
    case simulatedFailure

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "この項目は表示切り替えに対応していません。"
        case .simulatedFailure:
            "表示を変更できませんでした。"
        }
    }
}

#if DEBUG
@MainActor
private final class UITestMenuBarVisibilityChanger: MenuBarVisibilityChanging {
    private let scenario: LaunchEnvironment.VisibilityChangeScenario
    private var visibilities: [String: MenuBarItemVisibility]
    private var pendingTargets: [String: MenuBarVisibilityTarget] = [:]
    private var rollbackVisibilities: [UUID: (String, MenuBarItemVisibility)] = [:]

    init(
        scenario: LaunchEnvironment.VisibilityChangeScenario,
        initialItems: [MenuBarItemSnapshot]
    ) {
        self.scenario = scenario
        visibilities = Dictionary(uniqueKeysWithValues: initialItems.map { ($0.id, $0.visibility) })
    }

    func availability(for itemID: String) async -> VisibilityControlAvailability {
        if itemID == "ui-test-unsupported" {
            return .unavailable(reason: "この項目は表示切り替えに対応していません。")
        }
        return .available
    }

    func beginChange(
        itemID: String,
        from: MenuBarItemVisibility,
        to target: MenuBarVisibilityTarget
    ) async throws -> VisibilityChangeReceipt {
        if scenario == .failure {
            throw VisibilityChangeCompositionError.simulatedFailure
        }
        if scenario == .delayed {
            try await Task.sleep(for: .milliseconds(450))
        }
        let operationID = UUID()
        rollbackVisibilities[operationID] = (itemID, from)
        pendingTargets[itemID] = target
        visibilities[itemID] = target == .shown ? .visible : .hidden
        return VisibilityChangeReceipt(
            operationID: operationID,
            itemID: itemID,
            from: from,
            target: target
        )
    }

    func observedVisibility(itemID: String) async throws -> MenuBarItemVisibility {
        visibilities[itemID] ?? .unknown
    }

    func rollback(operationID: UUID) async throws {
        guard let rollback = rollbackVisibilities[operationID] else { return }
        visibilities[rollback.0] = rollback.1
    }
}
#endif
