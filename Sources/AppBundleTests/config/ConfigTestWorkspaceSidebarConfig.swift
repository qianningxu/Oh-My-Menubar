@testable import AppBundle
import AppKit
import Common
import XCTest

extension ConfigTest {
    func testParseWorkspaceSidebar() {
        let (parsed, errors) = parseConfig(
            """
            config-version = 3

            [tab-sidebar]
                enabled = true
                enable-focus = true
                width = 280
                monitor = ['secondary', 2]
                show-status-pills = false
                show-date = false
                menu-bar-reserve-height = 30
                folder-deletion-action = 'move-windows-to-fallback'

            [tab-sidebar.tab-labels]
                1 = 'Code'
                2 = 'Web'

            [tab-sidebar.folder-labels]
                default = 'Personal'

            [tab-sidebar.folder-colors]
                default = '#ff8844'
            """,
        )
        assertEquals(errors, [])
        assertEquals(
            parsed.workspaceSidebar,
            WorkspaceSidebarConfig(
                enabled: true,
                enableFocus: true,
                collapsedWidth: 44,
                width: 280,
                monitor: [.secondary, .sequenceNumber(2)],
                showStatusPills: false,
                showDate: false,
                widgets: nil,
                menuBarReserveHeight: 30,
                projectDeletionAction: .moveWindowsToFallback,
                workspaceLabels: ["1": "Code", "2": "Web"],
                folderLabels: ["default": "Personal"],
                folderColors: ["default": "#FF8844"],
            ),
        )

        let (_, widthErrors) = parseConfig(
            """
            [tab-sidebar]
                collapsed-width = 0
                width = 0
                menu-bar-reserve-height = -1
            """,
        )
        assertEquals(widthErrors.descriptions, [
            "tab-sidebar.collapsed-width: Must be greater than 0",
            "tab-sidebar.menu-bar-reserve-height: Must be greater than or equal to 0",
            "tab-sidebar.width: Must be greater than 0",
        ])

        let (_, colorErrors) = parseConfig(
            """
            [tab-sidebar.folder-colors]
                default = 'not-a-color'
            """,
        )
        assertEquals(colorErrors.descriptions, [
            "tab-sidebar.folder-colors.default: Must be a hex color like '#RRGGBB'",
        ])

        let (_, actionErrors) = parseConfig(
            """
            [tab-sidebar]
                folder-deletion-action = 'explode'
            """,
        )
        assertEquals(actionErrors.descriptions, [
            "tab-sidebar.folder-deletion-action: Possible values: close-windows, move-windows-to-fallback",
        ])
    }

    func testParseWorkspaceSidebarLegacyProjectFolderAliases() {
        let (parsed, errors) = parseConfig(
            """
            [workspace-sidebar]
                project-deletion-action = 'move-windows-to-fallback'

            [workspace-sidebar.project-labels]
                default = 'Legacy'

            [workspace-sidebar.project-colors]
                default = '#60a5fa'
            """,
        )

        assertEquals(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.projectDeletionAction, .moveWindowsToFallback)
        XCTAssertEqual(parsed.workspaceSidebar.folderLabels, ["default": "Legacy"])
        XCTAssertEqual(parsed.workspaceSidebar.folderColors, ["default": "#60A5FA"])
        XCTAssertEqual(parsed.workspaceSidebar.projectLabels, ["default": "Main"])
        XCTAssertEqual(parsed.workspaceSidebar.projectColors, [:])
    }

    func testParseWorkspaceSidebarLegacyWorkspaceLabelAlias() {
        let (parsed, errors) = parseConfig(
            """
            [workspace-sidebar.workspace-labels]
                1 = 'Code'
            """,
        )

        assertEquals(errors, [])
        XCTAssertEqual(parsed.workspaceSidebar.workspaceLabels, ["1": "Code"])
    }

    func testParseWorkspaceSidebarRejectsPrimaryAndLegacyRootTogether() {
        let (_, errors) = parseConfig(
            """
            [tab-sidebar]
                enabled = true

            [workspace-sidebar]
                enabled = false
            """,
        )

        assertEquals(errors.descriptions, [
            "tab-sidebar: Use either 'tab-sidebar' or legacy 'workspace-sidebar', not both",
        ])
    }

    func testWorkspaceSidebarDoesNotRequireThemeConfig() {
        let (parsed, errors) = parseConfig(
            """
            [tab-sidebar]
                enabled = true
                menu-bar-reserve-height = 0
            """,
        )

        assertEquals(errors, [])
        XCTAssertTrue(parsed.workspaceSidebar.enabled)
        XCTAssertEqual(parsed.workspaceSidebar.menuBarReserveHeight, 0)
    }

    func testParseWindowTabLabels() {
        let (parsed, errors) = parseConfig(
            """
            [window-tabs.tab-labels]
                "com.example.App|Docs" = "Build"
            """,
        )

        assertEquals(errors, [])
        XCTAssertEqual(parsed.windowTabs.tabLabels, ["com.example.App|Docs": "Build"])

        let (_, labelErrors) = parseConfig(
            """
            [window-tabs.tab-labels]
                "com.example.App|Docs" = 42
            """,
        )

        assertEquals(labelErrors.descriptions, [
            "window-tabs.tab-labels.com.example.App|Docs: Expected type is 'string'. But actual type is 'integer'",
        ])
    }

    @MainActor
    func testParseWorkspaceSidebarWidgets() {
        let (parsed, errors) = parseConfig(
            """
            [tab-sidebar]
                widgets = [
                    { id = 'todo-list', type = 'built-in/todo-list', enabled = true },
                    { id = 'time-date', type = 'built-in/time-date', enabled = true, show-date = false },
                    { id = 'schedule-heatmap', type = 'built-in/schedule-heatmap', enabled = true, schedule-path = '/tmp/schedule', toggl-entries-path = '/tmp/toggl/entries', deviation-path = '/tmp/deviation', days = 7 },
                    { id = 'toggl-weekly-focus', type = 'built-in/toggl-weekly-focus', enabled = true, entries-path = '/tmp/toggl/entries', target-date = '2026-09-13' },
                    { id = 'toggl-week-focus', type = 'built-in/toggl-week-focus', enabled = true, entries-path = '/tmp/toggl/entries', target-date = '2026-09-13' },
                    { id = 'period-heatmap', type = 'built-in/period-heatmap', enabled = true, entries-path = '/tmp/period' },
                    { id = 'spending-categories', type = 'built-in/spending-categories', enabled = true, entries-path = '/tmp/spending', days = 28, rotation-group = 'focus' },
                    { id = 'custom', type = 'plugin', enabled = false, bundle = 'CustomWidget.bundle' },
                ]
            """,
        )
        assertEquals(errors, [])
        assertEquals(parsed.workspaceSidebar.widgets, [
            WorkspaceSidebarWidgetConfig(
                id: "todo-list",
                type: .builtInTodoList,
                enabled: true,
            ),
            WorkspaceSidebarWidgetConfig(
                id: "time-date",
                type: .builtInTimeDate,
                enabled: true,
                showDate: false,
            ),
            WorkspaceSidebarWidgetConfig(
                id: "schedule-heatmap",
                type: .builtInScheduleHeatmap,
                enabled: true,
                showDate: true,
                schedulePath: "/tmp/schedule",
                togglEntriesPath: "/tmp/toggl/entries",
                deviationPath: "/tmp/deviation",
                days: 7,
            ),
            WorkspaceSidebarWidgetConfig(
                id: "toggl-weekly-focus",
                type: .builtInTogglWeeklyFocus,
                enabled: true,
                showDate: true,
                entriesPath: "/tmp/toggl/entries",
                targetDate: "2026-09-13",
            ),
            WorkspaceSidebarWidgetConfig(
                id: "toggl-week-focus",
                type: .builtInTogglWeekFocus,
                enabled: true,
                showDate: true,
                entriesPath: "/tmp/toggl/entries",
                targetDate: "2026-09-13",
            ),
            WorkspaceSidebarWidgetConfig(
                id: "period-heatmap",
                type: .builtInPeriodHeatmap,
                enabled: true,
                showDate: true,
                entriesPath: "/tmp/period",
            ),
            WorkspaceSidebarWidgetConfig(
                id: "spending-categories",
                type: .builtInSpendingCategories,
                enabled: true,
                showDate: true,
                entriesPath: "/tmp/spending",
                days: 28,
                rotationGroup: "focus",
            ),
            WorkspaceSidebarWidgetConfig(
                id: "custom",
                type: .plugin,
                enabled: false,
                bundle: "CustomWidget.bundle",
            ),
        ])

        let (legacyParsed, legacyErrors) = parseConfig(
            """
            [tab-sidebar]
                show-date = false
            """,
        )
        assertEquals(legacyErrors, [])
        assertEquals(legacyParsed.workspaceSidebar.resolvedWidgets, [
            WorkspaceSidebarWidgetConfig(
                id: "time-date",
                type: .builtInTimeDate,
                enabled: false,
                showDate: false,
            ),
        ])
    }

    func testParseWorkspaceSidebarWidgetErrors() {
        let (_, errors) = parseConfig(
            """
            [tab-sidebar]
                widgets = [
                    { id = 'time-date', type = 'built-in/time-date', bundle = 'Nope.bundle' },
                    { id = 'time-date', type = 'plugin' },
                    { id = 'unknown', type = 'built-in/nope' },
                    { id = 'bad-todo', type = 'built-in/todo-list', bundle = 'Nope.bundle', entries-path = '/tmp/todo' },
                    { id = 'wrong-fields', type = 'plugin', bundle = 'CustomWidget.bundle', entries-path = '/tmp/toggl/entries', schedule-path = '/tmp/schedule', toggl-entries-path = '/tmp/toggl/entries', deviation-path = '/tmp/deviation', target-date = '2026-09-13', days = 7 },
                    { id = 'bad-days', type = 'built-in/spending-categories', days = 0 },
                    { id = 'wrong-schedule-fields', type = 'built-in/schedule-heatmap', bundle = 'Nope.bundle', entries-path = '/tmp/toggl/entries' },
                    { id = 'bad-target-date', type = 'built-in/toggl-weekly-focus', target-date = '13-09-2026' },
                ]
            """,
        )
        assertEquals(errors.descriptions, [
            "tab-sidebar.widgets[0].bundle: Only plugin widgets can specify bundle",
            "tab-sidebar.widgets[1].id: Duplicate widget id 'time-date'",
            "tab-sidebar.widgets[2].type: Possible values: built-in/todo-list, built-in/tasks, built-in/time-date, built-in/today-focus, built-in/toggl-weekly-focus, built-in/toggl-week-focus, built-in/period-heatmap, built-in/spending-categories, built-in/schedule-heatmap, plugin",
            "tab-sidebar.widgets[3].bundle: Only plugin widgets can specify bundle",
            "tab-sidebar.widgets[3].entries-path: Only data widgets can specify entries-path",
            "tab-sidebar.widgets[4].entries-path: Only data widgets can specify entries-path",
            "tab-sidebar.widgets[4].schedule-path: Only schedule heatmap widgets can specify schedule-path",
            "tab-sidebar.widgets[4].toggl-entries-path: Only schedule heatmap widgets can specify toggl-entries-path",
            "tab-sidebar.widgets[4].deviation-path: Only schedule heatmap widgets can specify deviation-path",
            "tab-sidebar.widgets[4].days: Only data widgets can specify days",
            "tab-sidebar.widgets[4].target-date: Only target-date widgets can specify target-date",
            "tab-sidebar.widgets[5].days: Must be greater than 0",
            "tab-sidebar.widgets[6].bundle: Only plugin widgets can specify bundle",
            "tab-sidebar.widgets[6].entries-path: Schedule heatmap widgets use toggl-entries-path",
            "tab-sidebar.widgets[7].target-date: Must be YYYY-MM-DD",
        ])
    }

    @MainActor
    func testTodayFocusWidgetUsesLocalEntriesPathInConfigMap() {
        let previousConfig = config
        defer { config = previousConfig }

        let (parsed, errors) = parseConfig(
            """
            [tab-sidebar]
                widgets = [
                    { id = 'today-focus', type = 'built-in/today-focus', enabled = true, entries-path = '/tmp/self_data' },
                ]
            """,
        )
        assertEquals(errors, [])
        assertEquals(parsed.workspaceSidebar.widgets, [
            WorkspaceSidebarWidgetConfig(
                id: "today-focus",
                type: .builtInTodayFocus,
                enabled: true,
                showDate: true,
                entriesPath: "/tmp/self_data",
            ),
        ])

        config = parsed
        let configMap = buildConfigMap()
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "0", "entries-path"].slice).get(),
            .scalar(.string("/tmp/self_data")),
        )
    }

    @MainActor
    func testConfigMapIncludesWorkspaceSidebarWidgets() {
        let previousConfig = config
        defer { config = previousConfig }

        config = parseConfig(
            """
            [tab-sidebar]
                widgets = [
                    { id = 'todo-list', type = 'built-in/todo-list', enabled = true },
                    { id = 'time-date', type = 'built-in/time-date', enabled = true, show-date = true },
                    { id = 'schedule-heatmap', type = 'built-in/schedule-heatmap', enabled = true, schedule-path = '/tmp/schedule', toggl-entries-path = '/tmp/toggl/entries', deviation-path = '/tmp/deviation', days = 7 },
                    { id = 'toggl-weekly-focus', type = 'built-in/toggl-weekly-focus', enabled = true, entries-path = '/tmp/toggl/entries', target-date = '2026-09-13' },
                    { id = 'toggl-week-focus', type = 'built-in/toggl-week-focus', enabled = true, entries-path = '/tmp/toggl/entries', target-date = '2026-09-13' },
                    { id = 'period-heatmap', type = 'built-in/period-heatmap', enabled = true, entries-path = '/tmp/period' },
                    { id = 'spending-categories', type = 'built-in/spending-categories', enabled = true, entries-path = '/tmp/spending', days = 28, rotation-group = 'focus' },
                    { id = 'custom', type = 'plugin', enabled = false, bundle = 'CustomWidget.bundle' },
                ]
            """,
        ).config

        let configMap = buildConfigMap()
        guard let json = JSONEncoder.winMuxDefault.encodeToString(configMap) else {
            XCTFail("Expected config map to encode as JSON")
            return
        }
        XCTAssertTrue(json.contains("\"tab-sidebar\""))
        XCTAssertTrue(json.contains("\"widgets\""))
        XCTAssertTrue(json.contains("\"todo-list\""))
        XCTAssertTrue(json.contains("\"time-date\""))
        XCTAssertTrue(json.contains("\"/tmp/toggl/entries\""))
        XCTAssertTrue(json.contains("\"toggl-weekly-focus\""))
        XCTAssertTrue(json.contains("\"toggl-week-focus\""))
        XCTAssertTrue(json.contains("\"period-heatmap\""))
        XCTAssertTrue(json.contains("\"/tmp/period\""))
        XCTAssertTrue(json.contains("\"spending-categories\""))
        XCTAssertTrue(json.contains("\"/tmp/spending\""))
        XCTAssertTrue(json.contains("\"schedule-heatmap\""))
        XCTAssertTrue(json.contains("\"/tmp/schedule\""))
        XCTAssertTrue(json.contains("\"/tmp/deviation\""))
        XCTAssertTrue(json.contains("\"target-date\""))
        XCTAssertTrue(json.contains("\"rotation-group\""))
        XCTAssertFalse(json.contains("\"rotation-interval-seconds\""))
        XCTAssertTrue(json.contains("\"CustomWidget.bundle\""))
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "4", "enabled"].slice).get(),
            .scalar(.bool(true)),
        )
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "3", "target-date"].slice).get(),
            .scalar(.string("2026-09-13")),
        )
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "5", "entries-path"].slice).get(),
            .scalar(.string("/tmp/period")),
        )
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "6", "rotation-group"].slice).get(),
            .scalar(.string("focus")),
        )
        assertEquals(
            try? configMap.find(keyPath: ["tab-sidebar", "widgets", "7", "enabled"].slice).get(),
            .scalar(.bool(false)),
        )
    }

    func testParseWindowTabs() {
        let (parsed, errors) = parseConfig(
            """
            [window-tabs]
                enabled = true
                height = 38
            """,
        )
        assertEquals(errors, [])
        assertEquals(parsed.windowTabs, WindowTabsConfig(enabled: true, height: 38))

        let (_, heightErrors) = parseConfig(
            """
            [window-tabs]
                height = 20
            """,
        )
        assertEquals(heightErrors.descriptions, [
            "window-tabs.height: Must be greater than 20",
        ])
    }

    func testConfigMapExposesWindowTabsState() {
        config.windowTabs = WindowTabsConfig(enabled: true, height: 40)

        let configMap = buildConfigMap()

        assertEquals(
            try? configMap.find(keyPath: ["window-tabs", "enabled"].slice).get(),
            .scalar(.bool(true)),
        )
        assertEquals(
            try? configMap.find(keyPath: ["window-tabs", "height"].slice).get(),
            .scalar(.int(40)),
        )
    }

    func testParseRectangleShortcutsPresetIsRemoved() {
        let (parsed, errors) = parseConfig(
            """
            shortcuts-preset = 'rectangle'
            [mode.main.binding]
                alt-h = 'focus left'
            """,
        )
        assertEquals(errors.descriptions, [
            "shortcuts-preset: The 'rectangle' shortcuts preset has been removed",
        ])
        XCTAssertEqual(parsed.shortcutsPreset, .rectangle)
        XCTAssertNotNil(parsed.modes["main"])
    }

    func testRemovedRectangleShortcutsPresetDoesNotOverrideExplicitBindings() {
        let (parsed, errors) = parseConfig(
            """
            shortcuts-preset = 'rectangle'
            [mode.main.binding]
                ctrl-alt-left = 'focus left'
            """,
        )
        assertEquals(errors.descriptions, [
            "shortcuts-preset: The 'rectangle' shortcuts preset has been removed",
        ])

        let explicitBinding = HotkeyBinding(.control.union(.option), .leftArrow, [FocusCommand.new(direction: .left)])
        assertEquals(parsed.modes[mainModeId]?.bindings[explicitBinding.descriptionWithKeyCode], explicitBinding)
    }

    func testParseOnWindowDetected() {
        let (parsed, errors) = parseConfig(
            """
            [[on-window-detected]] # 0
                if.tab = 'W'
                check-further-callbacks = true
                run = ['layout floating', 'move-node-to-tab W']
            [[on-window-detected]] # 1
                if.app-id = 'com.apple.systempreferences'
                if.workspace = 'Legacy'
                run = []
            [[on-window-detected]] # 2
            [[on-window-detected]] # 3
                run = ['move-node-to-tab S', 'layout tiling']
            [[on-window-detected]] # 4
                run = ['move-node-to-tab S', 'move-node-to-tab W']
            [[on-window-detected]] # 5
                run = ['move-node-to-tab S', 'layout h_tiles']
            """,
        )
        assertEquals(parsed.onWindowDetected, [
            WindowDetectedCallback( // 0
                matcher: WindowDetectedCallbackMatcher(
                    appId: nil,
                    appNameRegexSubstring: nil,
                    windowTitleRegexSubstring: nil,
                    workspace: "W",
                ),
                checkFurtherCallbacks: true,
                rawRun: [
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.floating])),
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W")),
                ],
            ),
            WindowDetectedCallback( // 1
                matcher: WindowDetectedCallbackMatcher(
                    appId: "com.apple.systempreferences",
                    appNameRegexSubstring: nil,
                    windowTitleRegexSubstring: nil,
                    workspace: "Legacy",
                ),
                rawRun: [],
            ),
            WindowDetectedCallback( // 3
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.tiling])),
                ],
            ),
            WindowDetectedCallback( // 4
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "W")),
                ],
            ),
            WindowDetectedCallback( // 5
                rawRun: [
                    MoveNodeToWorkspaceCommand(args: MoveNodeToWorkspaceCmdArgs(workspace: "S")),
                    LayoutCommand(args: LayoutCmdArgs(rawArgs: [], toggleBetween: [.h_tiles])),
                ],
            ),
        ])

        assertEquals(errors.descriptions, [
            "on-window-detected[2]: \'run\' is mandatory key",
        ])
    }

    func testParseOnWindowDetectedRegex() {
        let (config, errors) = parseConfig(
            """
            [[on-window-detected]]
                if.app-name-regex-substring = '^system settings$'
                run = []
            """,
        )
        XCTAssertTrue(config.onWindowDetected.singleOrNil()!.matcher.appNameRegexSubstring != nil)
        assertEquals(errors, [])
    }

    func testRegex() {
        var devNull: [String] = []
        XCTAssertTrue("System Settings".contains(parseCaseInsensitiveRegex("settings").getOrNil(appendErrorTo: &devNull)!))
        XCTAssertTrue(!"System Settings".contains(parseCaseInsensitiveRegex("^settings^").getOrNil(appendErrorTo: &devNull)!))
    }

    func testParseGaps() {
        let (config, errors1) = parseConfig(
            """
            [gaps]
                inner.horizontal = 10
                inner.vertical = [{ monitor."main" = 1 }, { monitor."secondary" = 2 }, 5]
                outer.left = 12
                outer.bottom = 13
                outer.top = [{ monitor."built-in" = 3 }, { monitor."secondary" = 4 }, 6]
                outer.right = [{ monitor.2 = 7 }, 8]
            """,
        )
        assertEquals(errors1, [])
        assertEquals(
            config.gaps,
            Gaps(
                inner: .init(
                    vertical: .perMonitor(
                        [PerMonitorValue(description: .main, value: 1), PerMonitorValue(description: .secondary, value: 2)],
                        default: 5,
                    ),
                    horizontal: .constant(10),
                ),
                outer: .init(
                    left: .constant(12),
                    bottom: .constant(13),
                    top: .perMonitor(
                        [
                            PerMonitorValue(description: .caseSensitivePattern("built-in")!, value: 3),
                            PerMonitorValue(description: .secondary, value: 4),
                        ],
                        default: 6,
                    ),
                    right: .perMonitor([PerMonitorValue(description: .sequenceNumber(2), value: 7)], default: 8),
                ),
            ),
        )

        let (_, errors2) = parseConfig(
            """
            [gaps]
                inner.horizontal = [true]
                inner.vertical = [{ foo.main = 1 }, { monitor = { foo = 2, bar = 3 } }, 1]
            """,
        )
        assertEquals(errors2.descriptions, [
            "gaps.inner.horizontal: The last item in the array must be of type Int",
            "gaps.inner.vertical[0]: The table is expected to have a single key \'monitor\'",
            "gaps.inner.vertical[1].monitor: The table is expected to have a single key",
        ])
    }

    func testParseKeyMapping() {
        let (config, errors) = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'q'
                unicorn = 'u'

            [mode.main.binding]
                alt-unicorn = 'workspace wonderland'
            """,
        )
        assertEquals(errors.descriptions, [])
        assertEquals(config.keyMapping, KeyMapping(preset: .qwerty, rawKeyNotationToKeyCode: [
            "q": .q,
            "unicorn": .u,
        ]))
        let binding = HotkeyBinding(.option, .u, [WorkspaceCommand(args: WorkspaceCmdArgs(target: .direct(.parse("unicorn").getOrDie())))])
        assertEquals(config.modes[mainModeId]?.bindings, [binding.descriptionWithKeyCode: binding])

        let (_, errors1) = parseConfig(
            """
            [key-mapping.key-notation-to-key-code]
                q = 'qw'
                ' f' = 'f'
            """,
        )
        assertEquals(errors1.descriptions, [
            "key-mapping.key-notation-to-key-code: ' f' is invalid key notation",
            "key-mapping.key-notation-to-key-code.q: 'qw' is invalid key code",
        ])

        let (dvorakConfig, dvorakErrors) = parseConfig(
            """
            key-mapping.preset = 'dvorak'
            """,
        )
        assertEquals(dvorakErrors, [])
        assertEquals(dvorakConfig.keyMapping, KeyMapping(preset: .dvorak, rawKeyNotationToKeyCode: [:]))
        assertEquals(dvorakConfig.keyMapping.resolve()["quote"], .q)
        let (colemakConfig, colemakErrors) = parseConfig(
            """
            key-mapping.preset = 'colemak'
            """,
        )
        assertEquals(colemakErrors, [])
        assertEquals(colemakConfig.keyMapping, KeyMapping(preset: .colemak, rawKeyNotationToKeyCode: [:]))
        assertEquals(colemakConfig.keyMapping.resolve()["f"], .e)
    }

}
