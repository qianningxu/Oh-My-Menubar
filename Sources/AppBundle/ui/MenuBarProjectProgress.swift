import Foundation
import SwiftUI

let menuBarProjectsBasePath = "/Users/side/Documents/now/my_app/self/self_ob/Others/tasks.base"
let menuBarProjectProgressRefreshInterval: TimeInterval = 5 * 60

struct MenuBarProjectProgress: Identifiable, Equatable {
    let name: String
    let timeProgress: Int
    let completedTaskCount: Int
    let totalTaskCount: Int
    let daysRemaining: Int?
    let priority: Double
    let ratio: Double

    var id: String { name }

    var remainingTaskCount: Int {
        max(0, totalTaskCount - completedTaskCount)
    }

    var widgetOrder: Int {
        ["mt3507_math_stats", "mt4112_numerical_methods", "mt4113_statistical_computing", "mt4511_asymptotic_methods"].firstIndex(of: name) ?? 4
    }

    var widgetName: String {
        switch name {
            case "mt3507_math_stats": "Math Stats"
            case "mt4112_numerical_methods": "Numerical"
            case "mt4113_statistical_computing": "Stat Computing"
            case "mt4511_asymptotic_methods": "Asymptotics"
            default: name
        }
    }
}

func menuBarVisibleProjectProgress(_ projects: [MenuBarProjectProgress]) -> [MenuBarProjectProgress] {
    projects.filter { $0.remainingTaskCount > 0 }
}

struct MenuBarProjectProgressLoader {
    let baseURL: URL

    func load(now: Date = .now) -> [MenuBarProjectProgress] {
        guard let baseContents = try? String(contentsOf: baseURL, encoding: .utf8),
              let filter = ProjectViewFilter(baseContents: baseContents),
              let taskFolders = TaskViewFilter(baseContents: baseContents)?.folders
        else { return [] }

        let vaultURL = baseURL.deletingLastPathComponent().deletingLastPathComponent()
        let projectsURL = vaultURL.appending(path: filter.folder, directoryHint: .isDirectory)
        guard let projectURLs = try? FileManager.default.contentsOfDirectory(
            at: projectsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let taskCounts = Self.taskCounts(
            in: vaultURL,
            folders: taskFolders
        )

        return projectURLs
            .filter { $0.pathExtension.caseInsensitiveCompare("md") == .orderedSame }
            .compactMap { projectURL in
                guard let contents = try? String(contentsOf: projectURL, encoding: .utf8),
                      let frontmatter = ProjectFrontmatter(contents: contents),
                      frontmatter.values(for: "Period").contains("Y4S1"),
                      frontmatter.values(for: "Status").contains(filter.status),
                      !filter.requiresPriority || frontmatter.number(for: "Priority") != nil
                else { return nil }

                let start = frontmatter.date(for: "start")
                let deadline = frontmatter.date(for: "ddl")
                return MenuBarProjectProgress(
                    name: projectURL.deletingPathExtension().lastPathComponent,
                    timeProgress: Self.timeProgress(start: start, deadline: deadline, now: now),
                    completedTaskCount: taskCounts[projectURL.deletingPathExtension().lastPathComponent]?.completed ?? 0,
                    totalTaskCount: taskCounts[projectURL.deletingPathExtension().lastPathComponent]?.total ?? 0,
                    daysRemaining: Self.daysRemaining(deadline: deadline, now: now),
                    priority: frontmatter.number(for: "Priority") ?? 0,
                    ratio: frontmatter.number(for: "ratio") ?? 0
                )
            }
            .sorted {
                if $0.widgetOrder != $1.widgetOrder { return $0.widgetOrder < $1.widgetOrder }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                if $0.ratio != $1.ratio { return $0.ratio > $1.ratio }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private static func timeProgress(start: Date?, deadline: Date?, now: Date) -> Int {
        guard let start, let deadline, deadline > start else { return 0 }
        let percentage = (now.timeIntervalSince(start) / deadline.timeIntervalSince(start)) * 100
        return Int(min(100, max(0, percentage)).rounded())
    }

    private static func daysRemaining(deadline: Date?, now: Date) -> Int? {
        guard let deadline else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: deadline)
        ).day
    }

    private static func taskCounts(in vaultURL: URL, folders: [String]) -> [String: (completed: Int, total: Int)] {
        var counts: [String: (completed: Int, total: Int)] = [:]
        let fileManager = FileManager.default

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
                      let project = frontmatter.values(for: "project").first
                else { continue }

                let projectName = frontmatter.linkDisplayName(project)
                let current = counts[projectName] ?? (completed: 0, total: 0)
                counts[projectName] = (
                    completed: current.completed + (frontmatter.bool(for: "completed") ? 1 : 0),
                    total: current.total + 1
                )
            }
        }

        return counts
    }
}

struct MenuBarProjectsProgressWidget: View {
    let height: CGFloat

    init(height: CGFloat = 24) {
        self.height = height
    }

    var body: some View {
        TimelineView(
            .periodic(
                from: Date(timeIntervalSinceReferenceDate: 0),
                by: menuBarProjectProgressRefreshInterval
            )
        ) { context in
            let projects = menuBarVisibleProjectProgress(
                MenuBarProjectProgressLoader(
                    baseURL: URL(filePath: menuBarProjectsBasePath)
                ).load(now: context.date)
            )

            HStack(spacing: standardGap * 0.75) {
                ForEach(projects) { project in
                    MenuBarProjectProgressItem(project: project)
                        .menuBarWidgetItem(height: height)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

struct MenuBarProjectProgressCapsule: View {
    let project: MenuBarProjectProgress
    let height: CGFloat

    var body: some View {
        MenuBarProjectProgressItem(project: project)
            .menuBarWidgetItem(height: height)
    }
}

private struct MenuBarProjectProgressItem: View {
    let project: MenuBarProjectProgress

    var body: some View {
        HStack(spacing: menuBarWidgetSpacing) {
            Text("\(project.widgetName) - \(project.completedTaskCount)/\(project.totalTaskCount)\(project.widgetOrder < 4 ? "" : " - \(deadlineText)")")
                .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                .monospacedDigit()
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            Text(
                "\(project.name), \(project.completedTaskCount) of \(project.totalTaskCount) tasks completed, \(deadlineAccessibilityText)"
            )
        )
    }

    private var deadlineText: String {
        guard let daysRemaining = project.daysRemaining else { return "—" }
        return "\(daysRemaining)d"
    }

    private var deadlineAccessibilityText: String {
        guard let daysRemaining = project.daysRemaining else { return "no deadline" }
        if daysRemaining < 0 { return "\(-daysRemaining) days overdue" }
        if daysRemaining == 0 { return "due today" }
        return "\(daysRemaining) days left"
    }
}

private struct ProjectViewFilter {
    let folder: String
    let status: String
    let requiresPriority: Bool

    init?(baseContents: String) {
        let viewBlocks = baseContents.components(separatedBy: "\n  - type:")
        guard let projectsView = viewBlocks.first(where: { $0.contains("\n    name: Projects") }) else {
            return nil
        }

        guard let folder = Self.quotedValue(in: projectsView, after: "file.folder =="),
              let status = Self.quotedValue(in: projectsView, after: "Status.contains(")
        else { return nil }

        self.folder = folder
        self.status = status
        requiresPriority = projectsView.contains("!Priority.isEmpty()")
    }

    private static func quotedValue(in source: String, after marker: String) -> String? {
        guard let markerRange = source.range(of: marker) else { return nil }
        let suffix = source[markerRange.upperBound...]
        guard let openingQuote = suffix.firstIndex(where: { $0 == "\"" || $0 == "'" }) else { return nil }
        let quote = suffix[openingQuote]
        let valueStart = suffix.index(after: openingQuote)
        guard let closingQuote = suffix[valueStart...].firstIndex(of: quote) else { return nil }
        return String(suffix[valueStart ..< closingQuote])
    }
}

private struct TaskViewFilter {
    let folders: [String]

    init?(baseContents: String) {
        let viewBlocks = baseContents.components(separatedBy: "\n  - type:")
        guard let tasksView = viewBlocks.first(where: { $0.contains("\n    name: Tasks") }) else {
            return nil
        }

        let pattern = #"file\.folder\.containsAny\(([^)]*)\)"#
        guard let expression = tasksView.range(of: pattern, options: .regularExpression).map({ String(tasksView[$0]) }) else {
            return nil
        }

        let expressionRange = NSRange(expression.startIndex..., in: expression)
        let quotedValuePattern = #"[\"']([^\"']+)[\"']"#
        let regex = try! NSRegularExpression(pattern: quotedValuePattern)
        folders = regex.matches(in: expression, range: expressionRange).compactMap { match in
            guard let range = Range(match.range(at: 1), in: expression) else { return nil }
            return String(expression[range])
        }
    }
}

private struct ProjectFrontmatter {
    private let properties: [String: [String]]

    init?(contents: String) {
        let lines = contents.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              })
        else { return nil }

        var properties: [String: [String]] = [:]
        var currentKey: String?
        for line in lines[1 ..< closingIndex] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- "), let currentKey {
                properties[currentKey, default: []].append(Self.clean(String(trimmed.dropFirst(2))))
                continue
            }
            guard let colon = line.firstIndex(of: ":") else {
                currentKey = nil
                continue
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                currentKey = nil
                continue
            }
            currentKey = key
            let rawValue = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            properties[key] = rawValue.isEmpty ? [] : [Self.clean(rawValue)]
        }
        self.properties = properties
    }

    func values(for key: String) -> [String] {
        properties[key] ?? []
    }

    func number(for key: String) -> Double? {
        values(for: key).first.flatMap(Double.init)
    }

    func bool(for key: String) -> Bool {
        values(for: key).first?.lowercased() == "true"
    }

    func linkDisplayName(_ rawValue: String) -> String {
        let value = Self.clean(rawValue)
        guard value.hasPrefix("[["), value.hasSuffix("]]" ) else { return value }
        let link = String(value.dropFirst(2).dropLast(2))
        return link.split(separator: "|", maxSplits: 1).last.map(String.init) ?? link
    }

    func date(for key: String) -> Date? {
        guard let rawValue = values(for: key).first else { return nil }
        return Self.dateFormatters.lazy.compactMap { $0.date(from: rawValue) }.first
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private static let dateFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd",
    ].map { format in
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
