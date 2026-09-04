import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor
protocol LoginItemControlling {
    var isEnabled: Bool { get }
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
struct SystemLoginItemController: LoginItemControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
@Observable
final class LoginItemSettingsModel {
    static let approvalMessage = "ログイン時の起動をシステム設定で許可してください。"
    static let failureMessage = "ログイン項目を変更できませんでした。システム設定を確認してください。"

    private let controller: any LoginItemControlling
    private(set) var isEnabled: Bool
    private(set) var requiresApproval: Bool
    private(set) var errorMessage: String? = nil

    init(controller: any LoginItemControlling = SystemLoginItemController()) {
        self.controller = controller
        isEnabled = controller.isEnabled
        requiresApproval = controller.requiresApproval
        synchronizeStatus()
    }

    func refresh() {
        synchronizeStatus()
    }

    func request(_ enabled: Bool) {
        do {
            try controller.setEnabled(enabled)
            synchronizeStatus()
        } catch {
            synchronizeStatus(fallbackError: Self.failureMessage)
        }
    }

    private func synchronizeStatus(fallbackError: String? = nil) {
        isEnabled = controller.isEnabled
        requiresApproval = controller.requiresApproval
        errorMessage = requiresApproval ? Self.approvalMessage : fallbackError
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    convenience init(store: MenuBarStore, permissionService: AccessibilityPermissionService) {
        let rootView = MenuAllSettingsView(
            store: store,
            onOpenAccessibilitySettings: permissionService.openSystemSettings,
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "MenuAll 設定"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 470, height: 500))
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
    }

    func present() {
        guard let window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MenuAllSettingsView: View {
    @Bindable var store: MenuBarStore
    let onOpenAccessibilitySettings: () -> Void
    let onQuit: () -> Void

    @AppStorage("displayMode") private var displayModeRaw = MenuAllDisplayMode.iconAndName.rawValue
    @AppStorage("prioritizeHidden") private var prioritizeHidden = true
    @AppStorage("showSystemItems") private var showSystemItems = false
    @State private var loginItemSettings = LoginItemSettingsModel()

    var body: some View {
        Form {
            Section("一般") {
                Toggle("ログイン時にMenuAllを起動", isOn: launchAtLoginBinding)

                Picker("表示形式", selection: $displayModeRaw) {
                    ForEach(MenuAllDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if let loginItemError = loginItemSettings.errorMessage {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("表示する項目") {
                Toggle("隠れている項目を先に表示", isOn: $prioritizeHidden)
                Toggle("macOSのシステム項目を表示", isOn: $showSystemItems)
            }

            Section("権限") {
                LabeledContent("アクセシビリティ") {
                    Label(
                        store.isAccessibilityTrusted ? "許可" : "未許可",
                        systemImage: store.isAccessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
                    )
                    .foregroundStyle(store.isAccessibilityTrusted ? .green : .orange)
                }
                Button("システム設定を開く", action: onOpenAccessibilitySettings)
            }

            Section {
                LabeledContent("MenuAll バージョン", value: version)
                HStack {
                    Spacer()
                    Button("MenuAllを終了", action: onQuit)
                }
            }
        }
        .formStyle(.grouped)
        .padding(18)
        .frame(width: 470, height: 500)
        .onAppear { loginItemSettings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItemSettings.refresh()
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemSettings.isEnabled },
            set: { enabled in loginItemSettings.request(enabled) }
        )
    }
}
