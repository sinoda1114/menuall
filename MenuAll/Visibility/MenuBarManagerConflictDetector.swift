import AppKit
import Foundation

struct RunningMenuBarManagerApplication: Equatable, Sendable {
    let bundleIdentifier: String?
    let localizedName: String?
}

struct MenuBarManagerConflict: Equatable, Sendable {
    let bundleIdentifier: String?
    let displayName: String
}

@MainActor
protocol MenuBarManagerConflictDetecting {
    func runningConflicts() -> [MenuBarManagerConflict]
}

/// 複数のアプリが同時にメニューバーの境界を管理する状態を防ぐ。
@MainActor
final class MenuBarManagerConflictDetector: MenuBarManagerConflictDetecting {
    private let applicationsProvider: () -> [RunningMenuBarManagerApplication]
    private let ownBundleIdentifier: String?

    init(
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationsProvider: @escaping () -> [RunningMenuBarManagerApplication] = {
            NSWorkspace.shared.runningApplications.map {
                RunningMenuBarManagerApplication(
                    bundleIdentifier: $0.bundleIdentifier,
                    localizedName: $0.localizedName
                )
            }
        }
    ) {
        self.ownBundleIdentifier = ownBundleIdentifier
        self.applicationsProvider = applicationsProvider
    }

    func runningConflicts() -> [MenuBarManagerConflict] {
        Self.detect(
            in: applicationsProvider(),
            excludingBundleIdentifier: ownBundleIdentifier
        )
    }

    nonisolated static func detect(
        in applications: [RunningMenuBarManagerApplication],
        excludingBundleIdentifier: String? = nil
    ) -> [MenuBarManagerConflict] {
        var seen = Set<String>()

        return applications.compactMap { application in
            if let excludingBundleIdentifier,
               application.bundleIdentifier == excludingBundleIdentifier {
                return nil
            }

            guard let canonicalName = knownManagerName(for: application) else {
                return nil
            }
            let displayName = AXDiscoveryLimits.sanitized(application.localizedName)?.nilIfBlank
                ?? canonicalName
            let identity = application.bundleIdentifier?.lowercased() ?? displayName.lowercased()
            guard seen.insert(identity).inserted else { return nil }

            return MenuBarManagerConflict(
                bundleIdentifier: application.bundleIdentifier,
                displayName: displayName
            )
        }
    }

    private nonisolated static func knownManagerName(
        for application: RunningMenuBarManagerApplication
    ) -> String? {
        if let bundleIdentifier = AXDiscoveryLimits.sanitized(
            application.bundleIdentifier
        )?.lowercased() {
            if bundleIdentifier == "com.jordanbaird.ice" { return "Ice" }
            if bundleIdentifier == "com.dwarvesv.minimalbar" { return "Hidden Bar" }
            if bundleIdentifier == "com.mortennn.dozer" { return "Dozer" }
            if bundleIdentifier == "com.matthewpalmer.vanilla" { return "Vanilla" }
            if bundleIdentifier == "com.surteesstudios.bartender"
                || bundleIdentifier.hasPrefix("com.surteesstudios.bartender") {
                return "Bartender"
            }
        }

        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}
