@testable import AppBundle
import AppKit
import Common
import XCTest

extension ConfigTest {
    func testUpdateWorkspaceSidebarLabelConfigAddsSectionWhenMissing() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("[tab-sidebar.tab-labels]"))
        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
    }

    func testUpdateWorkspaceSidebarLabelConfigReplacesExistingLabel() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [workspace-sidebar.workspace-labels]
            "1" = "Old"
            "2" = "Web"
            """,
            workspaceName: "1",
            label: "Code",
        )

        XCTAssertTrue(updated.contains("\"1\" = \"Code\""))
        XCTAssertFalse(updated.contains("\"1\" = \"Old\""))
        XCTAssertTrue(updated.contains("\"2\" = \"Web\""))
        XCTAssertTrue(updated.contains("[tab-sidebar.tab-labels]"))
        XCTAssertFalse(updated.contains("[workspace-sidebar.workspace-labels]"))
    }

    func testUpdateWorkspaceSidebarLabelConfigAddsNewLabelWithoutExtraBlankLine() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [tab-sidebar.workspace-labels]
            "1" = "Code"
            """,
            workspaceName: "2",
            label: "Web",
        )

        XCTAssertEqual(
            updated,
            """
            [tab-sidebar.tab-labels]
            "1" = "Code"
            "2" = "Web"
            """,
        )
    }

    func testUpdateWorkspaceSidebarLabelConfigRemovesLastLabelSection() {
        let updated = updateWorkspaceSidebarLabelConfig(
            in: """
            [tab-sidebar.workspace-labels]
            "1" = "Code"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            workspaceName: "1",
            label: nil,
        )

        XCTAssertFalse(updated.contains("[tab-sidebar.workspace-labels]"))
        XCTAssertFalse(updated.contains("[tab-sidebar.tab-labels]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigAddsAndReplacesColor() {
        let added = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [tab-sidebar]
                enabled = true
            """,
            projectId: "project-1",
            colorHex: "#60A5FA",
        )

        XCTAssertTrue(added.contains("[tab-sidebar.project-colors]"))
        XCTAssertTrue(added.contains("\"project-1\" = \"#60A5FA\""))

        let replaced = updateWorkspaceSidebarProjectColorConfig(
            in: added,
            projectId: "project-1",
            colorHex: "#F87171",
        )

        XCTAssertTrue(replaced.contains("\"project-1\" = \"#F87171\""))
        XCTAssertFalse(replaced.contains("\"project-1\" = \"#60A5FA\""))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigRemovesLastColorSection() {
        let updated = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [tab-sidebar.project-colors]
            "project-1" = "#60A5FA"

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            projectId: "project-1",
            colorHex: nil,
        )

        XCTAssertFalse(updated.contains("[tab-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarProjectColorConfigMigratesLegacySectionName() {
        let updated = updateWorkspaceSidebarProjectColorConfig(
            in: """
            [workspace-sidebar.project-colors]
            "project-1" = "#60A5FA"
            """,
            projectId: "project-1",
            colorHex: "#F87171",
        )

        XCTAssertTrue(updated.contains("[tab-sidebar.project-colors]"))
        XCTAssertFalse(updated.contains("[workspace-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("\"project-1\" = \"#F87171\""))
    }

    func testProjectAndFolderMetadataEditsUseSeparateSections() {
        let withProject = updateWorkspaceSidebarProjectLabelConfig(
            in: "config-version = 3",
            projectId: "project-1",
            label: "Work"
        )
        let withFolder = updateWorkspaceSidebarFolderLabelConfig(
            in: withProject,
            folderId: "folder-1",
            label: "Backend"
        )
        let withProjectColor = updateWorkspaceSidebarProjectColorConfig(
            in: withFolder,
            projectId: "project-1",
            colorHex: "#60A5FA"
        )
        let updated = updateWorkspaceSidebarFolderColorConfig(
            in: withProjectColor,
            folderId: "folder-1",
            colorHex: "#F87171"
        )

        XCTAssertTrue(updated.contains("[tab-sidebar.project-labels]"))
        XCTAssertTrue(updated.contains("[tab-sidebar.folder-labels]"))
        XCTAssertTrue(updated.contains("[tab-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("[tab-sidebar.folder-colors]"))
    }

    func testSidebarConfigEditMigratesAllLegacyHeadersBeforeAddingFolderMetadata() {
        let updated = updateWorkspaceSidebarProjectLabelConfig(
            in: """
            [workspace-sidebar]
                enabled = true

            [workspace-sidebar.project-colors]
            "default" = "#9B8FC4"
            """,
            projectId: "project-1",
            label: "Work",
        )

        XCTAssertTrue(updated.contains("[tab-sidebar]"))
        XCTAssertTrue(updated.contains("[tab-sidebar.project-colors]"))
        XCTAssertTrue(updated.contains("[tab-sidebar.project-labels]"))
        XCTAssertFalse(updated.contains("[workspace-sidebar"))
    }

    func testUpdateWindowTabLabelConfigAddsReplacesEscapesAndRemoves() {
        let key = #"com.example.App|Docs "Alpha" \ Main"#
        let added = updateWindowTabLabelConfig(
            in: """
            [window-tabs]
                enabled = true
            """,
            key: key,
            label: #"Build "One" \ Shell"#,
        )

        XCTAssertTrue(added.contains("[window-tabs.tab-labels]"))
        XCTAssertTrue(added.contains(#""com.example.App|Docs \"Alpha\" \\ Main" = "Build \"One\" \\ Shell""#))

        let replaced = updateWindowTabLabelConfig(
            in: added,
            key: key,
            label: "Build Two",
        )

        XCTAssertTrue(replaced.contains(#""com.example.App|Docs \"Alpha\" \\ Main" = "Build Two""#))
        XCTAssertFalse(replaced.contains("Build \\\"One\\\""))

        let removed = updateWindowTabLabelConfig(
            in: replaced,
            key: key,
            label: nil,
        )

        XCTAssertFalse(removed.contains("[window-tabs.tab-labels]"))
        XCTAssertTrue(removed.contains("[window-tabs]"))
    }

    func testUpdateWorkspaceSidebarMenuBarReserveConfigAddsValueToExistingSection() {
        let updated = updateWorkspaceSidebarMenuBarReserveConfig(
            in: """
            [workspace-sidebar]
                enabled = true
                width = 240

            [mode.main.binding]
                alt-h = 'focus left'
            """,
            height: 32,
        )

        XCTAssertTrue(updated.contains("[tab-sidebar]\n    menu-bar-reserve-height = 32\n    enabled = true"))
        XCTAssertTrue(updated.contains("[mode.main.binding]"))
    }

    func testUpdateWorkspaceSidebarMenuBarReserveConfigReplacesValueAndPreservesComment() {
        let updated = updateWorkspaceSidebarMenuBarReserveConfig(
            in: """
            [tab-sidebar]
                menu-bar-reserve-height = 28 # visible menu bar
                enabled = true
            """,
            height: 0,
        )

        XCTAssertTrue(updated.contains("menu-bar-reserve-height = 0 # visible menu bar"))
        XCTAssertFalse(updated.contains("menu-bar-reserve-height = 28"))
    }

    func testUpdateWorkspaceSidebarProjectDeletionActionReplacesValueAndPreservesComment() {
        let updated = updateWorkspaceSidebarProjectDeletionActionConfig(
            in: """
            [workspace-sidebar]
                project-deletion-action = 'move-windows-to-fallback' # legacy
                enabled = true
            """,
            action: .closeWindows,
        )

        XCTAssertTrue(updated.contains("folder-deletion-action = 'close-windows' # legacy"))
        XCTAssertFalse(updated.contains("project-deletion-action"))
        XCTAssertFalse(updated.contains("move-windows-to-fallback"))
    }

}
