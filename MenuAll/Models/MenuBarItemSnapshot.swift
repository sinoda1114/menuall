import CoreGraphics
import Foundation

enum MenuBarItemVisibility: String, CaseIterable, Equatable, Sendable {
    case hidden
    case visible
    case unknown
}

struct MenuBarItemSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let ownerPID: Int32
    let ownerName: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let title: String
    let hasExplicitName: Bool
    let detail: String?
    let role: String?
    let visibility: MenuBarItemVisibility
    let actions: [String]
    let frame: CGRect?
    let failureReason: String?

    init(
        id: String,
        ownerPID: Int32,
        ownerName: String,
        bundleIdentifier: String? = nil,
        bundleURL: URL? = nil,
        title: String,
        hasExplicitName: Bool = true,
        detail: String? = nil,
        role: String? = nil,
        visibility: MenuBarItemVisibility = .unknown,
        actions: [String] = [],
        frame: CGRect? = nil,
        failureReason: String? = nil
    ) {
        self.id = id
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.title = title
        self.hasExplicitName = hasExplicitName
        self.detail = detail
        self.role = role
        self.visibility = visibility
        self.actions = actions
        self.frame = frame
        self.failureReason = failureReason
    }

    func replacingVisibility(with visibility: MenuBarItemVisibility) -> Self {
        Self(
            id: id,
            ownerPID: ownerPID,
            ownerName: ownerName,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL,
            title: title,
            hasExplicitName: hasExplicitName,
            detail: detail,
            role: role,
            visibility: visibility,
            actions: actions,
            frame: frame,
            failureReason: failureReason
        )
    }
}
