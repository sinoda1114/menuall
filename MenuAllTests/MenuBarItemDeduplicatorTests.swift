import CoreGraphics
import Testing
@testable import MenuAll

struct MenuBarItemDeduplicatorTests {
    @Test("同一所有元の無名かつ座標なしの重複を1件へ集約する")
    func collapsesUnnamedFramelessDuplicatesFromSameOwner() {
        let items = (0..<8).map { index in
            makeItem(
                id: "control-center-\(index)",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false
            )
        }

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.count == 1)
        #expect(result.first?.id == "control-center-0")
    }

    @Test("別名の明示項目がある所有元でも無名フォールバックを1件保持する")
    func keepsUnnamedFallbackWhenExplicitItemsHaveDifferentNames() {
        let items = [
            makeItem(
                id: "generic-1",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false
            ),
            makeItem(
                id: "generic-2",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false
            ),
            makeItem(
                id: "wifi",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "Wi-Fi",
                hasExplicitName: true,
                frame: CGRect(x: 100, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "clock",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "時計",
                hasExplicitName: true,
                frame: CGRect(x: 130, y: 0, width: 20, height: 20)
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["generic-1", "wifi", "clock"])
    }

    @Test("Control Centerのゼロサイズ無名項目を除外して明示名付き項目を保持する")
    func removesZeroSizedControlCenterFallbacks() {
        let unusableFrame = CGRect(x: 0, y: 1_440, width: 0, height: 0)
        let items = [
            makeItem(
                id: "control-center-named",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: true,
                frame: CGRect(x: 160, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "generic-1",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false,
                frame: unusableFrame
            ),
            makeItem(
                id: "generic-2",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false,
                frame: unusableFrame
            ),
            makeItem(
                id: "wifi",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "Wi-Fi",
                hasExplicitName: true
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["control-center-named", "wifi"])
    }

    @Test("Control Centerの実フレーム項目を全件保持して同名の無効な内部ノードを全件除外する")
    func removesAllInvalidControlCenterInternalNodes() {
        let invalidFrame = CGRect(x: 0, y: 1_440, width: 0, height: 0)
        let realItems = [
            makeItem(
                id: "clock",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "時計",
                hasExplicitName: true,
                frame: CGRect(x: 100, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "focus",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "集中モード",
                hasExplicitName: true,
                frame: CGRect(x: 130, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "wifi",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "Wi-Fi",
                hasExplicitName: true,
                frame: CGRect(x: 160, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "control-center",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false,
                frame: CGRect(x: 190, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "screen-mirroring",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "画面ミラーリング",
                hasExplicitName: true,
                frame: CGRect(x: 220, y: 0, width: 20, height: 20)
            )
        ]
        let internalNodes = (0..<8).map { index in
            makeItem(
                id: "internal-\(index)",
                ownerPID: 100,
                ownerName: "コントロールセンター",
                title: "コントロールセンター",
                hasExplicitName: false,
                frame: invalidFrame
            )
        }

        let result = MenuBarItemDeduplicator.deduplicating(realItems + internalNodes)

        #expect(result.map(\.id) == realItems.map(\.id))
    }

    @Test("一般アプリの表示名や無効フレームが異なる無名項目は実フレーム項目と併存させる")
    func preservesDistinctUnnamedItemsFromAnotherApplication() {
        let items = [
            makeItem(
                id: "real",
                ownerPID: 200,
                ownerName: "Utility",
                title: "同期状態",
                hasExplicitName: false,
                frame: CGRect(x: 100, y: 0, width: 20, height: 20)
            ),
            makeItem(
                id: "frameless",
                ownerPID: 200,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false
            ),
            makeItem(
                id: "zero-sized",
                ownerPID: 200,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result == items)
    }

    @Test("使用不能フレームが異なる無名項目はそれぞれ保持する")
    func preservesUnnamedItemsWithDifferentUnusableFrames() {
        let items = [
            makeItem(
                id: "zero",
                ownerPID: 200,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero
            ),
            makeItem(
                id: "negative",
                ownerPID: 200,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: CGRect(x: 10, y: 10, width: -1, height: 20)
            ),
            makeItem(
                id: "infinite",
                ownerPID: 200,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: CGRect(x: CGFloat.infinity, y: 10, width: 20, height: 20)
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["zero", "negative", "infinite"])
    }

    @Test("別名の明示項目があっても操作可能な無名項目を保持する")
    func preservesActionableUnnamedItemWhenExplicitItemHasDifferentName() {
        let items = [
            makeItem(
                id: "unnamed-actionable",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                actions: ["AXPress", "AXCancel"]
            ),
            makeItem(
                id: "named",
                ownerPID: 300,
                ownerName: "Utility",
                title: "同期状態",
                hasExplicitName: true,
                frame: CGRect(x: 200, y: 0, width: 20, height: 20)
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["unnamed-actionable", "named"])
    }

    @Test("操作一覧を取得しなくても異なるIDの無名項目を保持する")
    func preservesDistinctUnnamedItemsWithoutActionMetadata() {
        let items = [
            makeItem(
                id: "first",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero,
                actions: []
            ),
            makeItem(
                id: "second",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero,
                actions: []
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["first", "second"])
    }

    @Test("操作集合が異なる無名項目は同じ使用不能フレームでも保持する")
    func preservesUnnamedItemsWithDifferentActions() {
        let items = [
            makeItem(
                id: "press",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero,
                actions: ["AXPress"]
            ),
            makeItem(
                id: "show-menu",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false,
                frame: .zero,
                actions: ["AXShowMenu"]
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["press", "show-menu"])
    }

    @Test("一般アプリでは同名の明示項目と異なるIDの無名項目をすべて保持する")
    func keepsUnnamedFallbackWhenMatchingExplicitItemHasNoUsableFrame() {
        let items = [
            makeItem(
                id: "named-frameless",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: true
            ),
            makeItem(
                id: "unnamed-first",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false
            ),
            makeItem(
                id: "unnamed-second",
                ownerPID: 300,
                ownerName: "Utility",
                title: "Utility",
                hasExplicitName: false
            )
        ]

        let result = MenuBarItemDeduplicator.deduplicating(items)

        #expect(result.map(\.id) == ["named-frameless", "unnamed-first", "unnamed-second"])
    }

    @Test("他アプリの単一無名項目は削除しない")
    func preservesSingleUnnamedItemFromAnotherApplication() {
        let item = makeItem(
            id: "utility-item",
            ownerPID: 200,
            ownerName: "Utility",
            title: "Utility",
            hasExplicitName: false
        )

        let result = MenuBarItemDeduplicator.deduplicating([item])

        #expect(result == [item])
    }

    @Test("所有元が異なる同一表示名の無名項目はそれぞれ保持する")
    func preservesUnnamedItemsFromDifferentOwners() {
        let first = makeItem(
            id: "first",
            ownerPID: 200,
            ownerName: "Helper",
            title: "Helper",
            hasExplicitName: false
        )
        let second = makeItem(
            id: "second",
            ownerPID: 201,
            ownerName: "Helper",
            title: "Helper",
            hasExplicitName: false
        )

        let result = MenuBarItemDeduplicator.deduplicating([first, second])

        #expect(result == [first, second])
    }

    @Test("座標を持つ無名項目は同一表示名でも保持する")
    func preservesUnnamedItemsWithFrames() {
        let first = makeItem(
            id: "first",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "コントロールセンター",
            hasExplicitName: false,
            frame: CGRect(x: 100, y: 0, width: 20, height: 20)
        )
        let second = makeItem(
            id: "second",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "コントロールセンター",
            hasExplicitName: false,
            frame: CGRect(x: 130, y: 0, width: 20, height: 20)
        )

        let result = MenuBarItemDeduplicator.deduplicating([first, second])

        #expect(result == [first, second])
    }

    @Test("同じ明示名を持つ項目は座標なしでも集約しない")
    func preservesExplicitItemsWithSameDisplayName() {
        let first = makeItem(
            id: "wifi-1",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "Wi-Fi",
            hasExplicitName: true
        )
        let second = makeItem(
            id: "wifi-2",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "Wi-Fi",
            hasExplicitName: true
        )

        let result = MenuBarItemDeduplicator.deduplicating([first, second])

        #expect(result == [first, second])
    }

    @Test("同一IDの明示項目が重複しても先頭の1件だけを保持する")
    func collapsesDuplicateExplicitItemIDs() {
        let first = makeItem(
            id: "wifi",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "Wi-Fi",
            hasExplicitName: true
        )
        let duplicate = makeItem(
            id: "wifi",
            ownerPID: 100,
            ownerName: "コントロールセンター",
            title: "Wi-Fi duplicate",
            hasExplicitName: true
        )

        let result = MenuBarItemDeduplicator.deduplicating([first, duplicate])

        #expect(result == [first])
    }
}

private extension MenuBarItemDeduplicatorTests {
    func makeItem(
        id: String,
        ownerPID: Int32,
        ownerName: String,
        title: String,
        hasExplicitName: Bool,
        frame: CGRect? = nil,
        actions: [String] = []
    ) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(
            id: id,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bundleIdentifier: ownerName == "コントロールセンター"
                ? "com.apple.controlcenter"
                : nil,
            title: title,
            hasExplicitName: hasExplicitName,
            actions: actions,
            frame: frame
        )
    }
}
