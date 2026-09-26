import AppKit
import ApplicationServices
import Foundation

@MainActor
protocol AccessibilityPermissionProviding: AnyObject {
    var isTrusted: Bool { get }

    @discardableResult
    func recheckPermission() -> Bool

    func openSystemSettings()
}

@MainActor
final class AccessibilityPermissionService: AccessibilityPermissionProviding {
    private var authorizationCheckIndex = 0

    var isTrusted: Bool {
        if let override = LaunchEnvironment.accessibilityAuthorizationOverride(
            atCheckIndex: authorizationCheckIndex
        ) {
            return override == .granted
        }
        return AXIsProcessTrusted()
    }

    @discardableResult
    func recheckPermission() -> Bool {
        authorizationCheckIndex += 1
        return isTrusted
    }

    @discardableResult
    func requestPermissionPrompt() -> Bool {
        if LaunchEnvironment.isUITesting {
            return isTrusted
        }
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [
            promptKey: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSystemSettings() {
        if LaunchEnvironment.shouldSuppressExternalNavigation {
            return
        }
        requestPermissionPrompt()

        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }

        AppLogger.accessibility.error("アクセシビリティ設定画面を開けませんでした")
    }
}
