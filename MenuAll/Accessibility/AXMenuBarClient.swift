@preconcurrency import ApplicationServices
import CoreGraphics
import Foundation

struct RunningApplicationDescriptor: Sendable {
    let pid: pid_t
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
}

struct MenuBarScreenDescriptor: Sendable {
    let frame: CGRect
    let menuBarFrame: CGRect
    let obstructionFrames: [CGRect]
}

struct RawMenuBarItem: Sendable {
    let id: String
    let ownerPID: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let title: String
    let hasExplicitName: Bool
    let detail: String?
    let role: String?
    let frame: CGRect?
    let isAXHidden: Bool?
    let actions: [String]
}

struct MenuBarDiscoveryFailure: Identifiable, Sendable {
    let id: String
    let ownerPID: pid_t
    let ownerName: String
    let errorCode: Int32
    let message: String
}

struct AXDiscoveryReport: Sendable {
    let items: [RawMenuBarItem]
    let failures: [MenuBarDiscoveryFailure]
}

enum MenuBarItemIdentity {
    static func make(
        ownerPID: pid_t,
        stablePart: String,
        elementHash: CFHashCode
    ) -> String {
        "\(ownerPID):\(String(elementHash, radix: 16)):\(stablePart)"
    }
}

enum AXDiscoveryLimits {
    static let maximumApplications = 512
    static let maximumRootsPerApplication = 64
    static let maximumNodesPerApplication = 512
    static let maximumItemsPerApplication = 128
    static let maximumChildrenPerNode = 128
    static let maximumStringLength = 512
    static let maximumDiscoveryDuration: Duration = .seconds(2)
    static let discoveryMessagingTimeout: Float = 0.1
    static let actionMessagingTimeout: Float = 0.5

    static func sanitized(_ value: String?) -> String? {
        guard let value else { return nil }
        return String(
            String.UnicodeScalarView(value.unicodeScalars.prefix(maximumStringLength))
        )
    }
}

enum MenuBarActionError: LocalizedError, Sendable {
    case itemExpired
    case unsupported
    case accessibility(AXError)

    var errorDescription: String? {
        switch self {
        case .itemExpired:
            "項目が更新されたため、もう一度選択してください。"
        case .unsupported:
            "この項目はAccessibility操作を公開していません。"
        case let .accessibility(error):
            "元のメニューを開けませんでした（AXエラー: \(error.rawValue)）。"
        }
    }
}

actor AXMenuBarClient {
    private var actionTargets: [String: AXUIElement] = [:]

    func discover(applications: [RunningApplicationDescriptor]) -> AXDiscoveryReport {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: AXDiscoveryLimits.maximumDiscoveryDuration)
        var discovered: [RawMenuBarItem] = []
        var failures: [MenuBarDiscoveryFailure] = []
        var nextTargets: [String: AXUIElement] = [:]
        var conflictingItemIDs = Set<String>()

        for application in applications.prefix(AXDiscoveryLimits.maximumApplications) {
            guard clock.now < deadline else {
                failures.append(deadlineFailure(for: application))
                break
            }
            let applicationElement = AXUIElementCreateApplication(application.pid)
            AXUIElementSetMessagingTimeout(
                applicationElement,
                AXDiscoveryLimits.discoveryMessagingTimeout
            )

            let rootResult = menuBarRoots(from: applicationElement)
            guard rootResult.error == .success else {
                if shouldReport(rootResult.error) {
                    failures.append(
                        MenuBarDiscoveryFailure(
                            id: "\(application.pid)-\(rootResult.error.rawValue)",
                            ownerPID: application.pid,
                            ownerName: application.name,
                            errorCode: rootResult.error.rawValue,
                            message: message(for: rootResult.error)
                        )
                    )
                }
                continue
            }
            let roots = rootResult.elements
            var menuBarItems: [AXUIElement] = []
            var visited = Set<CFHashCode>()
            var remainingNodeBudget = AXDiscoveryLimits.maximumNodesPerApplication

            for root in roots {
                guard menuBarItems.count < AXDiscoveryLimits.maximumItemsPerApplication,
                      remainingNodeBudget > 0
                else { break }
                collectMenuBarItems(
                    from: root,
                    depth: 0,
                    visited: &visited,
                    remainingNodeBudget: &remainingNodeBudget,
                    clock: clock,
                    deadline: deadline,
                    results: &menuBarItems
                )
            }

            if menuBarItems.isEmpty {
                for root in roots {
                    guard clock.now < deadline else {
                        failures.append(deadlineFailure(for: application))
                        break
                    }
                    let remaining = AXDiscoveryLimits.maximumItemsPerApplication
                        - menuBarItems.count
                    guard remaining > 0 else { break }
                    menuBarItems.append(contentsOf: children(of: root).prefix(remaining))
                }
            }

            for element in menuBarItems.prefix(AXDiscoveryLimits.maximumItemsPerApplication) {
                guard clock.now < deadline else {
                    failures.append(deadlineFailure(for: application))
                    break
                }
                let attributes = itemAttributes(from: element)
                let stablePart = attributes.identifier
                    ?? attributes.title
                    ?? attributes.description
                    ?? "item"
                let itemID = MenuBarItemIdentity.make(
                    ownerPID: application.pid,
                    stablePart: stablePart,
                    elementHash: CFHash(element)
                )
                guard !conflictingItemIDs.contains(itemID) else { continue }
                if let existingTarget = nextTargets[itemID] {
                    if CFEqual(existingTarget, element) {
                        continue
                    }
                    // A hash/identifier collision must never pair the first
                    // snapshot with a later element as its action target.
                    nextTargets[itemID] = nil
                    conflictingItemIDs.insert(itemID)
                    discovered.removeAll { $0.id == itemID }
                    continue
                }
                let explicitName = firstNonEmpty(
                    attributes.title,
                    attributes.description,
                    attributes.help
                )
                let title = explicitName ?? application.name
                discovered.append(
                    RawMenuBarItem(
                        id: itemID,
                        ownerPID: application.pid,
                        ownerName: application.name,
                        bundleIdentifier: application.bundleIdentifier,
                        bundleURL: application.bundleURL,
                        title: title,
                        hasExplicitName: explicitName != nil,
                        detail: attributes.description == title ? attributes.help : attributes.description,
                        role: attributes.role,
                        frame: frame(of: element),
                        isAXHidden: boolAttribute(kAXHiddenAttribute as CFString, from: element),
                        actions: []
                    )
                )
                nextTargets[itemID] = element
            }
        }

        actionTargets = nextTargets
        return AXDiscoveryReport(items: discovered, failures: failures)
    }

    func performPrimaryAction(itemID: String) throws {
        guard let element = actionTargets[itemID] else {
            throw MenuBarActionError.itemExpired
        }

        AXUIElementSetMessagingTimeout(element, AXDiscoveryLimits.actionMessagingTimeout)
        let pressResult = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if pressResult == .success { return }
        guard pressResult == .actionUnsupported || pressResult == .notImplemented else {
            throw MenuBarActionError.accessibility(pressResult)
        }

        let showMenuResult = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        if showMenuResult == .success { return }
        guard showMenuResult != .actionUnsupported, showMenuResult != .notImplemented else {
            throw MenuBarActionError.unsupported
        }
        throw MenuBarActionError.accessibility(showMenuResult)
    }
}

private extension AXMenuBarClient {
    struct ItemAttributes {
        let title: String?
        let description: String?
        let help: String?
        let identifier: String?
        let role: String?
    }

    func itemAttributes(from element: AXUIElement) -> ItemAttributes {
        ItemAttributes(
            title: stringAttribute(kAXTitleAttribute as CFString, from: element),
            description: stringAttribute(kAXDescriptionAttribute as CFString, from: element),
            help: stringAttribute(kAXHelpAttribute as CFString, from: element),
            identifier: stringAttribute(kAXIdentifierAttribute as CFString, from: element),
            role: stringAttribute(kAXRoleAttribute as CFString, from: element)
        )
    }

    /// `kAXExtrasMenuBarAttribute` is normally a single AX element. Some
    /// implementations expose it as an array, so probe the count first and
    /// use the bounded range API instead of receiving an unbounded CFArray.
    func menuBarRoots(from applicationElement: AXUIElement) -> (
        elements: [AXUIElement],
        error: AXError
    ) {
        AXUIElementSetMessagingTimeout(
            applicationElement,
            AXDiscoveryLimits.discoveryMessagingTimeout
        )
        var availableCount: CFIndex = 0
        let countResult = AXUIElementGetAttributeValueCount(
            applicationElement,
            kAXExtrasMenuBarAttribute as CFString,
            &availableCount
        )

        if countResult == .success {
            guard availableCount > 0 else { return ([], .success) }
            let requestedCount = min(
                availableCount,
                CFIndex(AXDiscoveryLimits.maximumRootsPerApplication)
            )
            var rawRoots: CFArray?
            let copyResult = AXUIElementCopyAttributeValues(
                applicationElement,
                kAXExtrasMenuBarAttribute as CFString,
                0,
                requestedCount,
                &rawRoots
            )
            guard copyResult == .success, let rawRoots else {
                return ([], copyResult)
            }
            return (
                elements(from: rawRoots, limit: AXDiscoveryLimits.maximumRootsPerApplication),
                .success
            )
        }

        guard countResult == .illegalArgument else {
            return ([], countResult)
        }

        var rawMenuBar: CFTypeRef?
        let copyResult = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXExtrasMenuBarAttribute as CFString,
            &rawMenuBar
        )
        guard copyResult == .success, let rawMenuBar else {
            return ([], copyResult)
        }
        guard CFGetTypeID(rawMenuBar) == AXUIElementGetTypeID() else {
            return ([], .illegalArgument)
        }
        return ([unsafeDowncast(rawMenuBar, to: AXUIElement.self)], .success)
    }

    func collectMenuBarItems(
        from element: AXUIElement,
        depth: Int,
        visited: inout Set<CFHashCode>,
        remainingNodeBudget: inout Int,
        clock: ContinuousClock,
        deadline: ContinuousClock.Instant,
        results: inout [AXUIElement]
    ) {
        guard depth <= 5,
              remainingNodeBudget > 0,
              clock.now < deadline,
              results.count < AXDiscoveryLimits.maximumItemsPerApplication
        else { return }
        remainingNodeBudget -= 1
        let hash = CFHash(element)
        guard visited.insert(hash).inserted else { return }

        if stringAttribute(kAXRoleAttribute as CFString, from: element) == kAXMenuBarItemRole as String {
            results.append(element)
            return
        }

        for child in children(of: element) {
            collectMenuBarItems(
                from: child,
                depth: depth + 1,
                visited: &visited,
                remainingNodeBudget: &remainingNodeBudget,
                clock: clock,
                deadline: deadline,
                results: &results
            )
        }
    }

    func children(of element: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(element, AXDiscoveryLimits.discoveryMessagingTimeout)
        var availableCount: CFIndex = 0
        guard AXUIElementGetAttributeValueCount(
            element,
            kAXChildrenAttribute as CFString,
            &availableCount
        ) == .success,
        availableCount > 0
        else {
            return []
        }
        let requestedCount = min(
            availableCount,
            CFIndex(AXDiscoveryLimits.maximumChildrenPerNode)
        )
        var rawChildren: CFArray?
        guard AXUIElementCopyAttributeValues(
            element,
            kAXChildrenAttribute as CFString,
            0,
            requestedCount,
            &rawChildren
        ) == .success,
        let rawChildren
        else {
            return []
        }
        return elements(from: rawChildren, limit: AXDiscoveryLimits.maximumChildrenPerNode)
    }

    func elements(from value: CFTypeRef, limit: Int) -> [AXUIElement] {
        guard limit > 0 else { return [] }
        if CFGetTypeID(value) == AXUIElementGetTypeID() {
            return [unsafeDowncast(value, to: AXUIElement.self)]
        }

        guard CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }

        let array = unsafeDowncast(value, to: CFArray.self)
        return (0..<min(CFArrayGetCount(array), limit)).compactMap { index in
            guard let pointer = CFArrayGetValueAtIndex(array, index) else { return nil }
            let candidate = Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
            guard CFGetTypeID(candidate) == AXUIElementGetTypeID() else { return nil }
            return unsafeDowncast(candidate, to: AXUIElement.self)
        }
    }

    func attribute(_ name: CFString, from element: AXUIElement) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, AXDiscoveryLimits.discoveryMessagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name, &value) == .success else {
            return nil
        }
        return value
    }

    func stringAttribute(_ name: CFString, from element: AXUIElement) -> String? {
        AXDiscoveryLimits.sanitized(attribute(name, from: element) as? String)
    }

    func boolAttribute(_ name: CFString, from element: AXUIElement) -> Bool? {
        attribute(name, from: element) as? Bool
    }

    func frame(of element: AXUIElement) -> CGRect? {
        guard
            let rawPosition = attribute(kAXPositionAttribute as CFString, from: element),
            let rawSize = attribute(kAXSizeAttribute as CFString, from: element),
            CFGetTypeID(rawPosition) == AXValueGetTypeID(),
            CFGetTypeID(rawSize) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionValue = unsafeDowncast(rawPosition, to: AXValue.self)
        let sizeValue = unsafeDowncast(rawSize, to: AXValue.self)
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(positionValue, .cgPoint, &position),
            AXValueGetValue(sizeValue, .cgSize, &size)
        else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap { value in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { return nil }
            return value
        }.first
    }

    func shouldReport(_ error: AXError) -> Bool {
        switch error {
        case .noValue, .attributeUnsupported, .notImplemented:
            false
        default:
            true
        }
    }

    func message(for error: AXError) -> String {
        switch error {
        case .apiDisabled:
            "Accessibility権限がありません"
        case .cannotComplete:
            "対象アプリが応答しませんでした"
        case .invalidUIElement, .invalidUIElementObserver:
            "対象項目が無効になりました"
        default:
            "項目を取得できませんでした"
        }
    }

    func deadlineFailure(
        for application: RunningApplicationDescriptor
    ) -> MenuBarDiscoveryFailure {
        MenuBarDiscoveryFailure(
            id: "\(application.pid)-discovery-time-limit",
            ownerPID: application.pid,
            ownerName: application.name,
            errorCode: AXError.cannotComplete.rawValue,
            message: "項目の取得が時間上限を超えました"
        )
    }
}
