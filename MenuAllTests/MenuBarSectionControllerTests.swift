import AppKit
import Testing
@testable import MenuAll

@Suite("MenuBarSectionController")
@MainActor
struct MenuBarSectionControllerTests {
    @Test("競合がなければ安定した名前の標準幅境界を作る")
    func createsStableBoundary() {
        let factory = FakeBoundaryStatusItemFactory()
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory
        )

        #expect(controller.isAvailable)
        #expect(factory.createdItems.count == 1)
        #expect(factory.createdItems[0].autosaveName == MenuBarSectionController.autosaveName)
        #expect(factory.createdItems[0].length == MenuBarSectionController.standardLength)
    }

    @Test("非表示領域を一時表示して再び隠せる")
    func revealsAndConcealsHiddenSection() {
        let factory = FakeBoundaryStatusItemFactory()
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory
        )

        controller.setHiddenSectionExpanded(true)
        #expect(factory.createdItems[0].length == MenuBarSectionController.standardLength)

        controller.setHiddenSectionExpanded(false)
        #expect(factory.createdItems[0].length == MenuBarSectionController.concealedLength)
    }

    @Test("競合アプリの稼働中は境界を作らない")
    func skipsBoundaryWhenManagerConflicts() {
        let factory = FakeBoundaryStatusItemFactory()
        let conflict = MenuBarManagerConflict(
            bundleIdentifier: "com.jordanbaird.Ice",
            displayName: "Ice"
        )
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: [conflict]),
            statusItemFactory: factory
        )

        #expect(!controller.isAvailable)
        #expect(controller.conflicts == [conflict])
        #expect(factory.createdItems.isEmpty)
    }

    @Test("停止時は標準幅へ戻してから境界を除去する")
    func restoresAndRemovesBoundaryOnStop() {
        let factory = FakeBoundaryStatusItemFactory()
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory
        )
        controller.setHiddenSectionExpanded(false)

        controller.stop()

        #expect(factory.removedItems.count == 1)
        #expect(factory.lengthsAtRemoval == [MenuBarSectionController.standardLength])
        #expect(!controller.isAvailable)
    }

    @Test("競合アプリの途中起動と終了へ追従する")
    func reconcilesRuntimeConflicts() {
        let factory = FakeBoundaryStatusItemFactory()
        let detector = FakeConflictDetector(conflicts: [])
        let controller = MenuBarSectionController(
            conflictDetector: detector,
            statusItemFactory: factory
        )
        #expect(controller.isAvailable)

        detector.conflicts = [
            MenuBarManagerConflict(bundleIdentifier: "com.jordanbaird.Ice", displayName: "Ice")
        ]
        controller.refreshAvailability()
        #expect(!controller.isAvailable)
        #expect(factory.removedItems.count == 1)

        detector.conflicts = []
        controller.refreshAvailability()
        #expect(controller.isAvailable)
        #expect(factory.createdItems.count == 2)
    }

    @Test("操作中に競合が発生しても終了までは境界を保持する")
    func retainsBoundaryUntilActiveOperationEnds() {
        let factory = FakeBoundaryStatusItemFactory()
        let detector = FakeConflictDetector(conflicts: [])
        let controller = MenuBarSectionController(
            conflictDetector: detector,
            statusItemFactory: factory
        )

        #expect(controller.beginVisibilityChange(to: .hidden))
        detector.conflicts = [
            MenuBarManagerConflict(bundleIdentifier: "com.jordanbaird.Ice", displayName: "Ice")
        ]
        controller.refreshAvailability()

        #expect(controller.isAvailable)
        #expect(factory.removedItems.isEmpty)

        controller.endVisibilityChange()

        #expect(!controller.isAvailable)
        #expect(factory.removedItems.count == 1)
        #expect(factory.lengthsAtRemoval == [MenuBarSectionController.standardLength])
    }

    @Test("明示的な変更後だけ境界を再び隠す")
    func concealsBoundaryAfterExplicitChange() {
        let factory = FakeBoundaryStatusItemFactory()
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory
        )

        #expect(factory.createdItems[0].length == MenuBarSectionController.standardLength)
        #expect(controller.beginVisibilityChange(to: .shown))
        #expect(factory.createdItems[0].length == MenuBarSectionController.standardLength)

        controller.endVisibilityChange()

        #expect(factory.createdItems[0].length == MenuBarSectionController.concealedLength)
    }

    @Test("再作成後の境界配置が危険なら操作前に標準幅で除去する")
    func rejectsUnsafeBoundaryPlacementBeforeEveryOperation() {
        let factory = FakeBoundaryStatusItemFactory()
        var isPlacementSafe = true
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory,
            operationSafetyCheck: { _ in isPlacementSafe }
        )

        #expect(controller.beginVisibilityChange(to: .hidden))
        controller.endVisibilityChange()
        isPlacementSafe = false

        #expect(!controller.beginVisibilityChange(to: .shown))
        #expect(!controller.isAvailable)
        #expect(factory.removedItems.count == 1)
        #expect(factory.lengthsAtRemoval == [MenuBarSectionController.standardLength])
    }

    @Test("初回境界の左に未選択項目があれば非表示化を開始しない")
    func rejectsUnsafeInitialConcealment() {
        let factory = FakeBoundaryStatusItemFactory()
        let controller = MenuBarSectionController(
            conflictDetector: FakeConflictDetector(conflicts: []),
            statusItemFactory: factory,
            operationSafetyCheck: { _ in true },
            initialOperationSafetyCheck: { _ in false }
        )

        #expect(!controller.isSafeForVisibilityChange)
        #expect(!controller.beginVisibilityChange(to: .hidden))
        #expect(!controller.isAvailable)
        #expect(factory.lengthsAtRemoval == [MenuBarSectionController.standardLength])
    }

    @Test("競合後に境界を再作成した時は初回安全判定へ戻る")
    func resetsInitialSafetyAfterBoundaryRecreation() {
        let factory = FakeBoundaryStatusItemFactory()
        let detector = FakeConflictDetector(conflicts: [])
        var isInitialPlacementSafe = true
        let controller = MenuBarSectionController(
            conflictDetector: detector,
            statusItemFactory: factory,
            operationSafetyCheck: { _ in true },
            initialOperationSafetyCheck: { _ in isInitialPlacementSafe }
        )

        #expect(controller.beginVisibilityChange(to: .hidden))
        controller.endVisibilityChange()
        detector.conflicts = [
            MenuBarManagerConflict(bundleIdentifier: "com.jordanbaird.Ice", displayName: "Ice")
        ]
        controller.refreshAvailability()
        detector.conflicts = []
        isInitialPlacementSafe = false
        controller.refreshAvailability()

        #expect(!controller.isSafeForVisibilityChange)
        #expect(!controller.beginVisibilityChange(to: .shown))
        #expect(!controller.isAvailable)
        #expect(factory.createdItems.count == 2)
        #expect(factory.lengthsAtRemoval == [
            MenuBarSectionController.standardLength,
            MenuBarSectionController.standardLength
        ])
    }
}

@MainActor
private final class FakeConflictDetector: MenuBarManagerConflictDetecting {
    var conflicts: [MenuBarManagerConflict]

    init(conflicts: [MenuBarManagerConflict]) {
        self.conflicts = conflicts
    }

    func runningConflicts() -> [MenuBarManagerConflict] {
        conflicts
    }
}

@MainActor
private final class FakeBoundaryStatusItem: MenuBarBoundaryStatusItem {
    var length: CGFloat
    var autosaveName: String?
    var windowID: CGWindowID? = 77

    init(length: CGFloat) {
        self.length = length
    }
}

@MainActor
private final class FakeBoundaryStatusItemFactory: MenuBarBoundaryStatusItemFactory {
    private(set) var createdItems: [FakeBoundaryStatusItem] = []
    private(set) var removedItems: [ObjectIdentifier] = []
    private(set) var lengthsAtRemoval: [CGFloat] = []

    func makeStatusItem(length: CGFloat) -> any MenuBarBoundaryStatusItem {
        let item = FakeBoundaryStatusItem(length: length)
        createdItems.append(item)
        return item
    }

    func removeStatusItem(_ item: any MenuBarBoundaryStatusItem) {
        removedItems.append(ObjectIdentifier(item))
        lengthsAtRemoval.append(item.length)
    }
}
