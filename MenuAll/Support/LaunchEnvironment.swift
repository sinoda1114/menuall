import Foundation

/// UIテストから注入する起動条件を、製品コードから分離して扱うための窓口。
///
/// Releaseビルドでは常に無効になるため、環境変数によって製品動作が変わることはない。
enum LaunchEnvironment {
    enum UITestRoute: String, Sendable {
        case onboarding
        case popover
    }

    enum AccessibilityAuthorization: String, Sendable {
        case denied
        case granted
    }

    enum VisibilityChangeScenario: String, Sendable {
        case success
        case failure
        case unsupported
        case delayed
    }

    private enum Key {
        static let uiTesting = "MENUALL_UI_TESTING"
        static let route = "MENUALL_UI_TEST_ROUTE"
        static let accessibilitySequence = "MENUALL_UI_TEST_ACCESSIBILITY_SEQUENCE"
        static let suppressExternalNavigation = "MENUALL_UI_TEST_SUPPRESS_EXTERNAL_NAVIGATION"
        static let livePopoverDiscovery = "MENUALL_UI_TEST_LIVE_DISCOVERY"
        static let revokeAccessibilityOnItemAction =
            "MENUALL_UI_TEST_REVOKE_ACCESSIBILITY_ON_ITEM_ACTION"
        static let visibilityFixture = "MENUALL_UI_TEST_VISIBILITY_FIXTURE"
        static let visibilityChangeScenario = "MENUALL_UI_TEST_VISIBILITY_CHANGE_SCENARIO"
    }

    private static var environment: [String: String] {
        ProcessInfo.processInfo.environment
    }

    static var isUITesting: Bool {
#if DEBUG
        environment[Key.uiTesting] == "1"
#else
        false
#endif
    }

    /// ステータス項目をXCUIから直接操作できない環境向けの起動経路。
    /// 通常起動時は `nil` となり、製品の起動フローには影響しない。
    static var uiTestRoute: UITestRoute? {
        guard isUITesting, let rawValue = environment[Key.route] else {
            return nil
        }

        return UITestRoute(rawValue: rawValue)
    }

    /// `AXIsProcessTrusted` の実OS状態を使わず、権限案内を再現するための値。
    /// `checkIndex` は初回確認を0とし、「再確認」のたびに1増やす。
    /// シーケンスの末尾を超えた場合は最後の状態を維持する。
    static func accessibilityAuthorizationOverride(
        atCheckIndex checkIndex: Int
    ) -> AccessibilityAuthorization? {
        guard isUITesting else {
            return nil
        }

        let sequence = environment[Key.accessibilitySequence, default: ""]
            .split(separator: ",")
            .compactMap { token in
                AccessibilityAuthorization(rawValue: token.trimmingCharacters(in: .whitespaces))
            }

        guard !sequence.isEmpty else {
            return nil
        }

        let safeIndex = min(max(checkIndex, 0), sequence.count - 1)
        return sequence[safeIndex]
    }

    /// UIテスト中にシステム設定を実際に開いてフォーカスを失うことを防ぐ。
    static var shouldSuppressExternalNavigation: Bool {
        guard isUITesting else {
            return false
        }

        return environment[Key.suppressExternalNavigation] == "1"
    }

    /// 実権限を使う技術検証時だけ、テスト用ポップアップでAX列挙を動かす。
    /// Releaseビルドでは`isUITesting`が常にfalseになるため有効化されない。
    static var shouldRunLivePopoverDiscovery: Bool {
        guard isUITesting, uiTestRoute == .popover else {
            return false
        }

        return environment[Key.livePopoverDiscovery] == "1"
    }

    /// 項目操作の完了直前に権限が失われる境界ケースをUIテストで再現する。
    static var shouldRevokeAccessibilityOnItemAction: Bool {
        guard isUITesting, uiTestRoute == .popover else {
            return false
        }

        return environment[Key.revokeAccessibilityOnItemAction] == "1"
    }

    static var shouldUseVisibilityFixture: Bool {
        guard isUITesting, uiTestRoute == .popover else { return false }
        return environment[Key.visibilityFixture] == "three-categories" ||
            visibilityChangeScenario != nil
    }

    static var visibilityChangeScenario: VisibilityChangeScenario? {
        guard isUITesting, uiTestRoute == .popover,
              let value = environment[Key.visibilityChangeScenario]
        else { return nil }
        return VisibilityChangeScenario(rawValue: value)
    }
}
