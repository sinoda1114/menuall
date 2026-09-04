import CoreGraphics
import Testing
@testable import MenuAll

@Suite("CGEventMenuBarVisibilityChanger")
@MainActor
struct CGEventMenuBarVisibilityChangerTests {
    @Test("非表示項目を表示するとき境界の右側へCommand-dragする")
    func beginsShowChange() async throws {
        let resolver = FakeVisibilityEndpointResolver(visibility: .hidden)
        let generator = FakeDragEventGenerator()
        let poster = FakeDragEventPoster()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: poster
        )

        let receipt = try await changer.beginChange(
            itemID: "item",
            from: .hidden,
            to: .shown
        )

        #expect(receipt.itemID == "item")
        #expect(generator.specifications.count == 8)
        #expect(generator.specifications[0].phase == .mouseDown)
        #expect(generator.specifications[0].windowID == 10)
        #expect(generator.specifications[0].usesCommandModifier)
        #expect(generator.specifications.dropFirst().dropLast().allSatisfy { $0.phase == .mouseDragged })
        #expect(generator.specifications[7].phase == .mouseUp)
        #expect(generator.specifications[7].windowID == 20)
        #expect(generator.specifications[7].location.x == 440)
        #expect(generator.specifications[7].usesCommandModifier)
        #expect(poster.targetPIDs == [42, 42, 42, 42, 42, 42, 42, 42])
        #expect(resolver.endpointCallCount >= 1)
        #expect(resolver.layoutTargets == [.shown])
        #expect(resolver.endLayoutCallCount == 0)

        await changer.finalize(operationID: receipt.operationID)
        #expect(resolver.endLayoutCallCount == 1)
    }

    @Test("表示項目を非表示にするとき境界の左側へ移動する")
    func beginsHideChange() async throws {
        let resolver = FakeVisibilityEndpointResolver(visibility: .visible)
        let generator = FakeDragEventGenerator()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: FakeDragEventPoster()
        )

        _ = try await changer.beginChange(
            itemID: "item",
            from: .visible,
            to: .hidden
        )

        #expect(generator.specifications.last?.location.x == 400)
    }

    @Test("rollbackは変更前の側へ戻すイベントを生成する")
    func rollsBackToOriginalSide() async throws {
        let resolver = FakeVisibilityEndpointResolver(visibility: .hidden)
        let generator = FakeDragEventGenerator()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: FakeDragEventPoster()
        )
        let receipt = try await changer.beginChange(
            itemID: "item",
            from: .hidden,
            to: .shown
        )

        try await changer.rollback(operationID: receipt.operationID)

        #expect(generator.specifications.count == 16)
        #expect(generator.specifications.last?.location.x == 514)
        #expect(try await changer.isRollbackPositionRestored(operationID: receipt.operationID))
        await changer.finalize(operationID: receipt.operationID)
        #expect(resolver.endLayoutCallCount == 1)
    }

    @Test("競合または結合失敗の理由をavailabilityへ返す")
    func reportsUnavailableReason() async {
        let resolver = FakeVisibilityEndpointResolver(
            visibility: .hidden,
            availability: .unavailable(reason: "Iceが起動中です。")
        )
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: FakeDragEventGenerator(),
            eventPoster: FakeDragEventPoster()
        )

        #expect(await changer.availability(for: "item") == .unavailable(reason: "Iceが起動中です。"))
    }

    @Test("観測状態はresolverから読み直す")
    func observesLatestVisibility() async throws {
        let resolver = FakeVisibilityEndpointResolver(visibility: .visible)
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: FakeDragEventGenerator(),
            eventPoster: FakeDragEventPoster()
        )

        #expect(try await changer.observedVisibility(itemID: "item") == .visible)
    }

    @Test("境界トランザクションを開始できなければイベントを生成しない")
    func refusesChangeWhenLayoutTransactionCannotStart() async {
        let resolver = FakeVisibilityEndpointResolver(
            visibility: .hidden,
            allowsLayoutTransaction: false
        )
        let generator = FakeDragEventGenerator()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: FakeDragEventPoster()
        )

        await #expect(throws: Error.self) {
            _ = try await changer.beginChange(
                itemID: "item",
                from: .hidden,
                to: .shown
            )
        }

        #expect(generator.specifications.isEmpty)
        #expect(resolver.layoutTargets == [.shown])
    }

    @Test("境界展開中に競合が発生したらイベント送信前に中断する")
    func stopsWhenAvailabilityChangesAfterLayoutStarts() async {
        let resolver = FakeVisibilityEndpointResolver(
            visibility: .hidden,
            availabilityAfterLayoutStart: .unavailable(reason: "Iceが起動中です。")
        )
        let generator = FakeDragEventGenerator()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: FakeDragEventPoster()
        )

        await #expect(throws: Error.self) {
            _ = try await changer.beginChange(
                itemID: "item",
                from: .hidden,
                to: .shown
            )
        }

        #expect(generator.specifications.isEmpty)
        #expect(resolver.endLayoutCallCount == 1)
    }

    @Test("変更後に競合が発生したらrollbackイベントを送らず失敗する")
    func refusesRollbackWhenAvailabilityWasLost() async throws {
        let resolver = FakeVisibilityEndpointResolver(visibility: .hidden)
        let generator = FakeDragEventGenerator()
        let changer = CGEventMenuBarVisibilityChanger(
            resolver: resolver,
            eventGenerator: generator,
            eventPoster: FakeDragEventPoster()
        )
        let receipt = try await changer.beginChange(
            itemID: "item",
            from: .hidden,
            to: .shown
        )
        #expect(generator.specifications.count == 8)
        resolver.availability = .unavailable(reason: "Iceが起動中です。")

        await #expect(throws: Error.self) {
            try await changer.rollback(operationID: receipt.operationID)
        }

        #expect(generator.specifications.count == 8)
        #expect(resolver.endLayoutCallCount == 1)
    }
}

@MainActor
private final class FakeVisibilityEndpointResolver: MenuBarVisibilityEndpointResolving {
    var visibility: MenuBarItemVisibility
    var availability: VisibilityControlAvailability
    var allowsLayoutTransaction: Bool
    var availabilityAfterLayoutStart: VisibilityControlAvailability?
    private(set) var layoutTargets: [MenuBarVisibilityTarget] = []
    private(set) var endLayoutCallCount = 0
    private(set) var endpointCallCount = 0

    init(
        visibility: MenuBarItemVisibility,
        availability: VisibilityControlAvailability = .available,
        allowsLayoutTransaction: Bool = true,
        availabilityAfterLayoutStart: VisibilityControlAvailability? = nil
    ) {
        self.visibility = visibility
        self.availability = availability
        self.allowsLayoutTransaction = allowsLayoutTransaction
        self.availabilityAfterLayoutStart = availabilityAfterLayoutStart
    }

    func availability(for itemID: String) -> VisibilityControlAvailability {
        availability
    }

    func endpoint(for itemID: String) -> MenuBarVisibilityEndpoint? {
        endpointCallCount += 1
        return MenuBarVisibilityEndpoint(
            itemID: itemID,
            windowID: 10,
            sourcePID: 42,
            frame: CGRect(x: 500, y: 0, width: 28, height: 24),
            displayID: 1
        )
    }

    func boundaryEndpoint() -> MenuBarVisibilityEndpoint? {
        MenuBarVisibilityEndpoint(
            itemID: "boundary",
            windowID: 20,
            sourcePID: 900,
            frame: CGRect(x: 400, y: 0, width: 40, height: 24),
            displayID: 1
        )
    }

    func observedVisibility(itemID: String) -> MenuBarItemVisibility {
        visibility
    }

    func beginLayoutTransaction(to target: MenuBarVisibilityTarget) -> Bool {
        layoutTargets.append(target)
        if let availabilityAfterLayoutStart {
            availability = availabilityAfterLayoutStart
        }
        return allowsLayoutTransaction
    }

    func endLayoutTransaction() {
        endLayoutCallCount += 1
    }
}

@MainActor
private final class FakeDragEvent: MenuBarDragEvent { }

@MainActor
private final class FakeDragEventGenerator: MenuBarDragEventGenerating {
    private(set) var specifications: [MenuBarDragEventSpecification] = []

    func makeEvent(_ specification: MenuBarDragEventSpecification) throws -> any MenuBarDragEvent {
        specifications.append(specification)
        return FakeDragEvent()
    }
}

@MainActor
private final class FakeDragEventPoster: MenuBarDragEventPosting {
    private(set) var targetPIDs: [pid_t] = []

    func post(_ event: any MenuBarDragEvent, toPID pid: pid_t) throws {
        targetPIDs.append(pid)
    }
}
