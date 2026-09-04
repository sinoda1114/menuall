import AppKit
import ServiceManagement
import SwiftUI

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
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    var body: some View {
        Form {
            Section("一般") {
                Toggle("ログイン時にMenuAllを起動", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLoginItem(enabled: enabled)
                    }

                Picker("表示形式", selection: $displayModeRaw) {
                    ForEach(MenuAllDisplayMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.radioGroup)

                if let loginItemError {
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
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "ログイン項目を変更できませんでした。システム設定を確認してください。"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
