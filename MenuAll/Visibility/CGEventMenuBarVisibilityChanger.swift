import CoreGraphics
import Foundation

struct MenuBarVisibilityEndpoint: Equatable, Sendable {
    let itemID: String
    let windowID: CGWindowID
    let sourcePID: pid_t
    let frame: CGRect
    let displayID: CGDirectDisplayID?

    init(
        itemID: String,
        windowID: CGWindowID,
        sourcePID: pid_t,
        frame: CGRect,
        displayID: CGDirectDisplayID? = nil
    ) {
        self.itemID = itemID
        self.windowID = windowID
        self.sourcePID = sourcePID
        self.frame = frame
        self.displayID = displayID
    }
}

@MainActor
protocol MenuBarVisibilityEndpointResolving: AnyObject {
    func availability(for itemID: String) -> VisibilityControlAvailability
    func endpoint(for itemID: String) -> MenuBarVisibilityEndpoint?
    func boundaryEndpoint() -> MenuBarVisibilityEndpoint?
    func endpoints(
        for itemID: String
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)?
    func rollbackAvailability(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> VisibilityControlAvailability
    func rollbackEndpoints(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)?
    func observedVisibility(itemID: String) -> MenuBarItemVisibility
    func beginLayoutTransaction(to target: MenuBarVisibilityTarget) -> Bool
    func endLayoutTransaction()
}

extension MenuBarVisibilityEndpointResolving {
    func endpoints(
        for itemID: String
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)? {
        guard let item = endpoint(for: itemID),
              let boundary = boundaryEndpoint()
        else { return nil }
        return (item, boundary)
    }

    func beginLayoutTransaction(to target: MenuBarVisibilityTarget) -> Bool { true }
    func endLayoutTransaction() {}

    func rollbackAvailability(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> VisibilityControlAvailability {
        availability(for: itemID)
    }

    func rollbackEndpoints(
        for itemID: String,
        assumingCurrentVisibility visibility: MenuBarItemVisibility
    ) -> (item: MenuBarVisibilityEndpoint, boundary: MenuBarVisibilityEndpoint)? {
        endpoints(for: itemID)
    }
}

enum MenuBarDragEventPhase: Equatable, Sendable {
    case mouseDown
    case mouseDragged
    case mouseUp
}

struct MenuBarDragEventSpecification: Equatable, Sendable {
    let phase: MenuBarDragEventPhase
    let location: CGPoint
    let windowID: CGWindowID
    let targetPID: pid_t?
    let usesCommandModifier: Bool
}

@MainActor
protocol MenuBarDragEvent: AnyObject { }

@MainActor
protocol MenuBarDragEventGenerating: AnyObject {
    func makeEvent(_ specification: MenuBarDragEventSpecification) throws -> any MenuBarDragEvent
}

@MainActor
protocol MenuBarDragEventPosting: AnyObject {
    func post(_ event: any MenuBarDragEvent, toPID pid: pid_t) throws
}

/// 対象ウインドウへ限定したCommand-dragを生成する。UIへ接続するまでは実イベントを発生させない。
@MainActor
final class CGEventMenuBarVisibilityChanger: MenuBarVisibilityChanging {
    private struct RollbackRecord {
        let itemID: String
        let originalTarget: MenuBarVisibilityTarget
        let expectedCurrentVisibility: MenuBarItemVisibility
        let originalCenterX: CGFloat
    }

    private let resolver: any MenuBarVisibilityEndpointResolving
    private let eventGenerator: any MenuBarDragEventGenerating
    private let eventPoster: any MenuBarDragEventPosting
    private var rollbackRecords: [UUID: RollbackRecord] = [:]

    init(
        resolver: any MenuBarVisibilityEndpointResolving,
        eventGenerator: any MenuBarDragEventGenerating = CoreGraphicsMenuBarDragEventGenerator(),
        eventPoster: any MenuBarDragEventPosting = CoreGraphicsMenuBarDragEventPoster()
    ) {
        self.resolver = resolver
        self.eventGenerator = eventGenerator
        self.eventPoster = eventPoster
    }

    func availability(for itemID: String) async -> VisibilityControlAvailability {
        resolver.availability(for: itemID)
    }

    func beginChange(
        itemID: String,
        from: MenuBarItemVisibility,
        to target: MenuBarVisibilityTarget
    ) async throws -> VisibilityChangeReceipt {
        let availability = resolver.availability(for: itemID)
        guard case .available = availability else {
            if case let .unavailable(reason) = availability {
                throw CGEventMenuBarVisibilityChangerError.unavailable(reason)
            }
            throw CGEventMenuBarVisibilityChangerError.unavailable("この項目は変更できません。")
        }
        guard let originalTarget = originalTarget(for: from) else {
            throw CGEventMenuBarVisibilityChangerError.unknownVisibility
        }
        // 境界を展開する前の座標で対象windowを確定し、短期cacheを作る。
        // 展開後に隣の項目が古いAX frameへ移動しても初回照合へ戻さない。
        guard resolver.endpoints(for: itemID) != nil else {
            throw CGEventMenuBarVisibilityChangerError.itemEndpointNotFound
        }

        guard resolver.beginLayoutTransaction(to: target) else {
            throw CGEventMenuBarVisibilityChangerError.unavailable(
                "表示・非表示の境界を準備できません。"
            )
        }
        do {
            // NSStatusItemの再レイアウトを待ち、展開後のwindow座標を解決する。
            try await Task.sleep(for: .milliseconds(80))
            let refreshedAvailability = resolver.availability(for: itemID)
            guard case .available = refreshedAvailability else {
                if case let .unavailable(reason) = refreshedAvailability {
                    throw CGEventMenuBarVisibilityChangerError.unavailable(reason)
                }
                throw CGEventMenuBarVisibilityChangerError.unavailable(
                    "この項目は変更できません。"
                )
            }
            let originalCenterX = try performChange(itemID: itemID, target: target)
            let operationID = UUID()
            rollbackRecords[operationID] = RollbackRecord(
                itemID: itemID,
                originalTarget: originalTarget,
                expectedCurrentVisibility: target == .shown ? .visible : .hidden,
                originalCenterX: originalCenterX
            )
            return VisibilityChangeReceipt(
                operationID: operationID,
                itemID: itemID,
                from: from,
                target: target
            )
        } catch {
            resolver.endLayoutTransaction()
            throw error
        }
    }

    func observedVisibility(itemID: String) async throws -> MenuBarItemVisibility {
        resolver.observedVisibility(itemID: itemID)
    }

    func rollback(operationID: UUID) async throws {
        guard let record = rollbackRecords[operationID] else {
            throw CGEventMenuBarVisibilityChangerError.rollbackRecordNotFound
        }

        do {
            let availability = resolver.rollbackAvailability(
                for: record.itemID,
                assumingCurrentVisibility: record.expectedCurrentVisibility
            )
            guard case .available = availability else {
                if case let .unavailable(reason) = availability {
                    throw CGEventMenuBarVisibilityChangerError.unavailable(reason)
                }
                throw CGEventMenuBarVisibilityChangerError.unavailable(
                    "この項目は変更できません。"
                )
            }
            _ = try performChange(
                itemID: record.itemID,
                target: record.originalTarget,
                destinationX: record.originalCenterX,
                assumedVisibility: record.expectedCurrentVisibility
            )
        } catch {
            rollbackRecords[operationID] = nil
            resolver.endLayoutTransaction()
            throw error
        }
    }

    func isRollbackPositionRestored(operationID: UUID) async throws -> Bool {
        guard let record = rollbackRecords[operationID],
              let endpoints = resolver.endpoints(for: record.itemID)
        else { return false }
        return abs(endpoints.item.frame.midX - record.originalCenterX) <= 2
    }

    func finalize(operationID: UUID) async {
        guard rollbackRecords.removeValue(forKey: operationID) != nil else { return }
        resolver.endLayoutTransaction()
    }

    @discardableResult
    private func performChange(
        itemID: String,
        target: MenuBarVisibilityTarget,
        destinationX: CGFloat? = nil,
        assumedVisibility: MenuBarItemVisibility? = nil
    ) throws -> CGFloat {
        let resolvedEndpoints = if let assumedVisibility {
            resolver.rollbackEndpoints(
                for: itemID,
                assumingCurrentVisibility: assumedVisibility
            )
        } else {
            resolver.endpoints(for: itemID)
        }
        guard let endpoints = resolvedEndpoints else {
            throw CGEventMenuBarVisibilityChangerError.itemEndpointNotFound
        }
        let item = endpoints.item
        let boundary = endpoints.boundary

        let start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        let targetX = destinationX ?? (target == .shown ? boundary.frame.maxX : boundary.frame.minX)
        let destination = CGPoint(x: targetX, y: boundary.frame.midY)

        guard let itemDisplayID = item.displayID,
              let boundaryDisplayID = boundary.displayID,
              itemDisplayID == boundaryDisplayID
        else {
            throw CGEventMenuBarVisibilityChangerError.displayMismatch
        }

        let steps = 6
        var specifications = [
            MenuBarDragEventSpecification(
                phase: .mouseDown,
                location: start,
                windowID: item.windowID,
                targetPID: item.sourcePID,
                usesCommandModifier: true
            )
        ]
        for step in 1...steps {
            let progress = CGFloat(step) / CGFloat(steps + 1)
            specifications.append(
                MenuBarDragEventSpecification(
                    phase: .mouseDragged,
                    location: CGPoint(
                        x: start.x + ((destination.x - start.x) * progress),
                        y: start.y + ((destination.y - start.y) * progress)
                    ),
                    windowID: step == steps ? boundary.windowID : item.windowID,
                    targetPID: item.sourcePID,
                    usesCommandModifier: true
                )
            )
        }
        specifications.append(
            MenuBarDragEventSpecification(
                phase: .mouseUp,
                location: destination,
                windowID: boundary.windowID,
                // 1つのdrag gestureをmouseDownの受信プロセスへ最後まで配送する。
                targetPID: item.sourcePID,
                usesCommandModifier: true
            )
        )

        let events = try specifications.map(eventGenerator.makeEvent)
        for (index, event) in events.enumerated() {
            let targetPID = specifications[index].targetPID ?? item.sourcePID
            try eventPoster.post(event, toPID: targetPID)
        }
        return start.x
    }

    private func originalTarget(for visibility: MenuBarItemVisibility) -> MenuBarVisibilityTarget? {
        switch visibility {
        case .visible: .shown
        case .hidden: .hidden
        case .unknown: nil
        }
    }
}

private enum CGEventMenuBarVisibilityChangerError: LocalizedError {
    case unavailable(String)
    case unknownVisibility
    case itemEndpointNotFound
    case boundaryEndpointNotFound
    case eventCreationFailed
    case incompatibleEvent
    case rollbackRecordNotFound
    case displayMismatch

    var errorDescription: String? {
        switch self {
        case let .unavailable(reason): reason
        case .unknownVisibility: "現在の表示状態を確認できません。"
        case .itemEndpointNotFound: "対象項目をWindowServer上で特定できません。"
        case .boundaryEndpointNotFound: "表示・非表示の境界を特定できません。"
        case .eventCreationFailed: "メニューバー操作イベントを作成できません。"
        case .incompatibleEvent: "メニューバー操作イベントの形式が不正です。"
        case .rollbackRecordNotFound: "元に戻すための情報が見つかりません。"
        case .displayMismatch: "対象と境界が別の画面にあるため変更できません。"
        }
    }
}

@MainActor
private final class CoreGraphicsMenuBarDragEvent: MenuBarDragEvent {
    let event: CGEvent

    init(event: CGEvent) {
        self.event = event
    }
}

@MainActor
private final class CoreGraphicsMenuBarDragEventGenerator: MenuBarDragEventGenerating {
    func makeEvent(_ specification: MenuBarDragEventSpecification) throws -> any MenuBarDragEvent {
        let eventType: CGEventType
        switch specification.phase {
        case .mouseDown: eventType = .leftMouseDown
        case .mouseDragged: eventType = .leftMouseDragged
        case .mouseUp: eventType = .leftMouseUp
        }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: specification.location,
            mouseButton: .left
        ) else {
            throw CGEventMenuBarVisibilityChangerError.eventCreationFailed
        }

        event.flags = specification.usesCommandModifier ? .maskCommand : []
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(specification.windowID))
        event.setIntegerValueField(
            .mouseEventWindowUnderMousePointerThatCanHandleThisEvent,
            value: Int64(specification.windowID)
        )
        if let targetPID = specification.targetPID {
            event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(targetPID))
        }
        return CoreGraphicsMenuBarDragEvent(event: event)
    }
}

@MainActor
private final class CoreGraphicsMenuBarDragEventPoster: MenuBarDragEventPosting {
    private var originalPointerLocation: CGPoint?

    func post(_ event: any MenuBarDragEvent, toPID pid: pid_t) throws {
        guard let event = event as? CoreGraphicsMenuBarDragEvent else {
            throw CGEventMenuBarVisibilityChangerError.incompatibleEvent
        }
        if event.event.type == .leftMouseDown {
            originalPointerLocation = CGEvent(source: nil)?.location
        }
        // 解決済みの所有プロセスだけへ配送し、別アプリ上の同座標へ漏らさない。
        event.event.postToPid(pid)
        if event.event.type == .leftMouseUp,
           let originalPointerLocation {
            CGWarpMouseCursorPosition(originalPointerLocation)
            self.originalPointerLocation = nil
        }
    }
}
