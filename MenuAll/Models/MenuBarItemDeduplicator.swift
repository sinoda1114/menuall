import Foundation

enum MenuBarItemDeduplicator {
    static func deduplicating(_ items: [MenuBarItemSnapshot]) -> [MenuBarItemSnapshot] {
        var seenIDs = Set<String>()
        let uniqueItems = items.filter { seenIDs.insert($0.id).inserted }
        let spatiallyRepresentedItems = Set(
            uniqueItems.lazy
                .filter { isUsable($0.frame) }
                .map(ownerDisplayKey)
        )
        var seenUnnamedItems = Set<DeduplicationKey>()

        return uniqueItems.filter { item in
            guard isControlCenter(item),
                  !item.hasExplicitName,
                  !isUsable(item.frame)
            else {
                return true
            }

            let identity = ownerDisplayKey(item)
            guard !spatiallyRepresentedItems.contains(identity) else {
                return false
            }

            let key = DeduplicationKey(
                identity: identity,
                frame: frameSignature(item.frame)
            )
            return seenUnnamedItems.insert(key).inserted
        }
    }
}

private extension MenuBarItemDeduplicator {
    struct OwnerDisplayKey: Hashable {
        let ownerPID: Int32
        let displayName: String
    }

    struct DeduplicationKey: Hashable {
        let identity: OwnerDisplayKey
        let frame: FrameSignature
    }

    enum FrameSignature: Hashable {
        case missing
        case value(x: UInt64, y: UInt64, width: UInt64, height: UInt64)
    }

    static func ownerDisplayKey(_ item: MenuBarItemSnapshot) -> OwnerDisplayKey {
        OwnerDisplayKey(ownerPID: item.ownerPID, displayName: normalized(item.title))
    }

    static func frameSignature(_ frame: CGRect?) -> FrameSignature {
        guard let frame else { return .missing }
        return .value(
            x: Double(frame.origin.x).bitPattern,
            y: Double(frame.origin.y).bitPattern,
            width: Double(frame.size.width).bitPattern,
            height: Double(frame.size.height).bitPattern
        )
    }

    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }

    static func isControlCenter(_ item: MenuBarItemSnapshot) -> Bool {
        item.bundleIdentifier?.lowercased() == "com.apple.controlcenter"
    }

    static func isUsable(_ frame: CGRect?) -> Bool {
        guard let frame else { return false }
        return !frame.isNull
            && !frame.isInfinite
            && frame.origin.x.isFinite
            && frame.origin.y.isFinite
            && frame.size.width.isFinite
            && frame.size.height.isFinite
            && frame.size.width > 0
            && frame.size.height > 0
    }
}
