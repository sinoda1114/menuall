import Foundation

/// 表示変更を1件ずつ実行し、観測による成功確認と失敗時のrollbackを担う。
@MainActor
final class MenuBarVisibilityChangeCoordinator {
    private(set) var phases: [String: VisibilityChangePhase] = [:]

    var isChanging: Bool {
        activeItemID != nil
    }

    private let changer: any MenuBarVisibilityChanging
    private let timing: any VisibilityChangeTiming
    private let verificationTimeout: Duration
    private let verificationInterval: Duration
    private var activeItemID: String?

    init(
        changer: any MenuBarVisibilityChanging,
        timing: any VisibilityChangeTiming = ContinuousVisibilityChangeTiming(),
        verificationTimeout: Duration = .seconds(2),
        verificationInterval: Duration = .milliseconds(150)
    ) {
        self.changer = changer
        self.timing = timing
        self.verificationTimeout = max(verificationTimeout, .zero)
        self.verificationInterval = max(verificationInterval, .milliseconds(1))
    }

    func change(
        item: MenuBarItemSnapshot,
        to target: MenuBarVisibilityTarget
    ) async -> VisibilityChangeOutcome {
        guard activeItemID == nil else {
            return .busy
        }
        guard item.visibility != .unknown else {
            return .unavailable(reason: "現在の表示状態を確認できません。")
        }
        guard !target.matches(item.visibility) else {
            return .unchanged
        }

        activeItemID = item.id
        phases[item.id] = .changing(target)
        defer {
            phases[item.id] = nil
            activeItemID = nil
        }

        let availability = await changer.availability(for: item.id)
        guard case .available = availability else {
            if case let .unavailable(reason) = availability {
                return .unavailable(reason: reason)
            }
            return .unavailable(reason: "この項目は変更できません。")
        }

        // 2秒周期の一覧より新しい実状態を、イベント送信の直前に確認する。
        // 既に目標側なら順序を変えるだけの不要なdragを送らない。
        do {
            let current = try await changer.observedVisibility(itemID: item.id)
            if target.matches(current) {
                return .unchanged
            }
            guard current == item.visibility else {
                return .unavailable(reason: "表示状態が更新されました。再読み込み後にもう一度お試しください。")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }

        let receipt: VisibilityChangeReceipt
        do {
            receipt = try await changer.beginChange(
                itemID: item.id,
                from: item.visibility,
                to: target
            )
        } catch {
            return .failed(message: error.localizedDescription)
        }

        phases[item.id] = .verifying(target)
        let startedAt = timing.now
        let deadline = startedAt + verificationTimeout

        do {
            while timing.now < deadline {
                let observed = try await changer.observedVisibility(itemID: item.id)
                if target.matches(observed) {
                    await changer.finalize(operationID: receipt.operationID)
                    return .changed(to: target)
                }

                let remaining = deadline - timing.now
                guard remaining > .zero else { break }
                try await timing.sleep(for: min(verificationInterval, remaining))
            }
        } catch {
            return await rollback(
                receipt: receipt,
                successMessage: "変更を確認できなかったため元に戻しました。"
            )
        }

        return await rollback(
            receipt: receipt,
            successMessage: "変更を確認できなかったため元に戻しました。"
        )
    }

    private func rollback(
        receipt: VisibilityChangeReceipt,
        successMessage: String
    ) async -> VisibilityChangeOutcome {
        do {
            try await changer.rollback(operationID: receipt.operationID)
        } catch {
            await changer.finalize(operationID: receipt.operationID)
            return .rollbackFailed(message: error.localizedDescription)
        }

        let deadline = timing.now + verificationTimeout
        do {
            while timing.now < deadline {
                let observed = try await changer.observedVisibility(itemID: receipt.itemID)
                if observed == receipt.from,
                   try await changer.isRollbackPositionRestored(
                       operationID: receipt.operationID
                   ) {
                    await changer.finalize(operationID: receipt.operationID)
                    return .rolledBack(message: successMessage)
                }
                let remaining = deadline - timing.now
                guard remaining > .zero else { break }
                try await timing.sleep(for: min(verificationInterval, remaining))
            }
        } catch {
            await changer.finalize(operationID: receipt.operationID)
            return .rollbackFailed(message: "元の状態を再確認できませんでした。")
        }
        await changer.finalize(operationID: receipt.operationID)
        return .rollbackFailed(message: "元の状態へ戻ったことを確認できませんでした。")
    }
}
