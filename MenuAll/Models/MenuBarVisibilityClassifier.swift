import CoreGraphics

struct MenuBarScreenRegion: Equatable, Sendable {
    let id: String
    let menuBarFrame: CGRect
    let obstructionFrames: [CGRect]

    init(id: String, menuBarFrame: CGRect, obstructionFrames: [CGRect] = []) {
        self.id = id
        self.menuBarFrame = menuBarFrame
        self.obstructionFrames = obstructionFrames
    }
}

enum MenuBarScreenGeometry {
    static func menuBarHeight(
        screenFrame: CGRect,
        visibleFrame: CGRect,
        statusBarThickness: CGFloat
    ) -> CGFloat {
        let topInset = max(screenFrame.maxY - visibleFrame.maxY, 0)
        // AX menu bar item frames can extend below NSStatusBar.system.thickness,
        // especially on secondary displays where visibleFrame has no top inset.
        let axItemEnvelope = statusBarThickness + 8
        return max(topInset, axItemEnvelope, 1)
    }
}

enum MenuBarVisibilityClassifier {
    static func classify(
        frame: CGRect?,
        isAXHidden: Bool?,
        screens: [MenuBarScreenRegion]
    ) -> MenuBarItemVisibility {
        if isAXHidden == true {
            return .hidden
        }

        guard let frame, frame.isUsable else {
            return .unknown
        }

        guard !screens.isEmpty else {
            return .unknown
        }

        let containingScreens = screens.filter { $0.menuBarFrame.containsEntirely(frame) }
        guard !containingScreens.isEmpty else {
            return .hidden
        }

        let isObstructedOnEveryContainingScreen = containingScreens.allSatisfy { screen in
            screen.obstructionFrames.contains { obstruction in
                obstruction.isUsable && obstruction.intersection(frame).hasPositiveArea
            }
        }

        if isObstructedOnEveryContainingScreen {
            return .hidden
        }

        return .visible
    }
}

private extension CGRect {
    var isUsable: Bool {
        !isNull
            && !isInfinite
            && origin.x.isFinite
            && origin.y.isFinite
            && width.isFinite
            && height.isFinite
            && width > 0
            && height > 0
    }

    var hasPositiveArea: Bool {
        !isNull && width > 0 && height > 0
    }

    func containsEntirely(_ other: CGRect) -> Bool {
        isUsable
            && minX <= other.minX
            && minY <= other.minY
            && maxX >= other.maxX
            && maxY >= other.maxY
    }
}
