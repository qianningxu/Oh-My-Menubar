@testable import AppBundle
import Common
import Foundation
import XCTest

@MainActor
final class ConfigBootstrapTest: XCTestCase {
    func testStarterConfigParses() {
        let (parsedConfig, errors) = parseConfig(starterConfigText())
        assertEquals(errors, [])

        let bindings: [(String, String)] = parsedConfig.modes["main"]?.bindings.values.map {
            ($0.descriptionWithKeyNotation, $0.commands.prettyDescription)
        } ?? []
        let bindingMap: [String: String] = Dictionary(uniqueKeysWithValues: bindings)

        XCTAssertEqual(bindingMap["alt-space"], "layout horizontal vertical")
        XCTAssertEqual(bindingMap["ctrl-f"], "open-sidebar")
        XCTAssertEqual(bindingMap["alt-b"], "open-sidebar")
        XCTAssertEqual(bindingMap["alt-h"], "focus left")
        XCTAssertEqual(bindingMap["alt-1"], "tab 1")
        XCTAssertEqual(bindingMap["alt-0"], "tab 10")
        XCTAssertEqual(bindingMap["alt-tab"], "tab next")
        XCTAssertEqual(bindingMap["alt-shift-tab"], "tab prev")
        XCTAssertEqual(bindingMap["alt-n"], "new-tab")
        XCTAssertEqual(bindingMap["alt-shift-h"], "move left")
        XCTAssertEqual(bindingMap["cmd-shift-h"], "join-with left")
        XCTAssertEqual(bindingMap["alt-cmd-j"], "swap down")
        XCTAssertEqual(bindingMap["alt-cmd-k"], "swap up")
        XCTAssertEqual(bindingMap["cmd-shift-i"], "balance-sizes")
        XCTAssertNil(bindingMap["ctrl-1"])
        XCTAssertNil(bindingMap["ctrl-0"])
        XCTAssertEqual(bindingMap["ctrl-t"], "tab 15")
        XCTAssertEqual(bindingMap["ctrl-h"], "tab prev")
        XCTAssertEqual(bindingMap["cmd-ctrl-h"], "tab prev")
        XCTAssertEqual(bindingMap["alt-shift-1"], "move-node-to-tab 1")
        XCTAssertEqual(bindingMap["alt-shift-0"], "move-node-to-tab 10")
        XCTAssertNil(bindingMap["ctrl-shift-1"])
        XCTAssertNil(bindingMap["ctrl-shift-2"])
        XCTAssertNil(bindingMap["ctrl-shift-0"])
        XCTAssertNil(bindingMap["ctrl-shift-n"])
        XCTAssertEqual(bindingMap["ctrl-shift-h"], "move-node-to-tab --focus-follows-window prev")
        XCTAssertEqual(bindingMap["alt-shift-t"], "layout floating tiling")
        XCTAssertEqual(bindingMap["alt-shift-m"], "fullscreen")
        XCTAssertNil(bindingMap["ctrl-cmd-shift-h"])
        XCTAssertNil(bindingMap["alt-cmd-h"])
        XCTAssertNil(bindingMap["alt-cmd-l"])
        XCTAssertNil(bindingMap["alt-slash"])
        XCTAssertNil(bindingMap["alt-comma"])
        XCTAssertFalse(parsedConfig.windowTabs.enabled)
        XCTAssertEqual(parsedConfig.windowTabs.height, 36)
        XCTAssertTrue(parsedConfig.workspaceSidebar.enabled)
        XCTAssertEqual(parsedConfig.workspaceSidebar.width, 212)
        XCTAssertEqual(
            parsedConfig.workspaceSidebar.resolvedWidgets.filter(\.enabled).map(\.type),
            [.builtInTodayFocus],
        )
        XCTAssertTrue(parsedConfig.autoReloadConfig)
        if case .constant(let horizontalGap) = parsedConfig.gaps.inner.horizontal {
            XCTAssertEqual(horizontalGap, 8)
        } else {
            XCTFail("Expected constant horizontal gap")
        }
        if case .constant(let verticalGap) = parsedConfig.gaps.inner.vertical {
            XCTAssertEqual(verticalGap, 8)
        } else {
            XCTFail("Expected constant vertical gap")
        }
        if case .constant(let outerLeftGap) = parsedConfig.gaps.outer.left {
            XCTAssertEqual(outerLeftGap, 8)
        } else {
            XCTFail("Expected constant outer left gap")
        }
        XCTAssertEqual(parsedConfig.configVersion, 3)
        XCTAssertTrue(parsedConfig.enableProjects)
    }

    func testEnsureBootstrapConfigCopiesLegacyConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let legacyUrl = tempDir.appending(path: "legacy.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let legacyText = """
            config-version = 2

            [mode.main.binding]
            alt-h = 'focus left'
            """
        try legacyText.write(to: legacyUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [legacyUrl],
        )

        XCTAssertTrue(didMaterialize)
        let copiedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertEqual(copiedText, legacyText)
    }

    func testEnsureBootstrapConfigPrefersFirstLegacyConfigWithoutFailing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let preferredLegacyUrl = tempDir.appending(path: "preferred.toml")
        let secondaryLegacyUrl = tempDir.appending(path: "secondary.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let preferredText = """
            config-version = 2

            [mode.main.binding]
            alt-h = 'focus left'
            """
        let secondaryText = """
            config-version = 2

            [mode.main.binding]
            alt-l = 'focus right'
            """
        try preferredText.write(to: preferredLegacyUrl, atomically: true, encoding: .utf8)
        try secondaryText.write(to: secondaryLegacyUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [preferredLegacyUrl, secondaryLegacyUrl],
        )

        XCTAssertTrue(didMaterialize)
        let copiedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertEqual(copiedText, preferredText)
    }

    func testEnsureBootstrapConfigImportsAerospaceConfigWhenNoWinMuxConfigExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "WinMuxTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let aerospaceUrl = tempDir.appending(path: "aerospace.toml")
        let targetUrl = tempDir.appending(path: "winmux.toml")
        let aerospaceText = """
            start-at-login = false
            default-root-container-layout = 'accordion'
            accordion-padding = 22
            window-tabs.enabled = false
            exec-on-workspace-change = ['/bin/sh', '-c', 'echo $AEROSPACE_FOCUSED_WORKSPACE $AEROSPACE_PREV_WORKSPACE $AEROSPACE_WORKSPACE']

            [workspace-sidebar]
            enabled = false

            [mode.main.binding]
            alt-h = 'layout accordion tiles'
            alt-j = 'layout h_accordion v_accordion'
            alt-l = 'exec-and-forget echo $AEROSPACE_WINDOW_ID $AEROSPACE_FOCUSED_WORKSPACE $AEROSPACE_PREV_WORKSPACE $AEROSPACE_WORKSPACE'
            alt-1 = 'workspace 1'
            alt-shift-1 = 'move-node-to-workspace 1'
            """
        try aerospaceText.write(to: aerospaceUrl, atomically: true, encoding: .utf8)

        let didMaterialize = try materializeBootstrapConfigIfNeeded(
            targetUrl: targetUrl,
            existingLegacyUrls: [],
            aerospaceImportUrl: aerospaceUrl,
        )

        XCTAssertTrue(didMaterialize)
        let migratedText = try String(contentsOf: targetUrl, encoding: .utf8)
        XCTAssertTrue(migratedText.contains("# Migrated from AeroSpace config by WinMux."))
        XCTAssertTrue(migratedText.contains("default-root-container-layout = 'tiles'"))
        XCTAssertTrue(migratedText.contains("folder-padding = 30"))
        XCTAssertTrue(migratedText.contains("window-tabs.enabled = false"))
        XCTAssertTrue(migratedText.contains("[tab-sidebar]"))
        XCTAssertTrue(migratedText.contains("enabled = true"))
        XCTAssertTrue(migratedText.contains("layout tiles tiles"))
        XCTAssertTrue(migratedText.contains("layout h_tiles v_tiles"))
        XCTAssertTrue(migratedText.contains("alt-1 = 'tab 1'"))
        XCTAssertTrue(migratedText.contains("alt-shift-1 = 'move-node-to-tab 1'"))
        XCTAssertTrue(migratedText.contains("$WINMUX_WINDOW_ID"))
        XCTAssertTrue(migratedText.contains("$WINMUX_FOCUSED_TAB $WINMUX_PREV_TAB $WINMUX_TAB"))
        XCTAssertFalse(migratedText.contains("exec-on-workspace-change"))
        XCTAssertFalse(migratedText.contains("move-node-to-workspace"))
        XCTAssertFalse(migratedText.contains("'workspace 1'"))
        XCTAssertFalse(migratedText.contains("WINMUX_WORKSPACE"))
        XCTAssertFalse(migratedText.contains("WINMUX_FOCUSED_WORKSPACE"))
        XCTAssertFalse(migratedText.contains("WINMUX_PREV_WORKSPACE"))
        XCTAssertFalse(migratedText.contains("accordion"))
        XCTAssertFalse(migratedText.contains("AEROSPACE_"))

        let (parsedConfig, errors) = parseConfig(migratedText)
        XCTAssertEqual(errors.descriptions, [])
        XCTAssertTrue(parsedConfig.workspaceSidebar.enabled)
        XCTAssertFalse(parsedConfig.windowTabs.enabled)
        XCTAssertEqual(parsedConfig.configVersion, 3)
        XCTAssertEqual(parsedConfig.modes[mainModeId]?.bindings.values.map(\.descriptionWithKeyNotation).sorted(), ["alt-1", "alt-h", "alt-j", "alt-l", "alt-shift-1"])
    }
}
