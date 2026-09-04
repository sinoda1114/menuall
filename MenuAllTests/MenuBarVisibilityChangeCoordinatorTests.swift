import Foundation
import Testing
@testable import MenuAll

@Suite("MenuBarVisibilityChangeCoordinator", .serialized)
@MainActor
struct MenuBarVisibilityChangeCoordinatorTests {
    @Test("隠れている項目を表示へ変更し観測成功後に完了する")
    func changesHiddenItemToShown() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.hidden, .visible])
        let timing = ManualVisibilityChangeTiming()
        let coordinator = makeCoordinator(driver: driver, timing: timing)

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .changed(to: .shown))
        #expect(driver.beginTargets == [.shown])
        #expect(driver.rollbackOperationIDs.isEmpty)
        #expect(driver.finalizedOperationIDs.count == 1)
        #expect(coordinator.phases.isEmpty)
        #expect(!coordinator.isChanging)
    }

    @Test("表示中の項目を非表示へ変更できる")
    func changesVisibleItemToHidden() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.visible, .hidden])
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .visible),
            to: .hidden
        )

        #expect(outcome == .changed(to: .hidden))
        #expect(driver.beginTargets == [.hidden])
        #expect(coordinator.phases.isEmpty)
    }

    @Test("既に目標状態ならドライバーを呼ばない")
    func skipsChangeWhenAlreadyAtTarget() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [])
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .visible),
            to: .shown
        )

        #expect(outcome == .unchanged)
        #expect(driver.availabilityCallCount == 0)
        #expect(driver.beginTargets.isEmpty)
        #expect(coordinator.phases.isEmpty)
    }

    @Test("位置不明の項目は変更せず理由を返す")
    func rejectsUnknownVisibility() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [])
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .unknown),
            to: .shown
        )

        #expect(outcome == .unavailable(reason: "現在の表示状態を確認できません。"))
        #expect(driver.availabilityCallCount == 0)
        #expect(driver.beginTargets.isEmpty)
        #expect(coordinator.phases.isEmpty)
    }

    @Test("非対応項目は変更を開始しない")
    func rejectsUnsupportedItem() async {
        let driver = FakeMenuBarVisibilityChanger(
            availability: .unavailable(reason: "この項目は移動できません。"),
            observations: []
        )
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .unavailable(reason: "この項目は移動できません。"))
        #expect(driver.beginTargets.isEmpty)
        #expect(coordinator.phases.isEmpty)
    }

    @Test("変更開始失敗ではrollbackせずpendingを解除する")
    func reportsBeginFailureWithoutRollback() async {
        let driver = FakeMenuBarVisibilityChanger(
            observations: [.hidden],
            beginError: TestError("変更開始に失敗")
        )
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .failed(message: "変更開始に失敗"))
        #expect(driver.rollbackOperationIDs.isEmpty)
        #expect(coordinator.phases.isEmpty)
        #expect(!coordinator.isChanging)
    }

    @Test("検証が一度位置不明でも期限内に目標状態なら成功する")
    func toleratesUnknownObservationBeforeSuccess() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.hidden, .unknown, .visible])
        let timing = ManualVisibilityChangeTiming()
        let coordinator = makeCoordinator(driver: driver, timing: timing)

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .changed(to: .shown))
        #expect(driver.observedCallCount == 3)
        #expect(timing.sleepDurations == [.milliseconds(100)])
        #expect(driver.rollbackOperationIDs.isEmpty)
    }

    @Test("検証timeout時はrollbackして元に戻した結果を返す")
    func rollsBackAfterVerificationTimeout() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.hidden])
        let timing = ManualVisibilityChangeTiming()
        let coordinator = makeCoordinator(driver: driver, timing: timing)

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .rolledBack(message: "変更を確認できなかったため元に戻しました。"))
        #expect(driver.rollbackOperationIDs.count == 1)
        #expect(timing.now >= .milliseconds(300))
        #expect(coordinator.phases.isEmpty)
    }

    @Test("timeout後のrollback失敗を区別して返す")
    func reportsRollbackFailure() async {
        let driver = FakeMenuBarVisibilityChanger(
            observations: [.hidden],
            rollbackError: TestError("復元に失敗")
        )
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .rollbackFailed(message: "復元に失敗"))
        #expect(driver.rollbackOperationIDs.count == 1)
        #expect(coordinator.phases.isEmpty)
    }

    @Test("rollback呼び出し後も元状態を観測できなければ失敗にする")
    func reportsUnverifiedRollback() async {
        let driver = FakeMenuBarVisibilityChanger(
            observations: [.hidden, .unknown, .unknown, .unknown, .visible]
        )
        let timing = ManualVisibilityChangeTiming()
        let coordinator = makeCoordinator(driver: driver, timing: timing)

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(
            outcome == .rollbackFailed(
                message: "元の状態へ戻ったことを確認できませんでした。"
            )
        )
    }

    @Test("元の側へ戻っても並び位置が戻らなければrollback失敗にする")
    func reportsRollbackPositionMismatch() async {
        let driver = FakeMenuBarVisibilityChanger(
            observations: [.hidden],
            rollbackPositionRestored: false
        )
        let timing = ManualVisibilityChangeTiming()
        let coordinator = makeCoordinator(driver: driver, timing: timing)

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(
            outcome == .rollbackFailed(
                message: "元の状態へ戻ったことを確認できませんでした。"
            )
        )
        #expect(driver.finalizedOperationIDs.count == 1)
    }

    @Test("操作中の二重要求は開始せずbusyを返す")
    func preventsConcurrentChanges() async {
        let driver = FakeMenuBarVisibilityChanger(
            observations: [.hidden, .visible],
            suspendsBegin: true
        )
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let first = Task { @MainActor in
            await coordinator.change(
                item: makeItem(id: "first", visibility: .hidden),
                to: .shown
            )
        }

        while driver.beginTargets.isEmpty {
            await Task.yield()
        }

        let second = await coordinator.change(
            item: makeItem(id: "second", visibility: .visible),
            to: .hidden
        )

        #expect(second == .busy)
        #expect(driver.beginTargets == [.shown])

        driver.resumeBegin()
        #expect(await first.value == .changed(to: .shown))
        #expect(coordinator.phases.isEmpty)
        #expect(!coordinator.isChanging)
    }

    @Test("操作直前に既に目標状態ならdragを開始しない")
    func skipsWhenLiveStateAlreadyMatchesTarget() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.visible])
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(outcome == .unchanged)
        #expect(driver.beginTargets.isEmpty)
    }

    @Test("操作直前の状態が不明ならdragを開始しない")
    func rejectsUnknownLiveStateBeforeChange() async {
        let driver = FakeMenuBarVisibilityChanger(observations: [.unknown])
        let coordinator = makeCoordinator(
            driver: driver,
            timing: ManualVisibilityChangeTiming()
        )

        let outcome = await coordinator.change(
            item: makeItem(visibility: .hidden),
            to: .shown
        )

        #expect(
            outcome == .unavailable(
                reason: "表示状態が更新されました。再読み込み後にもう一度お試しください。"
            )
        )
        #expect(driver.beginTargets.isEmpty)
    }

    @Test("操作ゲートは完了前の二重開始を拒否する")
    func operationGateRejectsConcurrentBegin() {
        var gate = MenuBarVisibilityOperationGate()

        let first = gate.begin()
        let second = gate.begin()

        #expect(first != nil)
        #expect(second == nil)
        #expect(gate.isActive)
    }

    @Test("古い操作IDは現在の進捗を解除できない")
    func operationGateRejectsStaleCompletion() {
        var gate = MenuBarVisibilityOperationGate()
        let activeID = gate.begin()!

        let staleFinished = gate.finish(UUID())
        #expect(!staleFinished)
        #expect(gate.owns(activeID))
        let activeFinished = gate.finish(activeID)
        #expect(activeFinished)
        #expect(!gate.isActive)
    }

    private func makeCoordinator(
        driver: FakeMenuBarVisibilityChanger,
        timing: ManualVisibilityChangeTiming
    ) -> MenuBarVisibilityChangeCoordinator {
        MenuBarVisibilityChangeCoordinator(
            changer: driver,
            timing: timing,
            verificationTimeout: .milliseconds(300),
            verificationInterval: .milliseconds(100)
        )
    }
}

@MainActor
private final class FakeMenuBarVisibilityChanger: MenuBarVisibilityChanging {
    var availability: VisibilityControlAvailability
    var observations: [MenuBarItemVisibility]
    var beginError: Error?
    var observationError: Error?
    var rollbackError: Error?
    var suspendsBegin: Bool
    var rollbackPositionRestored: Bool

    private(set) var availabilityCallCount = 0
    private(set) var beginTargets: [MenuBarVisibilityTarget] = []
    private(set) var observedCallCount = 0
    private(set) var rollbackOperationIDs: [UUID] = []
    private(set) var finalizedOperationIDs: [UUID] = []
    private var beginContinuation: CheckedContinuation<Void, Never>?

    init(
        availability: VisibilityControlAvailability = .available,
        observations: [MenuBarItemVisibility],
        beginError: Error? = nil,
        observationError: Error? = nil,
        rollbackError: Error? = nil,
        suspendsBegin: Bool = false,
        rollbackPositionRestored: Bool = true
    ) {
        self.availability = availability
        self.observations = observations
        self.beginError = beginError
        self.observationError = observationError
        self.rollbackError = rollbackError
        self.suspendsBegin = suspendsBegin
        self.rollbackPositionRestored = rollbackPositionRestored
    }

    func availability(for itemID: String) async -> VisibilityControlAvailability {
        availabilityCallCount += 1
        return availability
    }

    func beginChange(
        itemID: String,
        from: MenuBarItemVisibility,
        to target: MenuBarVisibilityTarget
    ) async throws -> VisibilityChangeReceipt {
        beginTargets.append(target)
        if suspendsBegin {
            await withCheckedContinuation { continuation in
                beginContinuation = continuation
            }
        }
        if let beginError {
            throw beginError
        }
        return VisibilityChangeReceipt(
            operationID: UUID(),
            itemID: itemID,
            from: from,
            target: target
        )
    }

    func observedVisibility(itemID: String) async throws -> MenuBarItemVisibility {
        observedCallCount += 1
        if let observationError {
            throw observationError
        }
        guard !observations.isEmpty else {
            return .unknown
        }
        if observations.count == 1 {
            return observations[0]
        }
        return observations.removeFirst()
    }

    func rollback(operationID: UUID) async throws {
        rollbackOperationIDs.append(operationID)
        if let rollbackError {
            throw rollbackError
        }
    }

    func finalize(operationID: UUID) async {
        finalizedOperationIDs.append(operationID)
    }

    func isRollbackPositionRestored(operationID: UUID) async throws -> Bool {
        rollbackPositionRestored
    }

    func resumeBegin() {
        suspendsBegin = false
        beginContinuation?.resume()
        beginContinuation = nil
    }
}

@MainActor
private final class ManualVisibilityChangeTiming: VisibilityChangeTiming {
    private(set) var now: Duration = .zero
    private(set) var sleepDurations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        sleepDurations.append(duration)
        now += duration
    }
}

private struct TestError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private func makeItem(
    id: String = "item",
    visibility: MenuBarItemVisibility
) -> MenuBarItemSnapshot {
    MenuBarItemSnapshot(
        id: id,
        ownerPID: 100,
        ownerName: "Test App",
        title: "Test Item",
        visibility: visibility
    )
}
