import SwiftUI

struct WorkspaceSidebarWidgetStack: View {
    let widgets: [WorkspaceSidebarWidgetConfig]
    let sectionWidth: CGFloat
    let isCompact: Bool
    let showsNotePad: Bool

    private var enabledWidgets: [WorkspaceSidebarWidgetConfig] {
        widgets.filter { widget in
            workspaceSidebarWidgetIsVisible(
                widget,
                showsNotePad: showsNotePad,
                isCompact: isCompact
            )
        }
    }

    private var renderItems: [WorkspaceSidebarWidgetStackItem] {
        WorkspaceSidebarWidgetStackItem.items(for: enabledWidgets)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: workspaceSidebarWidgetStackGap) {
            ForEach(renderItems) { item in
                WorkspaceSidebarWidgetStackItemView(
                    item: item,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                )
            }
        }
        .frame(width: sectionWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func workspaceSidebarWidgetIsVisible(
    _ widget: WorkspaceSidebarWidgetConfig,
    showsNotePad: Bool,
    isCompact: Bool = false
) -> Bool {
    widget.enabled &&
        (!isCompact || widget.type != .builtInTogglWeeklyFocus) &&
        widget.type != .builtInSpendingCategories &&
        widget.type != .builtInScheduleHeatmap &&
        widget.type != .builtInTodoList &&
        widget.type != .builtInTasks
}

func workspaceSidebarHasVisibleWidgets(
    _ widgets: [WorkspaceSidebarWidgetConfig],
    showsNotePad: Bool,
    isCompact: Bool = false
) -> Bool {
    widgets.contains {
        workspaceSidebarWidgetIsVisible(
            $0,
            showsNotePad: showsNotePad,
            isCompact: isCompact
        )
    }
}

enum WorkspaceSidebarWidgetStackItem: Identifiable, Equatable {
    case widget(WorkspaceSidebarWidgetConfig)
    case rotationGroup(id: String, widgets: [WorkspaceSidebarWidgetConfig], intervalSeconds: Int)

    var id: String {
        switch self {
            case .widget(let widget):
                widget.id
            case .rotationGroup(let id, _, _):
                "rotation-\(id)"
        }
    }

    static func items(for widgets: [WorkspaceSidebarWidgetConfig]) -> [WorkspaceSidebarWidgetStackItem] {
        var widgetsByGroup: [String: [WorkspaceSidebarWidgetConfig]] = [:]
        for widget in widgets {
            guard let rotationGroup = widget.rotationGroup else { continue }
            widgetsByGroup[rotationGroup, default: []].append(widget)
        }

        var seenRotationGroups = Set<String>()
        return widgets.compactMap { widget in
            guard let rotationGroup = widget.rotationGroup else {
                return .widget(widget)
            }
            guard seenRotationGroups.insert(rotationGroup).inserted else {
                return nil
            }

            let groupedWidgets = widgetsByGroup[rotationGroup] ?? [widget]
            guard groupedWidgets.count > 1 else {
                return .widget(widget)
            }

            let intervalSeconds = groupedWidgets
                .lazy
                .compactMap(\.rotationIntervalSeconds)
                .first ?? defaultWorkspaceSidebarWidgetRotationIntervalSeconds
            return .rotationGroup(
                id: rotationGroup,
                widgets: groupedWidgets,
                intervalSeconds: intervalSeconds,
            )
        }
    }

    static func activeWidget(
        in widgets: [WorkspaceSidebarWidgetConfig],
        intervalSeconds: Int,
        at date: Date,
    ) -> WorkspaceSidebarWidgetConfig? {
        guard !widgets.isEmpty else { return nil }
        let interval = TimeInterval(max(1, intervalSeconds))
        let slot = Int(date.timeIntervalSinceReferenceDate / interval)
        return widgets[slot % widgets.count]
    }
}

private struct WorkspaceSidebarWidgetStackItemView: View {
    let item: WorkspaceSidebarWidgetStackItem
    let sectionWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        switch item {
            case .widget(let widget):
                renderWidget(widget)
            case .rotationGroup(let groupId, let widgets, let intervalSeconds):
                WorkspaceSidebarRotatingWidgetGroup(
                    groupId: groupId,
                    widgets: widgets,
                    intervalSeconds: intervalSeconds,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                )
        }
    }

    @ViewBuilder
    private func renderWidget(_ widget: WorkspaceSidebarWidgetConfig) -> some View {
        switch widget.type {
            case .builtInTodoList:
                WorkspaceSidebarTodoListWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                )
            case .builtInTasks:
                WorkspaceSidebarTasksWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    tasksPath: widget.tasksPath ?? defaultWorkspaceSidebarTasksPath,
                )
            case .builtInTimeDate:
                WorkspaceSidebarTimeDateWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    showsDate: widget.showDate,
                )
            case .builtInTodayFocus:
                WorkspaceSidebarTodayFocusWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    entriesPath: widget.entriesPath ?? defaultWorkspaceSidebarTogglEntriesPath,
                )
            case .builtInTogglWeeklyFocus:
                WorkspaceSidebarTogglWeeklyFocusWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    entriesPath: widget.entriesPath ?? defaultWorkspaceSidebarTogglEntriesPath,
                    targetDate: widget.targetDate ?? defaultWorkspaceSidebarTogglWeeklyFocusTargetDate,
                )
            case .builtInTogglWeekFocus:
                WorkspaceSidebarTogglWeekFocusWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    entriesPath: widget.entriesPath ?? defaultWorkspaceSidebarTogglEntriesPath,
                    targetDate: widget.targetDate ?? defaultWorkspaceSidebarTogglWeeklyFocusTargetDate,
                )
            case .builtInPeriodHeatmap:
                WorkspaceSidebarPeriodHeatmapWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    entriesPath: widget.entriesPath ?? defaultWorkspaceSidebarPeriodEntriesPath,
                )
            case .builtInSpendingCategories:
                WorkspaceSidebarSpendingCategoriesWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    entriesPath: widget.entriesPath ?? defaultWorkspaceSidebarSpendingEntriesPath,
                    days: widget.days ?? defaultWorkspaceSidebarSpendingDays,
                )
            case .builtInScheduleHeatmap:
                WorkspaceSidebarScheduleHeatmapWidget(
                    id: widget.id,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                    schedulePath: widget.schedulePath ?? defaultWorkspaceSidebarSchedulePath,
                    togglEntriesPath: widget.togglEntriesPath ?? defaultWorkspaceSidebarTogglEntriesPath,
                    deviationPath: widget.deviationPath ?? defaultWorkspaceSidebarDeviationPath,
                    days: widget.days ?? defaultWorkspaceSidebarScheduleHeatmapDays,
                )
            case .plugin:
                WorkspaceSidebarPluginWidget(
                    config: widget,
                    sectionWidth: sectionWidth,
                    isCompact: isCompact,
                )
        }
    }
}

private struct WorkspaceSidebarRotatingWidgetGroup: View {
    let groupId: String
    let widgets: [WorkspaceSidebarWidgetConfig]
    let intervalSeconds: Int
    let sectionWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: rotationPeriod)) { context in
            Group {
                if let widget = currentWidget(at: context.date) {
                    WorkspaceSidebarWidgetStackItemView(
                        item: .widget(widget),
                        sectionWidth: sectionWidth,
                        isCompact: isCompact,
                    )
                    .id(widget.id)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: widget.id)
                }
            }
        }
        .id(groupId)
    }

    private var rotationPeriod: TimeInterval {
        TimeInterval(max(1, intervalSeconds))
    }

    private func currentWidget(at date: Date) -> WorkspaceSidebarWidgetConfig? {
        WorkspaceSidebarWidgetStackItem.activeWidget(
            in: widgets,
            intervalSeconds: intervalSeconds,
            at: date,
        )
    }
}
