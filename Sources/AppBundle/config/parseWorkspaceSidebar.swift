import Foundation
import TOMLKit

private let workspaceSidebarParser: [String: any ParserProtocol<WorkspaceSidebarConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "enable-focus": Parser(\.enableFocus, parseBool),
    "collapsed-width": Parser(\.collapsedWidth, parseWorkspaceSidebarWidth),
    "width": Parser(\.width, parseWorkspaceSidebarWidth),
    "monitor": Parser(\.monitor) { value, backtrace, errors in
        parseMonitorDescriptions(value, backtrace, &errors)
    },
    "show-status-pills": Parser(\.showStatusPills, parseBool),
    "show-date": Parser(\.showDate, parseBool),
    "widgets": Parser(\.widgets, parseWorkspaceSidebarWidgets),
    "menu-bar-reserve-height": Parser(\.menuBarReserveHeight, parseWorkspaceSidebarMenuBarReserveHeight),
    "folder-deletion-action": Parser(\.projectDeletionAction, parseWorkspaceProjectDeletionAction),
    "folder-labels": Parser(\.folderLabels, parseWorkspaceSidebarLabels),
    "folder-colors": Parser(\.folderColors, parseWorkspaceSidebarProjectColors),
    "project-deletion-action": Parser(\.projectDeletionAction, parseWorkspaceProjectDeletionAction),
    "tab-labels": Parser(\.workspaceLabels, parseWorkspaceSidebarLabels),
    "workspace-labels": Parser(\.workspaceLabels, parseWorkspaceSidebarLabels),
    "project-labels": Parser(\.projectLabels, parseWorkspaceSidebarLabels),
    "project-colors": Parser(\.projectColors, parseWorkspaceSidebarProjectColors),
]

func parseWorkspaceSidebar(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> WorkspaceSidebarConfig {
    parseTable(raw, WorkspaceSidebarConfig(), workspaceSidebarParser, backtrace, &errors)
}

private func parseWorkspaceSidebarWidth(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than 0")) { $0 > 0 }
}

private func parseWorkspaceSidebarMenuBarReserveHeight(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than or equal to 0")) { $0 >= 0 }
}

private let workspaceSidebarWidgetParser: [String: any ParserProtocol<WorkspaceSidebarWidgetConfig>] = [
    "id": Parser(\.id, parseString),
    "type": Parser(\.type, parseWorkspaceSidebarWidgetType),
    "enabled": Parser(\.enabled, parseBool),
    "show-date": Parser(\.showDate, parseBool),
    "bundle": Parser(\.bundle) { raw, backtrace in parseString(raw, backtrace).map { Optional($0) } },
    "entries-path": Parser(\.entriesPath) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "tasks-path": Parser(\.tasksPath) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "schedule-path": Parser(\.schedulePath) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "toggl-entries-path": Parser(\.togglEntriesPath) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "deviation-path": Parser(\.deviationPath) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "target-date": Parser(\.targetDate) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must be YYYY-MM-DD")) { rawValue in
                workspaceSidebarDateFormatter.date(from: rawValue) != nil
            }
            .map { Optional($0) }
    },
    "days": Parser(\.days) { raw, backtrace in
        parseInt(raw, backtrace)
            .filter(.semantic(backtrace, "Must be greater than 0")) { $0 > 0 }
            .map { Optional($0) }
    },
    "rotation-group": Parser(\.rotationGroup) { raw, backtrace in
        parseString(raw, backtrace)
            .filter(.semantic(backtrace, "Must not be empty")) { !$0.isEmpty }
            .map { Optional($0) }
    },
    "rotation-interval-seconds": Parser(\.rotationIntervalSeconds) { raw, backtrace in
        parseInt(raw, backtrace)
            .filter(.semantic(backtrace, "Must be greater than 0")) { $0 > 0 }
            .map { Optional($0) }
    },
]

private func parseWorkspaceSidebarWidgets(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [WorkspaceSidebarWidgetConfig]? {
    guard let rawArray = raw.array else {
        errors.append(expectedActualTypeError(expected: .array, actual: raw.type, backtrace))
        return nil
    }

    var seenIds = Set<String>()
    return rawArray.enumerated().compactMap { index, rawWidget in
        let widgetBacktrace = backtrace + .index(index)
        guard rawWidget.table != nil else {
            errors.append(expectedActualTypeError(expected: .table, actual: rawWidget.type, widgetBacktrace))
            return nil
        }

        let widget = parseTable(rawWidget, WorkspaceSidebarWidgetConfig(), workspaceSidebarWidgetParser, widgetBacktrace, &errors)
        guard !widget.id.isEmpty else {
            errors.append(.semantic(widgetBacktrace + .key("id"), "Must not be empty"))
            return nil
        }
        guard seenIds.insert(widget.id).inserted else {
            errors.append(.semantic(widgetBacktrace + .key("id"), "Duplicate widget id '\(widget.id)'"))
            return nil
        }
        if widget.tasksPath != nil, widget.type != .builtInTasks {
            errors.append(.semantic(widgetBacktrace + .key("tasks-path"), "Only tasks widgets can specify tasks-path"))
        }
        switch widget.type {
            case .builtInTodoList:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.entriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("entries-path"), "Only data widgets can specify entries-path"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Only data widgets can specify days"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .builtInTasks:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.entriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("entries-path"), "Tasks widgets use tasks-path"))
                }
                if widget.schedulePath != nil || widget.togglEntriesPath != nil || widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace, "Tasks widgets only support tasks-path"))
                }
                if widget.days != nil || widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace, "Tasks widgets only support tasks-path"))
                }
            case .builtInTimeDate:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.entriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("entries-path"), "Only data widgets can specify entries-path"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Only data widgets can specify days"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .builtInTodayFocus:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Only data window widgets can specify days"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .builtInTogglWeeklyFocus, .builtInTogglWeekFocus:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Toggl weekly focus uses target-date"))
                }
            case .builtInPeriodHeatmap:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Only data window widgets can specify days"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .builtInSpendingCategories:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .builtInScheduleHeatmap:
                if widget.bundle != nil {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Only plugin widgets can specify bundle"))
                }
                if widget.entriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("entries-path"), "Schedule heatmap widgets use toggl-entries-path"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
            case .plugin:
                if widget.bundle?.isEmpty != false {
                    errors.append(.semantic(widgetBacktrace + .key("bundle"), "Plugin widgets require a bundle name"))
                    return nil
                }
                if widget.entriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("entries-path"), "Only data widgets can specify entries-path"))
                }
                if widget.schedulePath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("schedule-path"), "Only schedule heatmap widgets can specify schedule-path"))
                }
                if widget.togglEntriesPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("toggl-entries-path"), "Only schedule heatmap widgets can specify toggl-entries-path"))
                }
                if widget.deviationPath != nil {
                    errors.append(.semantic(widgetBacktrace + .key("deviation-path"), "Only schedule heatmap widgets can specify deviation-path"))
                }
                if widget.days != nil {
                    errors.append(.semantic(widgetBacktrace + .key("days"), "Only data widgets can specify days"))
                }
                if widget.targetDate != nil {
                    errors.append(.semantic(widgetBacktrace + .key("target-date"), "Only target-date widgets can specify target-date"))
                }
        }
        return widget
    }
}

private let workspaceSidebarDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
}()

private func parseWorkspaceSidebarWidgetType(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
) -> ParsedToml<WorkspaceSidebarWidgetType> {
    parseString(raw, backtrace).flatMap { rawValue in
        WorkspaceSidebarWidgetType(rawValue: rawValue)
            .orFailure(.semantic(
                backtrace,
                "Possible values: \(WorkspaceSidebarWidgetType.allCases.map(\.rawValue).joined(separator: ", "))",
            ))
    }
}

private func parseWorkspaceProjectDeletionAction(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
) -> ParsedToml<WorkspaceProjectDeletionAction> {
    parseString(raw, backtrace).flatMap { rawValue in
        WorkspaceProjectDeletionAction(rawValue: rawValue)
            .orFailure(.semantic(
                backtrace,
                "Possible values: \(WorkspaceProjectDeletionAction.allCases.map(\.rawValue).joined(separator: ", "))",
            ))
    }
}

private func parseWorkspaceSidebarLabels(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [String: String] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: String] = [:]
    for (workspaceName, rawLabel) in rawTable {
        if let label = parseString(rawLabel, backtrace + .key(workspaceName)).getOrNil(appendErrorTo: &errors) {
            result[workspaceName] = label
        }
    }
    return result
}

func normalizedWorkspaceSidebarColorHex(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let hex = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
    let allowedCharacters = Set("0123456789abcdefABCDEF")
    guard hex.count == 6,
          hex.allSatisfy({ allowedCharacters.contains($0) })
    else {
        return nil
    }
    return "#\(hex.uppercased())"
}

private func parseWorkspaceSidebarProjectColors(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [String: String] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: String] = [:]
    for (projectId, rawColor) in rawTable {
        let colorBacktrace = backtrace + .key(projectId)
        guard let color = parseString(rawColor, colorBacktrace).getOrNil(appendErrorTo: &errors) else { continue }
        guard let normalized = normalizedWorkspaceSidebarColorHex(color) else {
            errors.append(.semantic(colorBacktrace, "Must be a hex color like '#RRGGBB'"))
            continue
        }
        result[projectId] = normalized
    }
    return result
}
