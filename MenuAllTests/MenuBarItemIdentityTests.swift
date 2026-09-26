import Testing
@testable import MenuAll

@Suite("MenuBarItemIdentity")
struct MenuBarItemIdentityTests {
    @Test("同じAX要素は列挙位置に依存しないIDになる")
    func isStableWithoutEnumerationIndex() {
        let first = MenuBarItemIdentity.make(
            ownerPID: 321,
            stablePart: "com.example.status",
            elementHash: 9_876
        )
        let rediscovered = MenuBarItemIdentity.make(
            ownerPID: 321,
            stablePart: "com.example.status",
            elementHash: 9_876
        )

        #expect(first == rediscovered)
        #expect(first == "321:2694:com.example.status")
    }

    @Test("同名の別AX要素は異なるIDになる")
    func distinguishesElementsWithTheSameName() {
        let first = MenuBarItemIdentity.make(
            ownerPID: 321,
            stablePart: "Status",
            elementHash: 1
        )
        let second = MenuBarItemIdentity.make(
            ownerPID: 321,
            stablePart: "Status",
            elementHash: 2
        )

        #expect(first != second)
    }

    @Test("AX由来文字列を上限長へ切り詰める")
    func limitsUntrustedAccessibilityStrings() {
        let oversized = String(repeating: "あ", count: AXDiscoveryLimits.maximumStringLength + 100)

        #expect(
            AXDiscoveryLimits.sanitized(oversized)?.unicodeScalars.count
                == AXDiscoveryLimits.maximumStringLength
        )
    }

    @Test("巨大な結合文字列もUnicode scalar上限で止める")
    func limitsCombiningAccessibilityStrings() {
        let oversized = "a" + String(repeating: "\u{0301}", count: 10_000)

        #expect(
            AXDiscoveryLimits.sanitized(oversized)?.unicodeScalars.count
                == AXDiscoveryLimits.maximumStringLength
        )
    }

    @Test("AX由来の空文字とnilを区別して保持する")
    func preservesEmptyAndNilAccessibilityStrings() {
        #expect(AXDiscoveryLimits.sanitized("") == "")
        #expect(AXDiscoveryLimits.sanitized(nil) == nil)
    }
}
