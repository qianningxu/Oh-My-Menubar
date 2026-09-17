import AppKit
import Foundation
import SwiftUI

struct WorkspaceSidebarAgendaProject: Identifiable, Equatable, Sendable {
    let name: String
    let hours: Double

    var id: String { name }

    var hoursText: String {
        if hours.rounded() == hours { return "\(Int(hours))h" }
        return String(format: "%.2f", hours)
            .replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\.$", with: "", options: .regularExpression) + "h"
    }
}

struct WorkspaceSidebarTasksAgenda: Equatable, Sendable {
    enum Day: String, Equatable, Sendable {
        case today = "Today"
    }

    let day: Day
    let projects: [WorkspaceSidebarAgendaProject]
    let errorMessage: String?
}

enum WorkspaceSidebarTasksReader {
    static func load(
        tasksRoot: URL,
        now: Date = Date(),
        calendar: Calendar = .current,
        fileManager: FileManager = .default
    ) -> WorkspaceSidebarTasksAgenda {
        guard let projectURLs = try? fileManager.contentsOfDirectory(
            at: tasksRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else {
            return WorkspaceSidebarTasksAgenda(day: .today, projects: [], errorMessage: "Can't read tasks")
        }

        let allTasks = projectURLs
            .filter { projectURL in
                guard projectURL.lastPathComponent.caseInsensitiveCompare("archived") != .orderedSame,
                      let values = try? projectURL.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey])
                else { return false }
                return values.isDirectory == true && values.isHidden != true
            }
            .flatMap { tasks(in: $0, fileManager: fileManager) }

        let todayKey = dateKey(now, calendar: calendar)
        let todayTasks = tasks(on: todayKey, from: allTasks)
        return WorkspaceSidebarTasksAgenda(day: .today, projects: todayTasks, errorMessage: nil)
    }

    private struct ParsedTask {
        let project: String
        let arrangement: [String: Double]
    }

    private static func tasks(in projectURL: URL, fileManager: FileManager) -> [ParsedTask] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension.caseInsensitiveCompare("md") == .orderedSame,
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey]),
                  values.isRegularFile == true,
                  values.isHidden != true,
                  let contents = try? String(contentsOf: url, encoding: .utf8)
            else { return nil }

            let frontmatter = parseFrontmatter(contents)
            guard !isCompleted(frontmatter["completed"]),
                  let arrangement = parseArrangement(frontmatter["arrangement"]),
                  !arrangement.isEmpty
            else { return nil }

            return ParsedTask(
                project: projectURL.lastPathComponent,
                arrangement: arrangement
            )
        }
    }

    private static func tasks(on date: String, from tasks: [ParsedTask]) -> [WorkspaceSidebarAgendaProject] {
        let hoursByProject = tasks.reduce(into: [String: Double]()) { result, task in
            guard let hours = task.arrangement[date], hours > 0 else { return }
            result[task.project, default: 0] += hours
        }
        return hoursByProject.map { WorkspaceSidebarAgendaProject(name: $0.key, hours: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func parseFrontmatter(_ contents: String) -> [String: String] {
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var result: [String: String] = [:]
        for line in lines.dropFirst() {
            if line.trimmingCharacters(in: .whitespaces) == "---" { break }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            result[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func parseArrangement(_ rawValue: String?) -> [String: Double]? {
        guard let rawValue else { return nil }
        let value = unquote(rawValue)
        guard let data = value.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return nil }

        var result: [String: Double] = [:]
        for item in items {
            guard let date = item["date"] as? String,
                  date.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
                  let hours = (item["hours"] as? NSNumber)?.doubleValue,
                  hours > 0
            else { continue }
            result[date, default: 0] += hours
        }
        return result
    }

    private static func isCompleted(_ rawValue: String?) -> Bool {
        guard let rawValue else { return false }
        return ["true", "yes", "1", "done"].contains(unquote(rawValue).lowercased())
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              first == last,
              first == "\"" || first == "'"
        else { return value }
        return String(value.dropFirst().dropLast())
    }

    private static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private final class WorkspaceSidebarTasksPathWatcher {
    private let source: DispatchSourceFileSystemObject
    private let fileDescriptor: Int32

    init?(url: URL, onChange: @escaping @MainActor () -> Void) {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { MainActor.checkIsolated { onChange() } }
        source.setCancelHandler { [fileDescriptor] in close(fileDescriptor) }
        source.activate()
    }

    deinit { source.cancel() }
}

@MainActor
final class WorkspaceSidebarTasksStore: ObservableObject {
    @Published private(set) var agenda = WorkspaceSidebarTasksAgenda(day: .today, projects: [], errorMessage: nil)

    private let tasksRoot: URL
    private var watchers: [WorkspaceSidebarTasksPathWatcher] = []
    private var refreshTask: Task<Void, Never>?

    init(tasksRoot: URL) {
        self.tasksRoot = tasksRoot
        refresh()
    }

    func refresh() {
        agenda = WorkspaceSidebarTasksReader.load(tasksRoot: tasksRoot)
        installWatchers()
    }

    private func installWatchers() {
        let onChange: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            self.refreshTask?.cancel()
            self.refreshTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
        let projectURLs = (try? FileManager.default.contentsOfDirectory(
            at: tasksRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        watchers = ([tasksRoot] + projectURLs).compactMap {
            WorkspaceSidebarTasksPathWatcher(url: $0, onChange: onChange)
        }
    }
}

struct WorkspaceSidebarTasksWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    @StateObject private var store: WorkspaceSidebarTasksStore

    init(id: String, sectionWidth: CGFloat, isCompact: Bool, tasksPath: String) {
        self.id = id
        self.sectionWidth = sectionWidth
        self.isCompact = isCompact
        _store = StateObject(wrappedValue: WorkspaceSidebarTasksStore(
            tasksRoot: URL(filePath: tasksPath, directoryHint: .isDirectory)
        ))
    }

    var body: some View {
        expandedWidget
        .id(id)
        .accessibilityElement(children: .contain)
    }

    private var expandedWidget: some View {
        VStack(alignment: .leading, spacing: standardGap * 0) {
            Group {
                if let errorMessage = store.agenda.errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(workspaceSidebarWidgetSemanticColor(.red, .color9))
                } else if store.agenda.projects.isEmpty {
                    Text("Nothing scheduled today")
                        .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                } else {
                    VStack(alignment: .leading, spacing: standardGap * 4) {
                        ForEach(store.agenda.projects.prefix(4)) { project in
                            projectRow(project)
                        }
                    }
                }
            }
            .font(.system(size: 11, weight: .regular))
        }
        .padding(.horizontal, standardGap * 8)
        .padding(.vertical, standardGap * 7.5)
        .frame(width: sectionWidth, alignment: .leading)
        .background(WorkspaceSidebarStatusCardBackground())
    }

    private func projectRow(_ project: WorkspaceSidebarAgendaProject) -> some View {
        HStack(alignment: .center, spacing: standardGap * 3.5) {
            Circle()
                .fill(workspaceSidebarWidgetContent(.primary))
                .frame(width: 4, height: 4)

            Text(project.name)
                .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                .lineLimit(1)

            Spacer(minLength: 4)

            Text(project.hoursText)
                .font(.system(size: 10, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
        }
    }
}
