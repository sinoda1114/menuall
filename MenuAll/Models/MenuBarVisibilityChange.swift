import Foundation

/// 利用者が要求するメニューバー上の状態。
///
/// `MenuBarItemVisibility` はOSから読み取った観測値なので、要求値とは分離する。
enum MenuBarVisibilityTarget: Equatable, Sendable {
    case shown
    case hidden

    func matches(_ visibility: MenuBarItemVisibility) -> Bool {
        switch (self, visibility) {
        case (.shown, .visible), (.hidden, .hidden):
            true
        default:
            false
        }
    }
}

enum VisibilityControlAvailability: Equatable, Sendable {
    case available
    case unavailable(reason: String)
}

struct VisibilityChangeReceipt: Equatable, Sendable {
    let operationID: UUID
    let itemID: String
    let from: MenuBarItemVisibility
    let target: MenuBarVisibilityTarget
}

enum VisibilityChangePhase: Equatable, Sendable {
    case changing(MenuBarVisibilityTarget)
    case verifying(MenuBarVisibilityTarget)
}

enum VisibilityChangeOutcome: Equatable, Sendable {
    case changed(to: MenuBarVisibilityTarget)
    case unchanged
    case unavailable(reason: String)
    case failed(message: String)
    case rolledBack(message: String)
    case rollbackFailed(message: String)
    case busy
}
