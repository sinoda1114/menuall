import CoreGraphics
import Testing
@testable import MenuAll

struct MenuBarVisibilityClassifierTests {
    private let primary = MenuBarScreenRegion(
        id: "primary",
        menuBarFrame: CGRect(x: 0, y: 0, width: 1_440, height: 24),
        obstructionFrames: [CGRect(x: 660, y: 0, width: 120, height: 24)]
    )

    @Test("メニューバー領域内でAX非表示でなければ表示中と判定する")
    func visibleInsideMenuBar() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_200, y: 2, width: 22, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .visible)
    }

    @Test("メニューバー境界に一致する要素は表示中と判定する")
    func visibleAtExactBoundary() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 0, y: 0, width: 24, height: 24),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .visible)
    }

    @Test("ノッチ排除領域と交差する要素は非表示と判定する")
    func hiddenWhenIntersectingNotch() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 650, y: 2, width: 30, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .hidden)
    }

    @Test("ノッチ境界に接するだけの要素は表示中と判定する")
    func visibleWhenOnlyTouchingNotchBoundary() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 636, y: 2, width: 24, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .visible)
    }

    @Test("メニューバー領域から一部でも外れる要素は非表示と判定する")
    func hiddenWhenPartlyOutsideMenuBar() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_430, y: 2, width: 20, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .hidden)
    }

    @Test("AXHiddenがtrueなら座標にかかわらず非表示と判定する")
    func hiddenWhenAXHiddenIsTrue() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_200, y: 2, width: 22, height: 20),
            isAXHidden: true,
            screens: [primary]
        )

        #expect(result == .hidden)
    }

    @Test("AXHiddenがtrueなら座標がなくても非表示と判定する")
    func hiddenWithoutFrameWhenAXHiddenIsTrue() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: nil,
            isAXHidden: true,
            screens: [primary]
        )

        #expect(result == .hidden)
    }

    @Test("座標がなければ状態不明と判定する")
    func unknownWithoutFrame() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: nil,
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .unknown)
    }

    @Test("AXHidden属性がなくても画面内の座標から表示中と判定する")
    func visibleFromGeometryWithoutAXHiddenAttribute() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_200, y: 2, width: 22, height: 20),
            isAXHidden: nil,
            screens: [primary]
        )

        #expect(result == .visible)
    }

    @Test("画面情報がなければ状態不明と判定する")
    func unknownWithoutScreens() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_200, y: 2, width: 22, height: 20),
            isAXHidden: false,
            screens: []
        )

        #expect(result == .unknown)
    }

    @Test("どの画面のメニューバー領域にもない要素は非表示と判定する")
    func hiddenOutsideEveryScreenMenuBar() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 400, y: 200, width: 22, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .hidden)
    }

    @Test("複数画面では要素を含む画面だけを使って判定する")
    func visibleOnSecondaryScreen() {
        let secondary = MenuBarScreenRegion(
            id: "secondary",
            menuBarFrame: CGRect(x: 1_440, y: -100, width: 1_920, height: 26),
            obstructionFrames: []
        )

        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 3_100, y: -98, width: 22, height: 20),
            isAXHidden: false,
            screens: [primary, secondary]
        )

        #expect(result == .visible)
    }

    @Test("幅または高さがない座標は状態不明と判定する")
    func unknownForEmptyFrame() {
        let result = MenuBarVisibilityClassifier.classify(
            frame: CGRect(x: 1_200, y: 2, width: 0, height: 20),
            isAXHidden: false,
            screens: [primary]
        )

        #expect(result == .unknown)
    }
}

struct MenuBarScreenGeometryTests {
    @Test("実際の上端予約領域がStatusBar値より高い場合は予約領域を使う")
    func usesVisibleFrameTopInset() {
        let height = MenuBarScreenGeometry.menuBarHeight(
            screenFrame: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: 0, y: 60, width: 2_560, height: 1_350),
            statusBarThickness: 22
        )

        #expect(height == 30)
    }

    @Test("上端予約領域がない副画面ではAX項目の下端余白を含める")
    func includesAXItemBottomPaddingOnSecondaryScreen() {
        let height = MenuBarScreenGeometry.menuBarHeight(
            screenFrame: CGRect(x: 2_560, y: -358, width: 1_080, height: 1_920),
            visibleFrame: CGRect(x: 2_560, y: -358, width: 1_080, height: 1_920),
            statusBarThickness: 22
        )

        #expect(height == 30)
    }
}
