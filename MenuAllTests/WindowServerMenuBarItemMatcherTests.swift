import CoreGraphics
import Testing
@testable import MenuAll

@Suite("WindowServerMenuBarItemMatcher")
struct WindowServerMenuBarItemMatcherTests {
    private let matcher = WindowServerMenuBarItemMatcher(frameTolerance: 1)

    @Test("Bundle ID・名前・フレームが一致する一意候補を結合する")
    func matchesUniqueCandidate() {
        let item = accessibilityItem()
        let expected = windowItem()

        let result = matcher.match(item: item, among: [expected])

        #expect(result == .matched(expected))
    }

    @Test("同一フレーム候補のうち所有者が一致するものを選ぶ")
    func prefersOwnerIdentity() {
        let item = accessibilityItem()
        let unrelated = windowItem(
            windowID: 8,
            ownerPID: 8,
            ownerName: "Other",
            ownerBundleIdentifier: "com.example.Other"
        )
        let expected = windowItem(windowID: 9)

        let result = matcher.match(item: item, among: [unrelated, expected])

        #expect(result == .matched(expected))
    }

    @Test("AXのボタン枠を内包するstatus windowを照合する")
    func matchesContainingStatusWindow() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "contained",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Example",
            frame: CGRect(x: 500, y: 3, width: 24, height: 24)
        )
        let expected = WindowServerMenuBarItemDescriptor(
            windowID: 11,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: "Item-0",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 493, y: 0, width: 38, height: 30)
        )

        #expect(matcher.match(item: item, among: [expected]) == .matched(expected))
    }

    @Test("同じ強さの候補が複数ある場合は曖昧として拒否する")
    func rejectsAmbiguousCandidates() {
        let item = accessibilityItem()
        let first = windowItem(windowID: 1)
        let second = windowItem(windowID: 2)

        let result = matcher.match(item: item, among: [first, second])

        #expect(result == .unsupported(reason: "対応するメニューバー項目を一意に特定できません。"))
    }

    @Test("Appleが固定する項目は候補検索前に拒否する")
    func rejectsFixedAppleItem() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "clock",
            ownerPID: 20,
            ownerName: "Control Center",
            bundleIdentifier: "com.apple.controlcenter",
            title: "Clock",
            frame: CGRect(x: 900, y: 0, width: 32, height: 24)
        )

        let result = matcher.match(item: item, among: [windowItem()])

        #expect(result == .unsupported(reason: "macOSにより位置が固定されている項目です。"))
    }

    @Test("日本語表示名と本番形式IDのControl Center項目も拒否する")
    func rejectsLocalizedControlCenterItemWithProductionID() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "42802:AXClock:3",
            ownerPID: 42_802,
            ownerName: "コントロールセンター",
            bundleIdentifier: "com.apple.controlcenter",
            title: "時計",
            frame: CGRect(x: 900, y: 0, width: 32, height: 24)
        )

        let result = matcher.match(item: item, among: [windowItem()])

        #expect(result == .unsupported(reason: "macOSにより位置が固定されている項目です。"))
    }

    @Test("SystemUIServerの項目は表示名に依存せず拒否する")
    func rejectsSystemUIServerItemRegardlessOfTitle() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "512:com.apple.menuextra.example:7",
            ownerPID: 512,
            ownerName: "SystemUIServer",
            bundleIdentifier: "com.apple.systemuiserver",
            title: "入力メニュー",
            frame: CGRect(x: 850, y: 0, width: 32, height: 24)
        )

        let result = matcher.match(item: item, among: [windowItem()])

        #expect(result == .unsupported(reason: "macOSにより位置が固定されている項目です。"))
    }

    @Test("フレームが取得できない項目は拒否する")
    func rejectsMissingFrame() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "missing-frame",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Example",
            frame: nil
        )

        let result = matcher.match(item: item, among: [windowItem()])

        #expect(result == .unsupported(reason: "項目の位置を取得できません。"))
    }

    private func accessibilityItem() -> AccessibilityMenuBarItemDescriptor {
        AccessibilityMenuBarItemDescriptor(
            itemID: "item",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu",
            title: "Example",
            frame: CGRect(x: 500, y: 0, width: 28, height: 24)
        )
    }

    private func windowItem(
        windowID: CGWindowID = 7,
        ownerPID: pid_t = 42,
        ownerName: String = "Example",
        ownerBundleIdentifier: String? = "com.example.Menu"
    ) -> WindowServerMenuBarItemDescriptor {
        WindowServerMenuBarItemDescriptor(
            windowID: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            ownerBundleIdentifier: ownerBundleIdentifier,
            windowName: "Example",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 500, y: 0, width: 28, height: 24)
        )
    }
}
