import CoreGraphics
import Foundation
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

    @Test("所有者identityがないscore 0のstatus windowは照合しない")
    func rejectsContainingStatusWindowWithoutOwnerIdentity() {
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

        #expect(
            matcher.match(item: item, among: [expected])
                == .unsupported(reason: "対応するメニューバー項目を特定できません。")
        )
    }

    @Test("検証済みOSホストがbundle名で代理所有するstatus windowを照合する")
    func matchesTrustedSystemHostProxy() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "proxied",
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
            windowName: "com.example.Menu",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 493, y: 0, width: 38, height: 30),
            isTrustedSystemMenuBarHost: true
        )

        #expect(matcher.match(item: item, among: [expected]) == .matched(expected))
    }

    @Test("OSホストを自己申告するだけのwindowは代理照合しない")
    func rejectsUntrustedSystemHostProxyClaim() {
        let item = accessibilityItem()
        let claimedProxy = WindowServerMenuBarItemDescriptor(
            windowID: 11,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: "com.example.Menu",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 500, y: 0, width: 28, height: 24)
        )

        #expect(
            matcher.match(item: item, among: [claimedProxy])
                == .unsupported(reason: "対応するメニューバー項目を特定できません。")
        )
    }

    @Test("既知bundle IDでもSystem実行ファイルでなければ信頼しない")
    func requiresProtectedSystemExecutableForHostTrust() {
        #expect(
            !SystemMenuBarHostTrust.isTrusted(
                bundleIdentifier: "com.apple.controlcenter",
                executableURL: URL(fileURLWithPath: "/tmp/ControlCenter.app/Contents/MacOS/ControlCenter"),
                hasValidAppleSignature: true
            )
        )
        #expect(
            SystemMenuBarHostTrust.isTrusted(
                bundleIdentifier: "com.apple.controlcenter",
                executableURL: URL(
                    fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"
                ),
                hasValidAppleSignature: true
            )
        )
        #expect(
            !SystemMenuBarHostTrust.isTrusted(
                bundleIdentifier: "com.apple.controlcenter",
                executableURL: URL(
                    fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"
                ),
                hasValidAppleSignature: false
            )
        )
    }

    @Test("既知OSホストでない場合は署名検証を実行しない")
    func skipsSignatureValidationBeforeSystemHostPreflightPasses() {
        var signatureValidationCount = 0
        let validateSignature = {
            signatureValidationCount += 1
            return true
        }

        let untrustedResult = SystemMenuBarHostTrust.isTrusted(
            bundleIdentifier: "com.example.Menu",
            executableURL: URL(fileURLWithPath: "/Applications/Example.app/Contents/MacOS/Example"),
            hasValidAppleSignature: validateSignature()
        )
        #expect(!untrustedResult)
        #expect(signatureValidationCount == 0)

        let wrongPathResult = SystemMenuBarHostTrust.isTrusted(
            bundleIdentifier: "com.apple.controlcenter",
            executableURL: URL(fileURLWithPath: "/Applications/ControlCenter"),
            hasValidAppleSignature: validateSignature()
        )
        #expect(!wrongPathResult)
        #expect(signatureValidationCount == 0)

        let trustedResult = SystemMenuBarHostTrust.isTrusted(
            bundleIdentifier: "com.apple.controlcenter",
            executableURL: URL(
                fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"
            ),
            hasValidAppleSignature: validateSignature()
        )
        #expect(trustedResult)
        #expect(signatureValidationCount == 1)
    }

    @Test("代理window名はbundle IDと大文字小文字を含め完全一致させる")
    func rejectsCaseMismatchedProxyWindowName() {
        let item = accessibilityItem()
        let proxy = WindowServerMenuBarItemDescriptor(
            windowID: 11,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: "com.example.menu",
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 500, y: 0, width: 28, height: 24),
            isTrustedSystemMenuBarHost: true
        )

        #expect(
            matcher.match(item: item, among: [proxy])
                == .unsupported(reason: "対応するメニューバー項目を特定できません。")
        )
    }

    @Test("不正なbundle IDは検証済みOSホストでも代理照合しない")
    func rejectsMalformedBundleIdentifierForProxy() {
        let item = AccessibilityMenuBarItemDescriptor(
            itemID: "malformed",
            ownerPID: 42,
            ownerName: "Example",
            bundleIdentifier: "com.example.Menu\" or anchor apple",
            title: "Example",
            frame: CGRect(x: 500, y: 0, width: 28, height: 24)
        )
        let proxy = WindowServerMenuBarItemDescriptor(
            windowID: 11,
            ownerPID: 900,
            ownerName: "Control Center",
            ownerBundleIdentifier: "com.apple.controlcenter",
            windowName: item.bundleIdentifier,
            layer: Int(CGWindowLevelForKey(.statusWindow)),
            frame: CGRect(x: 500, y: 0, width: 28, height: 24),
            isTrustedSystemMenuBarHost: true
        )

        #expect(
            matcher.match(item: item, among: [proxy])
                == .unsupported(reason: "対応するメニューバー項目を特定できません。")
        )
    }

    @Test("同じPIDでもbundle IDが不一致ならstale windowとして拒否する")
    func rejectsSamePIDWithConflictingBundleIdentifiers() {
        let item = accessibilityItem()
        let staleWindow = windowItem(
            ownerPID: item.ownerPID,
            ownerName: "Example",
            ownerBundleIdentifier: "com.example.ReusedPID"
        )

        #expect(
            matcher.match(item: item, among: [staleWindow])
                == .unsupported(reason: "対応するメニューバー項目を特定できません。")
        )
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
