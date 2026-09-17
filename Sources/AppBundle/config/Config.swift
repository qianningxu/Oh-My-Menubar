import AppKit
import Common
import HotKey
import OrderedCollections

func getDefaultConfigUrlFromProject() -> URL {
    var url = URL(filePath: #filePath)
    check(FileManager.default.fileExists(atPath: url.path))
    while !FileManager.default.fileExists(atPath: url.appending(component: ".git").path) {
        url.deleteLastPathComponent()
    }
    let projectRoot: URL = url
    return projectRoot.appending(component: "resources/default-config.toml")
}

var defaultConfigUrl: URL {
    if isUnitTest {
        return getDefaultConfigUrlFromProject()
    } else {
        return Bundle.main.url(forResource: "default-config", withExtension: "toml")
            // Useful for debug builds that are not app bundles
            ?? getDefaultConfigUrlFromProject()
    }
}
@MainActor let defaultConfig: Config = {
    let parsedConfig = parseConfig(Result { try String(contentsOf: defaultConfigUrl, encoding: .utf8) }.getOrDie())
    if !parsedConfig.errors.isEmpty {
        die("Can't parse default config: \(parsedConfig.errors)")
    }
    return parsedConfig.config
}()
@MainActor var config: Config = defaultConfig // todo move to Ctx?
@MainActor var configUrl: URL = defaultConfigUrl

struct Config: ConvenienceCopyable {
    var configVersion: Int = 1
    var afterLoginCommand: [any Command] = []
    var afterStartupCommand: [any Command] = []
    var _indentForNestedContainersWithTheSameOrientation: Void = ()
    var enableNormalizationFlattenContainers: Bool = true
    var _nonEmptyWorkspacesRootContainersLayoutOnStartup: Void = ()
    var defaultRootContainerLayout: Layout = .tiles
    var defaultRootContainerOrientation: DefaultContainerOrientation = .auto
    var startAtLogin: Bool = false
    var autoReloadConfig: Bool = false
    var enableProjects: Bool = false
    var automaticallyUnhideMacosHiddenApps: Bool = false
    var shortcutsPreset: ShortcutsPreset = .none
    var tabGroupPadding: Int = 30
    var enableNormalizationOppositeOrientationForNestedContainers: Bool = true
    var persistentWorkspaces: OrderedSet<String> = []
    var execOnWorkspaceChange: [String] = [] // todo deprecate
    var keyMapping = KeyMapping()
    var execConfig: ExecConfig = ExecConfig()

    var onFocusChanged: [any Command] = []
    // var onFocusedWorkspaceChanged: [any Command] = []
    var onFocusedMonitorChanged: [any Command] = []

    var autoAddNewWindowsToTabGroup: Bool = false
    var gaps: Gaps = .zero
    var workspaceSidebar = WorkspaceSidebarConfig()
    var windowTabs = WindowTabsConfig()
    var workspaceToMonitorForceAssignment: [String: [MonitorDescription]] = [:]
    var modes: [String: Mode] = [:]
    var onWindowDetected: [WindowDetectedCallback] = []
    var onModeChanged: [any Command] = []
}

enum DefaultContainerOrientation: String {
    case horizontal, vertical, auto
}

enum ShortcutsPreset: String, Equatable, Sendable {
    case none
    case rectangle
}

struct WorkspaceSidebarConfig: ConvenienceCopyable, Equatable, Sendable {
    var enabled: Bool = false
    var enableFocus: Bool = false
    var collapsedWidth: Int = 44
    var width: Int = 212
    var monitor: [MonitorDescription] = []
    var showStatusPills: Bool = true
    var showDate: Bool = true
    var widgets: [WorkspaceSidebarWidgetConfig]? = nil
    var menuBarReserveHeight: Int = 36
    var projectDeletionAction: WorkspaceProjectDeletionAction = .closeWindows
    var workspaceLabels: [String: String] = [:]
    var folderLabels: [String: String] = [:]
    var folderColors: [String: String] = [:]
    var projectLabels: [String: String] = [:]
    var projectColors: [String: String] = [:]
}

struct WorkspaceSidebarWidgetConfig: ConvenienceCopyable, Equatable, Sendable {
    var id: String = ""
    var type: WorkspaceSidebarWidgetType = .builtInTimeDate
    var enabled: Bool = true
    var showDate: Bool = true
    var bundle: String? = nil
    var entriesPath: String? = nil
    var tasksPath: String? = nil
    var schedulePath: String? = nil
    var togglEntriesPath: String? = nil
    var deviationPath: String? = nil
    var targetDate: String? = nil
    var days: Int? = nil
    var rotationGroup: String? = nil
    var rotationIntervalSeconds: Int? = nil
}

enum WorkspaceSidebarWidgetType: String, CaseIterable, Sendable {
    case builtInTodoList = "built-in/todo-list"
    case builtInTasks = "built-in/tasks"
    case builtInTimeDate = "built-in/time-date"
    case builtInTodayFocus = "built-in/today-focus"
    case builtInTogglWeeklyFocus = "built-in/toggl-weekly-focus"
    case builtInTogglWeekFocus = "built-in/toggl-week-focus"
    case builtInPeriodHeatmap = "built-in/period-heatmap"
    case builtInSpendingCategories = "built-in/spending-categories"
    case builtInScheduleHeatmap = "built-in/schedule-heatmap"
    case plugin
}

let defaultWorkspaceSidebarDataPath = "/Users/side/Documents/now/my_app/self/self_data/data"
let defaultWorkspaceSidebarTasksPath = "/Users/side/Documents/now/my_app/self/self_ob/Others/Tasks"
let defaultWorkspaceSidebarTogglEntriesPath = defaultWorkspaceSidebarDataPath
let defaultWorkspaceSidebarTogglWeeklyFocusTargetDate = "2026-09-13"
let defaultWorkspaceSidebarPeriodEntriesPath = defaultWorkspaceSidebarDataPath
let defaultWorkspaceSidebarSpendingEntriesPath = defaultWorkspaceSidebarDataPath
let defaultWorkspaceSidebarSpendingDays = 28
let defaultWorkspaceSidebarSchedulePath = defaultWorkspaceSidebarDataPath
let defaultWorkspaceSidebarDeviationPath = "/Users/side/Documents/now/my_app/self/self_ob"
let defaultWorkspaceSidebarScheduleHeatmapDays = 7
let defaultWorkspaceSidebarWidgetRotationIntervalSeconds = 300

enum WorkspaceProjectDeletionAction: String, CaseIterable, Identifiable, Sendable {
    case closeWindows = "close-windows"
    case moveWindowsToFallback = "move-windows-to-fallback"

    var id: String { rawValue }
}

struct WindowTabsConfig: ConvenienceCopyable, Equatable, Sendable {
    var enabled: Bool = false
    var height: Int = 36
    var tabLabels: [String: String] = [:]
}

extension WorkspaceSidebarConfig {
    var resolvedWidgets: [WorkspaceSidebarWidgetConfig] {
        widgets ?? [
            WorkspaceSidebarWidgetConfig(
                id: "time-date",
                type: .builtInTimeDate,
                enabled: false,
                showDate: showDate,
            ),
        ]
    }

    @MainActor
    func resolvedMonitor(sortedMonitors: [Monitor]) -> Monitor? {
        monitor.lazy
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .first
    }

    @MainActor
    func resolvedMonitors(sortedMonitors: [Monitor]) -> [Monitor] {
        guard !monitor.isEmpty else { return sortedMonitors }
        if monitor == [.main] {
            return sortedMonitors
        }
        var seenTopLeftCorners = Set<CGPoint>()
        return monitor
            .compactMap { $0.resolveMonitor(sortedMonitors: sortedMonitors) }
            .filter { seenTopLeftCorners.insert($0.rect.topLeftCorner).inserted }
    }
}
