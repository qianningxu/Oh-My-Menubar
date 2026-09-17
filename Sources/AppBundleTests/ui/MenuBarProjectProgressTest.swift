import Foundation
import XCTest
@testable import AppBundle

final class MenuBarProjectProgressTest: XCTestCase {
    func testProjectProgressRefreshesEveryFiveMinutes() {
        XCTAssertEqual(menuBarProjectProgressRefreshInterval, 5 * 60)
    }

    func testCourseProjectsUseCompactWidgetNames() {
        let names = [
            "mt3507_math_stats": "Math Stats",
            "mt4112_numerical_methods": "Numerical",
            "mt4113_statistical_computing": "Stat Computing",
            "mt4511_asymptotic_methods": "Asymptotics",
        ]
        for (name, expected) in names {
            let project = MenuBarProjectProgress(
                name: name,
                timeProgress: 0,
                completedTaskCount: 0,
                totalTaskCount: 0,
                daysRemaining: nil,
                priority: 1,
                ratio: 0
            )
            XCTAssertEqual(project.widgetName, expected)
        }
    }

    func testOnlyProjectsWithRemainingTasksAreVisible() {
        let active = MenuBarProjectProgress(
            name: "Active",
            timeProgress: 0,
            completedTaskCount: 2,
            totalTaskCount: 3,
            daysRemaining: nil,
            priority: 1,
            ratio: 0
        )
        let completed = MenuBarProjectProgress(
            name: "Completed",
            timeProgress: 100,
            completedTaskCount: 3,
            totalTaskCount: 3,
            daysRemaining: nil,
            priority: 1,
            ratio: 0
        )
        let empty = MenuBarProjectProgress(
            name: "Empty",
            timeProgress: 0,
            completedTaskCount: 0,
            totalTaskCount: 0,
            daysRemaining: nil,
            priority: 1,
            ratio: 0
        )

        XCTAssertEqual(menuBarVisibleProjectProgress([active, completed, empty]), [active])
    }

    func testLoadsEveryProjectMatchingProjectsViewFiltersAndSortsByPriority() throws {
        let fixture = try ProjectProgressFixture()
        defer { fixture.remove() }

        try fixture.writeBase()
        try fixture.writeProject(
            "Interview Q",
            frontmatter: """
            Period:
              - Y4S1
            Status: In progress
            Priority: 3
            ratio: 4
            start: 2026-08-22T00:00:00
            ddl: 2026-09-25
            """
        )
        try fixture.writeProject(
            "Leetcode",
            frontmatter: """
            Period: Y4S1
            Status:
              - In progress
            Priority: 2
            start: 2026-09-04T00:00:00
            ddl: 2026-09-25
            """
        )
        try fixture.writeProject(
            "Completed",
            frontmatter: """
            Period: Y4S1
            Status: Completed
            Priority: 9
            """
        )

        let now = try XCTUnwrap(ProjectProgressFixture.date("2026-09-04T12:00:00"))
        try fixture.writeProject("Old period", frontmatter: "Period: Y3 summer\nStatus: In progress\nPriority: 10")
        let projects = MenuBarProjectProgressLoader(baseURL: fixture.baseURL).load(now: now)

        XCTAssertEqual(projects.map(\.name), ["Interview Q", "Leetcode"])
        XCTAssertEqual(projects.map(\.completedTaskCount), [0, 0])
        XCTAssertEqual(projects.map(\.totalTaskCount), [0, 0])
        XCTAssertEqual(projects.map(\.daysRemaining), [21, 21])
        XCTAssertEqual(projects[0].timeProgress, 40)
        XCTAssertEqual(projects[1].timeProgress, 2)
    }

    func testCountsCompletedTasksInConfiguredTaskFolders() throws {
        let fixture = try ProjectProgressFixture()
        defer { fixture.remove() }

        try fixture.writeBase()
        try fixture.writeProject(
            "Interview Q",
            frontmatter: """
            Period: Y4S1
            Status: In progress
            Priority: 1
            start: 2026-09-01
            ddl: 2026-09-20
            """
        )

        try fixture.writeTask("Interview Q", "done", completed: true)
        try fixture.writeTask("Interview Q", "todo", completed: false)
        try fixture.writeTask("Different project", "ignored", completed: true)

        let now = try XCTUnwrap(ProjectProgressFixture.date("2026-09-04T12:00:00"))
        let project = try XCTUnwrap(MenuBarProjectProgressLoader(baseURL: fixture.baseURL).load(now: now).first)
        XCTAssertEqual(project.completedTaskCount, 1)
        XCTAssertEqual(project.totalTaskCount, 2)
    }
}

private final class ProjectProgressFixture {
    let rootURL: URL
    let vaultURL: URL
    let baseURL: URL
    let projectsURL: URL
    let tasksURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appending(
            path: "winmux-project-progress-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        vaultURL = rootURL.appending(path: "self_ob", directoryHint: .isDirectory)
        baseURL = vaultURL.appending(path: "Others/tasks.base")
        projectsURL = vaultURL.appending(path: "Others/Projects", directoryHint: .isDirectory)
        tasksURL = vaultURL.appending(path: "Others/Tasks/Interview Q", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: projectsURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tasksURL, withIntermediateDirectories: true)
    }

    func writeBase() throws {
        let contents = """
        views:
          - type: table
            name: Projects
            filters:
              and:
                - file.folder == "Others/Projects"
                - Period.contains("Y3 summer")
                - Status.contains("In progress")
                - "!Priority.isEmpty()"
          - type: table
            name: Tasks
            filters:
              and:
                - file.folder.containsAny("Others/Tasks/Interview Q")
        """
        try contents.write(to: baseURL, atomically: true, encoding: .utf8)
    }

    func writeTask(_ project: String, _ name: String, completed: Bool) throws {
        let contents = "---\ncompleted: \(completed)\nproject: \"[[\(project)]]\"\n---\n"
        try contents.write(
            to: tasksURL.appending(path: "\(name).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func writeProject(_ name: String, frontmatter: String) throws {
        let contents = "---\n\(frontmatter)\n---\n"
        try contents.write(
            to: projectsURL.appending(path: "\(name).md"),
            atomically: true,
            encoding: .utf8
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    static func date(_ rawValue: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: rawValue)
    }
}
