import AppKit

@MainActor
protocol MenuBarBoundaryStatusItem: AnyObject {
    var length: CGFloat { get set }
    var autosaveName: String? { get set }
    var windowID: CGWindowID? { get }
}

@MainActor
protocol MenuBarBoundaryStatusItemFactory {
    func makeStatusItem(length: CGFloat) -> any MenuBarBoundaryStatusItem
    func removeStatusItem(_ item: any MenuBarBoundaryStatusItem)
}

/// MenuAllが所有する境界項目。境界より左を非表示、右を表示として扱う。
@MainActor
final class MenuBarSectionController {
    static let autosaveName = "MenuAll.HiddenSectionBoundary"
    static let standardLength: CGFloat = 12
    static let concealedLength: CGFloat = 2_000

    private(set) var conflicts: [MenuBarManagerConflict]
    private(set) var isAvailable = false

    private let conflictDetector: any MenuBarManagerConflictDetecting
    private let statusItemFactory: any MenuBarBoundaryStatusItemFactory
    private let operationSafetyCheck: (CGWindowID?) -> Bool
    private let initialOperationSafetyCheck: (CGWindowID?) -> Bool
    private var boundaryItem: (any MenuBarBoundaryStatusItem)?
    private var isStopped = false
    private var activeOperationCount = 0
    private var shouldConcealAfterOperation = false

    init(
        conflictDetector: any MenuBarManagerConflictDetecting = MenuBarManagerConflictDetector(),
        statusItemFactory: any MenuBarBoundaryStatusItemFactory = AppKitMenuBarBoundaryStatusItemFactory(),
        operationSafetyCheck: @escaping (CGWindowID?) -> Bool = { _ in true },
        initialOperationSafetyCheck: @escaping (CGWindowID?) -> Bool = { _ in true }
    ) {
        self.conflictDetector = conflictDetector
        self.statusItemFactory = statusItemFactory
        self.operationSafetyCheck = operationSafetyCheck
        self.initialOperationSafetyCheck = initialOperationSafetyCheck
        conflicts = []
        refreshAvailability()
    }

    isolated deinit {
        restoreAndRemoveBoundary()
    }

    func setHiddenSectionExpanded(_ isExpanded: Bool) {
        guard isAvailable else { return }
        shouldConcealAfterOperation = !isExpanded
        boundaryItem?.length = isExpanded ? Self.standardLength : Self.concealedLength
    }

    /// 操作中だけ境界を縮め、画面外の項目を同じ画面内へ戻す。
    /// 競合が途中発生しても、操作終了までは境界を保持する。
    func beginVisibilityChange(to target: MenuBarVisibilityTarget) -> Bool {
        refreshAvailability()
        guard conflicts.isEmpty, isAvailable else { return false }
        guard operationSafetyCheck(boundaryItem?.windowID),
              shouldConcealAfterOperation || initialOperationSafetyCheck(boundaryItem?.windowID)
        else {
            restoreAndRemoveBoundary()
            return false
        }
        activeOperationCount += 1
        // 表示・非表示のどちらも、操作中だけ全項目を画面内へ戻す。
        // 完了後は境界を再び広げ、境界の左側だけを非表示に保つ。
        shouldConcealAfterOperation = true
        boundaryItem?.length = Self.standardLength
        return true
    }

    func endVisibilityChange() {
        guard activeOperationCount > 0 else { return }
        activeOperationCount -= 1
        guard activeOperationCount == 0 else { return }

        conflicts = conflictDetector.runningConflicts()
        if conflicts.isEmpty {
            guard operationSafetyCheck(boundaryItem?.windowID) else {
                restoreAndRemoveBoundary()
                return
            }
            boundaryItem?.length = shouldConcealAfterOperation
                ? Self.concealedLength
                : Self.standardLength
        } else {
            restoreAndRemoveBoundary()
        }
    }

    /// Ice等の途中起動・終了へ追従する。各変更直前にも呼び出す。
    func refreshAvailability() {
        guard !isStopped else { return }
        conflicts = conflictDetector.runningConflicts()

        if conflicts.isEmpty {
            guard boundaryItem == nil else {
                isAvailable = true
                return
            }
            let item = statusItemFactory.makeStatusItem(length: Self.standardLength)
            item.autosaveName = Self.autosaveName
            boundaryItem = item
            isAvailable = true
        } else {
            if activeOperationCount == 0 {
                restoreAndRemoveBoundary()
            }
        }
    }

    var boundaryWindowID: CGWindowID? {
        boundaryItem?.windowID
    }

    var isSafeForVisibilityChange: Bool {
        isAvailable
            && operationSafetyCheck(boundaryItem?.windowID)
            && (shouldConcealAfterOperation || initialOperationSafetyCheck(boundaryItem?.windowID))
    }

    func stop() {
        isStopped = true
        restoreAndRemoveBoundary()
    }

    private func restoreAndRemoveBoundary() {
        shouldConcealAfterOperation = false
        guard let boundaryItem else {
            isAvailable = false
            return
        }

        boundaryItem.length = Self.standardLength
        statusItemFactory.removeStatusItem(boundaryItem)
        self.boundaryItem = nil
        isAvailable = false
    }
}

@MainActor
private final class AppKitMenuBarBoundaryStatusItem: MenuBarBoundaryStatusItem {
    let statusItem: NSStatusItem

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        statusItem.button?.title = ""
        statusItem.button?.image = nil
    }

    var length: CGFloat {
        get { statusItem.length }
        set { statusItem.length = newValue }
    }

    var autosaveName: String? {
        get { statusItem.autosaveName }
        set { statusItem.autosaveName = newValue }
    }

    var windowID: CGWindowID? {
        guard let windowNumber = statusItem.button?.window?.windowNumber,
              windowNumber > 0
        else { return nil }
        return CGWindowID(windowNumber)
    }
}

@MainActor
private final class AppKitMenuBarBoundaryStatusItemFactory: MenuBarBoundaryStatusItemFactory {
    func makeStatusItem(length: CGFloat) -> any MenuBarBoundaryStatusItem {
        AppKitMenuBarBoundaryStatusItem(
            statusItem: NSStatusBar.system.statusItem(withLength: length)
        )
    }

    func removeStatusItem(_ item: any MenuBarBoundaryStatusItem) {
        guard let appKitItem = item as? AppKitMenuBarBoundaryStatusItem else { return }
        NSStatusBar.system.removeStatusItem(appKitItem.statusItem)
    }
}
