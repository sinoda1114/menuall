import AppKit
import CoreGraphics
import Foundation

struct AccessibilityMenuBarItemDescriptor: Equatable, Sendable {
    let itemID: String
    let ownerPID: pid_t
    let ownerName: String?
    let bundleIdentifier: String?
    let title: String?
    let frame: CGRect?
}

struct WindowServerMenuBarItemDescriptor: Equatable, Sendable {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let ownerName: String?
    let ownerBundleIdentifier: String?
    let windowName: String?
    let layer: Int
    let frame: CGRect
    let displayID: CGDirectDisplayID?

    init(
        windowID: CGWindowID,
        ownerPID: pid_t,
        ownerName: String?,
        ownerBundleIdentifier: String?,
        windowName: String?,
        layer: Int,
        frame: CGRect,
        displayID: CGDirectDisplayID? = nil
    ) {
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.ownerBundleIdentifier = ownerBundleIdentifier
        self.windowName = windowName
        self.layer = layer
        self.frame = frame
        self.displayID = displayID
    }
}

enum WindowServerMenuBarItemMatch: Equatable, Sendable {
    case matched(WindowServerMenuBarItemDescriptor)
    case unsupported(reason: String)
}

/// AX項目とWindowServerの公開情報を、所有者・名前・フレームから保守的に結合する。
struct WindowServerMenuBarItemMatcher: Sendable {
    let frameTolerance: CGFloat

    init(frameTolerance: CGFloat = 1) {
        self.frameTolerance = max(0, frameTolerance)
    }

    func match(
        item: AccessibilityMenuBarItemDescriptor,
        among windows: [WindowServerMenuBarItemDescriptor]
    ) -> WindowServerMenuBarItemMatch {
        if isFixedAppleItem(item) {
            return .unsupported(reason: "macOSにより位置が固定されている項目です。")
        }
        guard let frame = item.frame else {
            return .unsupported(reason: "項目の位置を取得できません。")
        }

        let scoredCandidates = windows.compactMap { window -> (WindowServerMenuBarItemDescriptor, Int)? in
            guard framesMatch(frame, window.frame) else { return nil }
            return (window, identityScore(item: item, window: window))
        }
        guard !scoredCandidates.isEmpty else {
            return .unsupported(reason: "対応するメニューバー項目を特定できません。")
        }

        let bestScore = scoredCandidates.map(\.1).max() ?? 0
        let bestCandidates = scoredCandidates.filter { $0.1 == bestScore }
        guard bestCandidates.count == 1, let match = bestCandidates.first?.0 else {
            return .unsupported(reason: "対応するメニューバー項目を一意に特定できません。")
        }

        return .matched(match)
    }

    private func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let exactMatch = abs(lhs.minX - rhs.minX) <= frameTolerance
            && abs(lhs.minY - rhs.minY) <= frameTolerance
            && abs(lhs.width - rhs.width) <= frameTolerance
            && abs(lhs.height - rhs.height) <= frameTolerance
        if exactMatch { return true }

        // AXはボタンの内容枠、WindowServerは余白を含むstatus windowを返す。
        // 実機では24x24のAX枠が38x30のstatus window内に入るため、
        // 同一座標空間で完全に内包される場合も同じ項目として扱う。
        return rhs.insetBy(dx: -frameTolerance, dy: -frameTolerance).contains(lhs)
    }

    private func identityScore(
        item: AccessibilityMenuBarItemDescriptor,
        window: WindowServerMenuBarItemDescriptor
    ) -> Int {
        var score = 0
        if let bundleIdentifier = item.bundleIdentifier,
           bundleIdentifier.caseInsensitiveCompare(window.ownerBundleIdentifier ?? "") == .orderedSame {
            score += 8
        }
        if item.ownerPID == window.ownerPID { score += 4 }
        if normalized(item.ownerName) == normalized(window.ownerName), normalized(item.ownerName) != nil {
            score += 2
        }
        if normalized(item.title) == normalized(window.windowName), normalized(item.title) != nil {
            score += 1
        }
        return score
    }

    private func isFixedAppleItem(_ item: AccessibilityMenuBarItemDescriptor) -> Bool {
        switch item.bundleIdentifier?.lowercased() {
        case "com.apple.controlcenter", "com.apple.systemuiserver": true
        default: false
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

/// `CGWindowListCopyWindowInfo`をテストしやすい値型へ変換する。
protocol WindowServerMenuBarItemDescriptorProviding {
    func descriptors() -> [WindowServerMenuBarItemDescriptor]
    func activeDisplayIDs() -> Set<CGDirectDisplayID>
}

struct WindowServerMenuBarItemDescriptorProvider: WindowServerMenuBarItemDescriptorProviding {
    func activeDisplayIDs() -> Set<CGDirectDisplayID> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var displays = Array(repeating: CGDirectDisplayID(), count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else {
            return []
        }
        return Set(displays.prefix(Int(count)))
    }

    func descriptors() -> [WindowServerMenuBarItemDescriptor] {
        guard let rawWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
            as? [[String: Any]]
        else {
            return []
        }

        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let displayIDs = activeDisplayIDs()
        return rawWindows.compactMap { rawWindow in
            guard let layer = (rawWindow[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  layer == statusLayer,
                  let windowID = (rawWindow[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (rawWindow[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let bounds = rawWindow[kCGWindowBounds as String] as? [String: NSNumber],
                  let x = bounds["X"]?.doubleValue,
                  let y = bounds["Y"]?.doubleValue,
                  let width = bounds["Width"]?.doubleValue,
                  let height = bounds["Height"]?.doubleValue
            else {
                return nil
            }

            let frame = CGRect(x: x, y: y, width: width, height: height)

            let application = NSRunningApplication(processIdentifier: ownerPID)
            return WindowServerMenuBarItemDescriptor(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: AXDiscoveryLimits.sanitized(
                    rawWindow[kCGWindowOwnerName as String] as? String
                ),
                ownerBundleIdentifier: AXDiscoveryLimits.sanitized(
                    application?.bundleIdentifier
                ),
                windowName: AXDiscoveryLimits.sanitized(
                    rawWindow[kCGWindowName as String] as? String
                ),
                layer: layer,
                frame: frame,
                displayID: displayID(containing: frame, among: displayIDs)
            )
        }
    }

    private func displayID(
        containing frame: CGRect,
        among displayIDs: Set<CGDirectDisplayID>
    ) -> CGDirectDisplayID? {
        displayIDs.first { displayID in
            CGDisplayBounds(displayID).contains(CGPoint(x: frame.midX, y: frame.midY))
        }
    }
}
