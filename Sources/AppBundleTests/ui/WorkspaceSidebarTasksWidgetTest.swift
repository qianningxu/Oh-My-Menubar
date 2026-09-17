import Foundation
import Testing
@testable import AppBundle

struct WorkspaceSidebarTasksWidgetTest {
    @Test func readsTodayAndIgnoresCompletedAndArchivedTasks() throws {
        let fixture = try TasksFixture()
        defer { fixture.remove() }

        try fixture.write(
            project: "Alpha",
            title: "Today task",
            frontmatter: """
            completed: false
            arrangement: '[{"date":"2026-07-30","hours":1.5}]'
            """
        )
        try fixture.write(
            project: "Alpha",
            title: "Done task",
            frontmatter: """
            completed: true
            arrangement: '[{"date":"2026-07-30","hours":4}]'
            """
        )
        try fixture.write(
            project: "archived/Old",
            title: "Archived task",
            frontmatter: """
            completed: false
            arrangement: '[{"date":"2026-07-30","hours":8}]'
            """
        )

        let agenda = WorkspaceSidebarTasksReader.load(
            tasksRoot: fixture.root,
            now: fixture.date("2026-07-30"),
            calendar: fixture.calendar
        )

        #expect(agenda.day == .today)
        #expect(agenda.errorMessage == nil)
        #expect(agenda.projects.map(\.name) == ["Alpha"])
        #expect(agenda.projects.first?.hours == 1.5)
        #expect(agenda.projects.first?.hoursText == "1.5h")
    }

    @Test func excludesTomorrowWhenTodayIsEmpty() throws {
        let fixture = try TasksFixture()
        defer { fixture.remove() }

        try fixture.write(
            project: "All of stats",
            title: "01 Probability",
            frontmatter: """
            arrangement: '[{"date":"2026-07-31","hours":4.5}]'
            """
        )
        try fixture.write(
            project: "Leetcode",
            title: "blind75",
            frontmatter: """
            arrangement: '[{"date":"2026-07-31","hours":1}]'
            """
        )

        let agenda = WorkspaceSidebarTasksReader.load(
            tasksRoot: fixture.root,
            now: fixture.date("2026-07-30"),
            calendar: fixture.calendar
        )

        #expect(agenda.day == .today)
        #expect(agenda.projects.isEmpty)
    }

    @Test func combinesTasksIntoProjectRows() throws {
        let fixture = try TasksFixture()
        defer { fixture.remove() }

        try fixture.write(
            project: "Alpha",
            title: "Today task",
            frontmatter: """
            arrangement: '[{"date":"2026-07-30","hours":1}]'
            """
        )
        try fixture.write(
            project: "Alpha",
            title: "Another today task",
            frontmatter: """
            arrangement: '[{"date":"2026-07-30","hours":2}]'
            """
        )

        let agenda = WorkspaceSidebarTasksReader.load(
            tasksRoot: fixture.root,
            now: fixture.date("2026-07-30"),
            calendar: fixture.calendar
        )

        #expect(agenda.day == .today)
        #expect(agenda.projects.map(\.name) == ["Alpha"])
        #expect(agenda.projects.first?.hours == 3)
    }

    @Test func combinesDuplicateArrangementEntriesForTheSameDate() throws {
        let fixture = try TasksFixture()
        defer { fixture.remove() }

        try fixture.write(
            project: "Alpha",
            title: "Split task",
            frontmatter: """
            arrangement: '[{"date":"2026-07-30","hours":1},{"date":"2026-07-30","hours":0.5}]'
            """
        )

        let agenda = WorkspaceSidebarTasksReader.load(
            tasksRoot: fixture.root,
            now: fixture.date("2026-07-30"),
            calendar: fixture.calendar
        )

        #expect(agenda.projects.first?.hours == 1.5)
    }
}

private struct TasksFixture {
    let root: URL
    let calendar: Calendar

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        self.calendar = calendar
    }

    func date(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: value + " 12:00:00")!
    }

    func write(project: String, title: String, frontmatter: String) throws {
        let projectURL = root.appending(path: project, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let contents = "---\n\(frontmatter)\n---\n"
        try contents.write(to: projectURL.appending(path: title + ".md"), atomically: true, encoding: .utf8)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
