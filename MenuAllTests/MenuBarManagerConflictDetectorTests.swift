import Testing
@testable import MenuAll

@Suite("MenuBarManagerConflictDetector")
struct MenuBarManagerConflictDetectorTests {
    @Test("既知のメニューバー管理アプリだけを検出する")
    func detectsKnownManagers() {
        let applications = [
            RunningMenuBarManagerApplication(
                bundleIdentifier: "com.jordanbaird.Ice",
                localizedName: "Ice"
            ),
            RunningMenuBarManagerApplication(
                bundleIdentifier: "com.example.Unrelated",
                localizedName: "Unrelated"
            ),
            RunningMenuBarManagerApplication(
                bundleIdentifier: "com.dwarvesv.minimalbar",
                localizedName: "Hidden Bar"
            ),
        ]

        let conflicts = MenuBarManagerConflictDetector.detect(in: applications)

        #expect(conflicts.map(\.displayName) == ["Ice", "Hidden Bar"])
    }

    @Test("表示名だけを既知アプリに似せても競合として停止しない")
    func rejectsSpoofedManagerNameWithoutKnownBundleID() {
        let conflicts = MenuBarManagerConflictDetector.detect(in: [
            RunningMenuBarManagerApplication(
                bundleIdentifier: nil,
                localizedName: "Bartender 5"
            ),
        ])

        #expect(conflicts.isEmpty)
    }

    @Test("MenuAll自身は競合として扱わない")
    func excludesCurrentApplication() {
        let conflicts = MenuBarManagerConflictDetector.detect(
            in: [
                RunningMenuBarManagerApplication(
                    bundleIdentifier: "com.sinoda.MenuAll",
                    localizedName: "MenuAll"
                ),
            ],
            excludingBundleIdentifier: "com.sinoda.MenuAll"
        )

        #expect(conflicts.isEmpty)
    }
}
