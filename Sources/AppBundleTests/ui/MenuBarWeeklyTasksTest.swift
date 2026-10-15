@testable import AppBundle
import Foundation
import XCTest

final class MenuBarWeeklyTasksTest: XCTestCase {
    func testIncludesUnfinishedEarlierTasksAndRefreshesAfterCompletion() throws {
        let vaultURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let tasksURL = vaultURL.appendingPathComponent("Others/Tasks")
        try FileManager.default.createDirectory(at: tasksURL, withIntermediateDirectories: true)
        let baseURL = vaultURL.appendingPathComponent("Others/tasks.base")
        try """
        views:
          - type: table
            name: Tasks
            filters:
              and:
                - file.folder.containsAny("Others/Tasks")
        """.write(to: baseURL, atomically: true, encoding: .utf8)

        func writeTask(_ title: String, planned: String?, completed: Bool, deadline: String? = nil) throws {
            let plannedProperty = planned.map { "planed: \($0)\n" } ?? ""
            let deadlineProperty = deadline.map { "ddl: \($0)\n" } ?? ""
            try """
            ---
            \(plannedProperty)\(deadlineProperty)completed: \(completed)
            project: "[[Study]]"
            ---
            """.write(to: tasksURL.appendingPathComponent("\(title).md"), atomically: true, encoding: .utf8)
        }

        try writeTask("Old unfinished", planned: "2025-01-01", completed: false)
        try writeTask("Previous Sunday unfinished", planned: "2026-10-11", completed: false)
        try writeTask("Previous Sunday completed", planned: "2026-10-11", completed: true)
        try writeTask("Monday completed", planned: "2026-10-12", completed: true, deadline: "2026-10-30T17:00:00")
        try writeTask("Sunday unfinished", planned: "2026-10-18", completed: false, deadline: "2026-10-25")
        try writeTask("Next Monday unfinished", planned: "2026-10-19", completed: false, deadline: "2026-10-11")
        try writeTask("Undated unfinished", planned: nil, completed: false)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        let now = try XCTUnwrap(formatter.date(from: "2026-10-15"))
        let loader = MenuBarWeeklyTasksLoader(baseURL: baseURL)
        let snapshot = loader.load(now: now)

        XCTAssertEqual(snapshot.tasks.map(\.title), [
            "Old unfinished", "Previous Sunday unfinished", "Monday completed", "Sunday unfinished",
        ])
        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.completedCount, 1)
        let timedDeadlineTask = try XCTUnwrap(snapshot.tasks.first { $0.title == "Monday completed" })
        XCTAssertEqual(timedDeadlineTask.plannedDate, formatter.date(from: "2026-10-12"))
        XCTAssertEqual(timedDeadlineTask.deadline, Calendar.current.date(
            bySettingHour: 17, minute: 0, second: 0, of: try XCTUnwrap(formatter.date(from: "2026-10-30"))
        ))
        XCTAssertEqual(timedDeadlineTask.deadlineIncludesTime, true)
        let dateOnlyDeadlineTask = try XCTUnwrap(snapshot.tasks.first { $0.title == "Sunday unfinished" })
        XCTAssertEqual(dateOnlyDeadlineTask.deadline, formatter.date(from: "2026-10-25"))
        XCTAssertEqual(dateOnlyDeadlineTask.deadlineIncludesTime, false)
        XCTAssertEqual(snapshot.tasks.first?.deadline, nil)

        try writeTask("Old unfinished", planned: "2025-01-01", completed: true)
        let refreshed = loader.load(now: now)
        XCTAssertEqual(refreshed.tasks.map(\.title), [
            "Previous Sunday unfinished", "Monday completed", "Sunday unfinished",
        ])
        XCTAssertEqual(refreshed.totalCount, 3)
        XCTAssertEqual(refreshed.completedCount, 1)
    }
}
