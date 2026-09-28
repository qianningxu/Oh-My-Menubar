import Foundation
import SwiftUI

private let menuBarWeeklyTasksRefreshInterval: TimeInterval = 2

struct MenuBarWeeklyTask: Identifiable, Equatable {
    let fileURL: URL
    let title: String
    let projectName: String
    let plannedDate: Date
    let estimatedHours: Double?
    let isCompleted: Bool

    var id: String { fileURL.path }
}

struct MenuBarWeeklyTaskProject: Identifiable {
    let name: String
    let tasks: [MenuBarWeeklyTask]

    var id: String { name }
    var completedCount: Int { tasks.filter(\.isCompleted).count }
}

struct MenuBarWeeklyTasksSnapshot: Equatable {
    let weekStart: Date
    let weekEnd: Date
    let tasks: [MenuBarWeeklyTask]

    var completedCount: Int { tasks.filter(\.isCompleted).count }
    var totalCount: Int { tasks.count }

    var projects: [MenuBarWeeklyTaskProject] {
        Dictionary(grouping: tasks, by: \.projectName)
            .map { MenuBarWeeklyTaskProject(name: $0.key, tasks: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
    }
}

struct MenuBarWeeklyTasksLoader {
    let baseURL: URL

    func load(now: Date = .now) -> MenuBarWeeklyTasksSnapshot {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return MenuBarWeeklyTasksSnapshot(weekStart: now, weekEnd: now, tasks: [])
        }

        guard let baseContents = try? String(contentsOf: baseURL, encoding: .utf8),
              let folders = TaskViewFilter(baseContents: baseContents)?.folders
        else {
            return MenuBarWeeklyTasksSnapshot(weekStart: week.start, weekEnd: week.end, tasks: [])
        }

        let vaultURL = baseURL.deletingLastPathComponent().deletingLastPathComponent()
        let fileManager = FileManager.default
        var tasks: [MenuBarWeeklyTask] = []

        for folder in folders {
            let folderURL = vaultURL.appending(path: folder, directoryHint: .isDirectory)
            guard let enumerator = fileManager.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let taskURL as URL in enumerator where taskURL.pathExtension.caseInsensitiveCompare("md") == .orderedSame {
                guard let contents = try? String(contentsOf: taskURL, encoding: .utf8),
                      let frontmatter = ProjectFrontmatter(contents: contents),
                      let plannedDate = frontmatter.date(for: "planed")
                else { continue }

                let plannedDay = calendar.startOfDay(for: plannedDate)
                guard plannedDay >= week.start, plannedDay < week.end else { continue }

                let projectName = frontmatter.values(for: "project").first.map(frontmatter.linkDisplayName) ?? "Unassigned"
                tasks.append(
                    MenuBarWeeklyTask(
                        fileURL: taskURL,
                        title: taskURL.deletingPathExtension().lastPathComponent,
                        projectName: projectName,
                        plannedDate: plannedDate,
                        estimatedHours: frontmatter.values(matchingProperty: "Estimated").first.flatMap(Double.init),
                        isCompleted: frontmatter.bool(for: "completed")
                    )
                )
            }
        }

        tasks.sort {
            if $0.plannedDate != $1.plannedDate { return $0.plannedDate < $1.plannedDate }
            if $0.projectName != $1.projectName {
                return $0.projectName.localizedStandardCompare($1.projectName) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        return MenuBarWeeklyTasksSnapshot(weekStart: week.start, weekEnd: week.end, tasks: tasks)
    }
}

@MainActor
final class MenuBarWeeklyTasksModel: ObservableObject {
    static let shared = MenuBarWeeklyTasksModel()

    @Published private(set) var snapshot: MenuBarWeeklyTasksSnapshot
    @Published private(set) var feedback: MenuBarWeeklyTasksFeedback?
    @Published private(set) var startingTaskIDs: Set<String> = []

    private let baseURL = URL(filePath: menuBarProjectsBasePath)
    private var lastRefreshAt = Date.distantPast
    private var feedbackExpiration: Task<Void, Never>?

    private init() {
        snapshot = MenuBarWeeklyTasksLoader(baseURL: baseURL).load()
    }

    func refreshContinuously() async {
        while !Task.isCancelled {
            refresh(now: .now)
            do {
                try await Task.sleep(nanoseconds: UInt64(menuBarWeeklyTasksRefreshInterval * 1_000_000_000))
            } catch {
                return
            }
        }
    }

    func refresh(now: Date = .now, force: Bool = false) {
        guard force || now.timeIntervalSince(lastRefreshAt) >= menuBarWeeklyTasksRefreshInterval else { return }
        lastRefreshAt = now
        let refreshed = MenuBarWeeklyTasksLoader(baseURL: baseURL).load(now: now)
        if refreshed != snapshot {
            snapshot = refreshed
        }
    }

    func toggleCompletion(for task: MenuBarWeeklyTask) {
        do {
            try MenuBarWeeklyTaskFrontmatterWriter.setCompleted(
                !task.isCompleted,
                expectedCurrentValue: task.isCompleted,
                at: task.fileURL
            )
            refresh(force: true)
            clearFeedback()
        } catch {
            refresh(force: true)
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    func startTracking(_ task: MenuBarWeeklyTask) async {
        guard !startingTaskIDs.contains(task.id) else { return }
        startingTaskIDs.insert(task.id)
        defer { startingTaskIDs.remove(task.id) }

        do {
            let settings = try MenuBarWeeklyTasksTogglSettings.load(for: task, baseURL: baseURL)
            let alreadyRunning = try await MenuBarWeeklyTasksTogglClient(settings: settings).startTimeEntry(
                description: task.title
            )
            let action = alreadyRunning ? "Already tracking" : "Started Toggl timer for"
            showFeedback("\(action) “\(task.title)” · \(task.projectName)", isError: false)
        } catch {
            showFeedback(error.localizedDescription, isError: true)
        }
    }

    private func showFeedback(_ message: String, isError: Bool) {
        feedbackExpiration?.cancel()
        let next = MenuBarWeeklyTasksFeedback(message: message, isError: isError)
        feedback = next
        feedbackExpiration = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            } catch {
                return
            }
            guard self?.feedback?.id == next.id else { return }
            self?.feedback = nil
        }
    }

    private func clearFeedback() {
        feedbackExpiration?.cancel()
        feedbackExpiration = nil
        feedback = nil
    }
}

struct MenuBarWeeklyTasksFeedback: Identifiable {
    let id = UUID()
    let message: String
    let isError: Bool
}

private enum MenuBarWeeklyTaskFrontmatterError: LocalizedError {
    case unreadableTask
    case taskChangedInObsidian
    case missingCompletedProperty

    var errorDescription: String? {
        switch self {
            case .unreadableTask: "Could not read this task file."
            case .taskChangedInObsidian: "This task changed in Obsidian. The list has been refreshed."
            case .missingCompletedProperty: "This task has no valid completed property."
        }
    }
}

private enum MenuBarWeeklyTaskFrontmatterWriter {
    static func setCompleted(
        _ completed: Bool,
        expectedCurrentValue: Bool,
        at url: URL
    ) throws {
        let contents = try String(contentsOf: url, encoding: .utf8)
        guard let frontmatter = ProjectFrontmatter(contents: contents) else {
            throw MenuBarWeeklyTaskFrontmatterError.unreadableTask
        }

        let currentValue = frontmatter.values(matchingProperty: "completed").first?.lowercased()
        let currentCompleted: Bool?
        switch currentValue {
            case "true": currentCompleted = true
            case "false", nil: currentCompleted = false
            default: currentCompleted = nil
        }
        guard let currentCompleted else {
            throw MenuBarWeeklyTaskFrontmatterError.missingCompletedProperty
        }
        guard currentCompleted == expectedCurrentValue else {
            throw MenuBarWeeklyTaskFrontmatterError.taskChangedInObsidian
        }

        let newline = contents.contains("\r\n") ? "\r\n" : "\n"
        var lines = contents.components(separatedBy: newline)
        guard let closingIndex = lines.dropFirst().firstIndex(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            throw MenuBarWeeklyTaskFrontmatterError.unreadableTask
        }

        if let propertyIndex = lines[..<closingIndex].firstIndex(where: { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            return normalizedTaskPropertyName(String(line[..<colon])) == "completed"
        }) {
            let line = lines[propertyIndex]
            guard let colon = line.firstIndex(of: ":") else {
                throw MenuBarWeeklyTaskFrontmatterError.unreadableTask
            }
            let prefix = String(line[...colon])
            let remainder = String(line[line.index(after: colon)...])
            let commentIndex = remainder.firstIndex(of: "#")
            let valuePart = commentIndex.map { String(remainder[..<$0]) } ?? remainder
            let comment = commentIndex.map { String(remainder[$0...]) } ?? ""
            let leadingWhitespace = String(valuePart.prefix(while: { $0 == " " || $0 == "\t" }))
            let trailingWhitespace = String(valuePart.reversed().prefix(while: { $0 == " " || $0 == "\t" }).reversed())
            lines[propertyIndex] = prefix + leadingWhitespace + String(completed) + trailingWhitespace + comment
        } else {
            lines.insert("completed: \(completed)", at: closingIndex)
        }

        try lines.joined(separator: newline).write(to: url, atomically: true, encoding: .utf8)
    }
}

private func normalizedTaskPropertyName(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .lowercased()
}

struct MenuBarWeeklyTasksCapsule: View {
    let height: CGFloat

    @StateObject private var model = MenuBarWeeklyTasksModel.shared

    var body: some View {
        HStack(spacing: menuBarWidgetSpacing) {
            Image(systemName: "checklist")
                .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                .foregroundStyle(menuBarWidgetIcon)
            Text("Tasks - \(model.snapshot.completedCount)/\(model.snapshot.totalCount)")
                .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                .monospacedDigit()
        }
        .menuBarWidgetItem(height: height, chartKind: .weeklyTasks)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text("This week: \(model.snapshot.completedCount) of \(model.snapshot.totalCount) tasks completed")
        )
        .background(MenuBarChartHitRegion(kind: .weeklyTasks))
        .task { await model.refreshContinuously() }
    }
}

struct MenuBarWeeklyTasksPopover: View {
    @StateObject private var model = MenuBarWeeklyTasksModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.regular) {
            if let feedback = model.feedback {
                Text(feedback.message)
                    .font(.system(size: menuBarWidgetFontSize * 0.8))
                    .foregroundStyle(
                        feedback.isError
                            ? workspaceSidebarWidgetSemanticColor(.red, .color9)
                            : workspaceSidebarWidgetContent(.secondary)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            if model.snapshot.tasks.isEmpty {
                Text("No tasks planned this week.")
                    .font(.system(size: menuBarWidgetFontSize))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: WinMuxSpacing.section) {
                        ForEach(model.snapshot.projects) { project in
                            MenuBarWeeklyTaskProjectSection(project: project, model: model)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task { await model.refreshContinuously() }
    }
}

private struct MenuBarWeeklyTaskProjectSection: View {
    let project: MenuBarWeeklyTaskProject
    @ObservedObject var model: MenuBarWeeklyTasksModel

    var body: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.compact) {
            HStack {
                Text(project.name)
                    .font(.system(size: menuBarWidgetFontSize, weight: .semibold))
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                Spacer(minLength: WinMuxSpacing.compact)
                Text("\(project.completedCount)/\(project.tasks.count)")
                    .font(.system(size: menuBarWidgetFontSize * 0.8, weight: .medium, design: .monospaced))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
            }

            VStack(alignment: .leading, spacing: WinMuxSpacing.compact) {
                ForEach(project.tasks) { task in
                    MenuBarWeeklyTaskRow(task: task, model: model)
                }
            }
        }
    }
}

private struct MenuBarWeeklyTaskRow: View {
    let task: MenuBarWeeklyTask
    @ObservedObject var model: MenuBarWeeklyTasksModel

    var body: some View {
        HStack(alignment: .center, spacing: WinMuxSpacing.compact) {
            Button {
                model.toggleCompletion(for: task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: menuBarWidgetIconSize))
                    .foregroundStyle(
                        task.isCompleted
                            ? workspaceSidebarWidgetSemanticColor(.green, .color9)
                            : workspaceSidebarWidgetContent(.secondary)
                    )
            }
            .buttonStyle(.plain)
            .help(task.isCompleted ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(task.isCompleted ? "Mark \(task.title) incomplete" : "Mark \(task.title) complete")

            VStack(alignment: .leading, spacing: WinMuxSpacing.hairline) {
                Text(task.title)
                    .font(.system(size: menuBarWidgetFontSize * 0.85))
                    .foregroundStyle(workspaceSidebarWidgetContent(task.isCompleted ? .secondary : .primary))
                    .strikethrough(task.isCompleted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Estimated: \(task.estimatedHours.map { "\($0.formatted(.number.precision(.fractionLength(0...2))))h" } ?? "—")")
                    .font(.system(size: menuBarWidgetFontSize * 0.7))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(task.plannedDate.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(.system(size: menuBarWidgetFontSize * 0.7, weight: .regular, design: .monospaced))
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))

            Button {
                Task { await model.startTracking(task) }
            } label: {
                if model.startingTaskIDs.contains(task.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: WinMuxSpacing.section)
                } else {
                    Label("Start", systemImage: "play.fill")
                        .font(.system(size: menuBarWidgetFontSize * 0.75, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.startingTaskIDs.contains(task.id))
            .help("Start Toggl timer")
            .accessibilityLabel("Start Toggl timer for \(task.title)")
        }
        .padding(.vertical, WinMuxSpacing.hairline)
    }
}

private struct MenuBarWeeklyTasksTogglSettings {
    let apiToken: String
    let workspaceID: Int
    let projectID: Int

    static func load(for task: MenuBarWeeklyTask, baseURL: URL) throws -> Self {
        let vaultURL = baseURL.deletingLastPathComponent().deletingLastPathComponent()
        let settingsURL = vaultURL.appending(path: ".obsidian/plugins/project-task-folders/data.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw MenuBarWeeklyTasksTogglError.settingsUnavailable }

        guard settings["togglEnabled"] as? Bool == true else {
            throw MenuBarWeeklyTasksTogglError.togglDisabled
        }
        guard let token = (settings["togglApiToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { throw MenuBarWeeklyTasksTogglError.tokenMissing }
        guard let workspaceID = Self.positiveInteger(settings["togglWorkspaceId"]) else {
            throw MenuBarWeeklyTasksTogglError.workspaceMissing
        }

        let tasksFolder = (settings["tasksFolder"] as? String).flatMap(Self.cleanPath) ?? "Others/Tasks"
        let projectsFolder = (settings["projectsFolder"] as? String).flatMap(Self.cleanPath) ?? "Others/Projects"
        let archiveFolderName = (settings["archiveFolderName"] as? String).flatMap(Self.cleanPath) ?? "archived"
        let tasksRootPath = vaultURL.appending(path: tasksFolder).path
        guard task.fileURL.path.hasPrefix(tasksRootPath + "/") else {
            throw MenuBarWeeklyTasksTogglError.projectUnavailable(task.projectName)
        }
        let relativeTaskPath = String(task.fileURL.path.dropFirst(tasksRootPath.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let taskPathComponents = relativeTaskPath.split(separator: "/").map(String.init)
        guard taskPathComponents.count >= 2,
              taskPathComponents[0] != archiveFolderName
        else { throw MenuBarWeeklyTasksTogglError.projectUnavailable(task.projectName) }

        let projectFolderName = taskPathComponents[0]
        let projectRelativePath = "\(projectsFolder)/\(projectFolderName).md"
        let projectURL = vaultURL.appending(path: projectRelativePath, directoryHint: .notDirectory)
        guard let projectContents = try? String(contentsOf: projectURL, encoding: .utf8),
              let projectFrontmatter = ProjectFrontmatter(contents: projectContents)
        else { throw MenuBarWeeklyTasksTogglError.projectUnavailable(projectFolderName) }

        let statusProperty = (settings["statusProperty"] as? String).flatMap(Self.cleanPath) ?? "Status"
        let activeStatus = (settings["activeStatus"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "In progress"
        guard projectFrontmatter.values(matchingProperty: statusProperty)
            .contains(where: { Self.normalizedValue($0) == Self.normalizedValue(activeStatus) })
        else { throw MenuBarWeeklyTasksTogglError.projectUnavailable(projectFolderName) }

        let togglProjectIDProperty = (settings["togglProjectIdProperty"] as? String)
            .flatMap(Self.cleanPath) ?? "toggl_project_id"
        let frontmatterProjectID = projectFrontmatter.values(matchingProperty: togglProjectIDProperty)
            .first.flatMap(Self.positiveInteger)
        let mappedProjectIDs = settings["togglProjectIds"] as? [String: Any] ?? [:]
        let projectID = frontmatterProjectID
            ?? Self.positiveInteger(mappedProjectIDs[projectRelativePath])
        guard let projectID else {
            throw MenuBarWeeklyTasksTogglError.projectNotLinked(projectFolderName)
        }

        return Self(apiToken: token, workspaceID: workspaceID, projectID: projectID)
    }

    private static func cleanPath(_ value: String) -> String? {
        let cleaned = value.trimmingCharacters(in: CharacterSet(charactersIn: " /\\\t\n"))
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func normalizedValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        let number: Double?
        if let value = value as? String {
            number = Double(value)
        } else if let value = value as? NSNumber {
            number = value.doubleValue
        } else {
            number = nil
        }
        guard let number, number.isFinite, number > 0,
              number.rounded() == number, number < Double(Int.max)
        else { return nil }
        return Int(number)
    }
}

private enum MenuBarWeeklyTasksTogglError: LocalizedError {
    case settingsUnavailable
    case togglDisabled
    case tokenMissing
    case workspaceMissing
    case projectUnavailable(String)
    case projectNotLinked(String)
    case invalidResponse
    case requestFailed(method: String, path: String, status: Int, detail: String)

    var errorDescription: String? {
        switch self {
            case .settingsUnavailable: "Could not read the Obsidian task plugin settings."
            case .togglDisabled: "Toggl is disabled in the Obsidian task plugin settings."
            case .tokenMissing: "The Toggl API token is missing from the Obsidian task plugin settings."
            case .workspaceMissing: "The Toggl workspace ID is invalid in the Obsidian task plugin settings."
            case let .projectUnavailable(project): "The active Obsidian project “\(project)” could not be found."
            case let .projectNotLinked(project): "No Toggl project is linked to “\(project)”. Run project sync first."
            case .invalidResponse: "Toggl returned an invalid response."
            case let .requestFailed(method, path, status, detail):
                "Toggl API \(method) \(path) failed (\(status))\(detail.isEmpty ? "" : ": \(detail)")"
        }
    }
}

private struct MenuBarWeeklyTasksTogglClient {
    let settings: MenuBarWeeklyTasksTogglSettings

    func startTimeEntry(description: String) async throws -> Bool {
        let currentData = try await request(method: "GET", path: "/me/time_entries/current")
        let current = try readCurrentTimeEntry(from: currentData)
        if current?.description == description, current?.projectID == settings.projectID {
            return true
        }

        if let current {
            _ = try await request(
                method: "PATCH",
                path: "/workspaces/\(settings.workspaceID)/time_entries/\(current.id)/stop"
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let body: [String: Any] = [
            "created_with": "obsidian-project-task-folders",
            "description": description,
            "duration": -1,
            "project_id": settings.projectID,
            "start": formatter.string(from: .now),
            "workspace_id": settings.workspaceID,
        ]
        let createdData = try await request(
            method: "POST",
            path: "/workspaces/\(settings.workspaceID)/time_entries",
            body: body
        )
        guard (try? readCurrentTimeEntry(from: createdData)) != nil else {
            throw MenuBarWeeklyTasksTogglError.invalidResponse
        }
        return false
    }

    private func request(method: String, path: String, body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "https://api.track.toggl.com/api/v9\(path)") else {
            throw MenuBarWeeklyTasksTogglError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(settings.apiToken):api_token".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw MenuBarWeeklyTasksTogglError.invalidResponse
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            let detail = Self.errorDetail(from: data)
                .replacingOccurrences(of: settings.apiToken, with: "[redacted]")
            throw MenuBarWeeklyTasksTogglError.requestFailed(
                method: method,
                path: path,
                status: response.statusCode,
                detail: detail
            )
        }
        return data
    }

    private func readCurrentTimeEntry(from data: Data) throws -> MenuBarWeeklyTasksTogglEntry? {
        guard let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw MenuBarWeeklyTasksTogglError.invalidResponse
        }
        if value is NSNull { return nil }
        guard let entry = value as? [String: Any],
              let id = Self.integer(entry["id"]),
              let duration = Self.number(entry["duration"]), duration.isFinite,
              let startedAt = entry["start"] as? String
        else { throw MenuBarWeeklyTasksTogglError.invalidResponse }
        let projectValue = entry["project_id"] ?? entry["pid"]
        let projectID = projectValue is NSNull ? nil : Self.integer(projectValue)
        return MenuBarWeeklyTasksTogglEntry(
            id: id,
            description: entry["description"] as? String ?? "",
            projectID: projectID,
            duration: duration,
            startedAt: startedAt
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber {
            let number = value.doubleValue
            guard number.isFinite, number.rounded() == number, number < Double(Int.max) else { return nil }
            return Int(number)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func errorDetail(from data: Data) -> String {
        guard !data.isEmpty else { return "" }
        if let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let detail = value["message"] ?? value["error"] ?? value["detail"] {
            return String(describing: detail).prefix(300).description
        }
        return String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MenuBarWeeklyTasksTogglEntry {
    let id: Int
    let description: String
    let projectID: Int?
    let duration: Double
    let startedAt: String
}
