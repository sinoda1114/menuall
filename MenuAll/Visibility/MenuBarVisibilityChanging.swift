import Foundation

/// 他アプリのメニューバー項目を動かすOS依存処理の境界。
///
/// 実装は変更を開始した時点の復元情報を`operationID`に関連付けて保持する。
/// これにより上位層へAX要素や画面座標を公開せずにrollbackできる。
@MainActor
protocol MenuBarVisibilityChanging: AnyObject {
    func availability(for itemID: String) async -> VisibilityControlAvailability

    func beginChange(
        itemID: String,
        from: MenuBarItemVisibility,
        to target: MenuBarVisibilityTarget
    ) async throws -> VisibilityChangeReceipt

    func observedVisibility(itemID: String) async throws -> MenuBarItemVisibility

    func rollback(operationID: UUID) async throws

    /// rollback後に元の並び位置まで戻ったかを確認する。
    func isRollbackPositionRestored(operationID: UUID) async throws -> Bool

    /// 変更の再観測が成功した後、復元情報と一時レイアウトを解放する。
    func finalize(operationID: UUID) async
}

extension MenuBarVisibilityChanging {
    func isRollbackPositionRestored(operationID: UUID) async throws -> Bool { true }
    func finalize(operationID: UUID) async {}
}

/// UIから同時に複数の表示変更を開始しないための世代付きゲート。
/// 完了した処理は、自分が開始した世代だけを解除できる。
struct MenuBarVisibilityOperationGate {
    private(set) var activeOperationID: UUID?

    var isActive: Bool { activeOperationID != nil }

    mutating func begin() -> UUID? {
        guard activeOperationID == nil else { return nil }
        let operationID = UUID()
        activeOperationID = operationID
        return operationID
    }

    func owns(_ operationID: UUID) -> Bool {
        activeOperationID == operationID
    }

    mutating func finish(_ operationID: UUID) -> Bool {
        guard owns(operationID) else { return false }
        activeOperationID = nil
        return true
    }
}

/// 検証待ちを実時間から分離し、Unitテストで決定的に進めるための境界。
@MainActor
protocol VisibilityChangeTiming: AnyObject {
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

@MainActor
final class ContinuousVisibilityChangeTiming: VisibilityChangeTiming {
    private let clock = ContinuousClock()
    private lazy var origin = clock.now

    var now: Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}
