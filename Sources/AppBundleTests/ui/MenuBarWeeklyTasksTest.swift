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

        func writeTask(_ title: String, planned: String?, completed: Bool) throws {
            let plannedProperty = planned.map { "planed: \($0)\n" } ?? ""
            try """
            ---
            \(plannedProperty)completed: \(completed)
            project: "[[Study]]"
            ---
            """.write(to: tasksURL.appendingPathComponent("\(title).md"), atomically: true, encoding: .utf8)
        }

        try writeTask("Old unfinished", planned: "2025-01-01", completed: false)
        try writeTask("Previous Sunday unfinished", planned: "2026-10-11", completed: false)
        try writeTask("Previous Sunday completed", planned: "2026-10-11", completed: true)
        try writeTask("Monday completed", planned: "2026-10-12", completed: true)
        try writeTask("Sunday unfinished", planned: "2026-10-18", completed: false)
        try writeTask("Next Monday unfinished", planned: "2026-10-19", completed: false)
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

        try writeTask("Old unfinished", planned: "2025-01-01", completed: true)
        let refreshed = loader.load(now: now)
        XCTAssertEqual(refreshed.tasks.map(\.title), [
            "Previous Sunday unfinished", "Monday completed", "Sunday unfinished",
        ])
        XCTAssertEqual(refreshed.totalCount, 3)
        XCTAssertEqual(refreshed.completedCount, 1)
    }
}
