@testable import AppBundle
import Foundation
import XCTest

final class WorkspaceSidebarScheduleHeatmapWidgetTest: XCTestCase {
    func testScheduleHeatmapAggregatorFulfillsWithAggregateUnionCoverage() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-03 Session 1.md"),
            from: "2026-06-03T10:00",
            to: "2026-06-03T12:00",
        )
        try writeTogglEntry(
            workspace.toggl.appending(component: "entry-one.md"),
            start: "2026-06-03 10:00:00",
            stop: "2026-06-03 11:00:00",
        )
        try writeTogglEntry(
            workspace.toggl.appending(component: "entry-overlap.md"),
            start: "2026-06-03 10:30:00",
            stop: "2026-06-03 11:30:00",
        )
        try writeTogglEntry(
            workspace.toggl.appending(component: "entry-two.md"),
            start: "2026-06-03 11:30:00",
            stop: "2026-06-03 11:40:00",
        )

        let snapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: workspace.deviation,
            days: 7,
        ).load(now: try date("2026-06-04 12:00:00"))

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.fulfilledCount, 1)
        assertEquals(snapshot.reflectedCount, 0)
        assertEquals(snapshot.unfulfilledCount, 0)
        assertEquals(snapshot.scannedTogglEntryCount, 3)

        let cell = try XCTUnwrap(snapshot.days.flatMap(\.cells).first)
        assertEquals(cell.status, .fulfilled)
        assertEquals(Int(cell.coveredSeconds), 6000)
    }

    func testScheduleHeatmapAggregatorFallsBackToReflectedOrUnfulfilledAndHidesPending() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-03 Session 1.md"),
            from: "2026-06-03T10:00",
            to: "2026-06-03T12:00",
        )
        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-03 Session 2.md"),
            from: "2026-06-03T13:00",
            to: "2026-06-03T15:00",
        )
        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-04 Session 1.md"),
            from: "2026-06-04T10:00",
            to: "2026-06-04T12:00",
        )
        try writeDeviation(workspace.deviation.appending(component: "2026-06-03 Session 1.md"))

        let snapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: workspace.deviation,
            days: 7,
        ).load(now: try date("2026-06-04 09:00:00"))

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.fulfilledCount, 0)
        assertEquals(snapshot.reflectedCount, 1)
        assertEquals(snapshot.unfulfilledCount, 1)
        assertEquals(snapshot.scannedScheduleCount, 3)
        assertEquals(snapshot.days.flatMap(\.cells).map(\.identity), [
            "2026-06-03 Session 1",
            "2026-06-03 Session 2",
        ])
        assertEquals(snapshot.days.flatMap(\.cells).map(\.status), [.reflected, .unfulfilled])
    }

    func testScheduleHeatmapAggregatorFindsDeviationInVaultRootDeviationFolder() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        let vaultRoot = workspace.root.appending(component: "vault", directoryHint: .isDirectory)
        let nestedDeviation = vaultRoot.appending(component: "Deviation", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: nestedDeviation, withIntermediateDirectories: true)

        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-03 Session 1.md"),
            from: "2026-06-03T10:00",
            to: "2026-06-03T12:00",
        )
        try writeDeviation(nestedDeviation.appending(component: "2026-06-03 Session 1.md"))

        let snapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: vaultRoot,
            days: 7,
        ).load(now: try date("2026-06-04 12:00:00"))

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.reflectedCount, 1)
        assertEquals(snapshot.days.flatMap(\.cells).map(\.status), [.reflected])
    }

    func testScheduleHeatmapAggregatorUsesFilenameDateForGridAndFrontMatterForOverlap() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-04 Session 4.md"),
            from: "2026-06-03T17:30",
            to: "2026-06-03T19:00",
        )
        try writeTogglEntry(
            workspace.toggl.appending(component: "evening.md"),
            start: "2026-06-03 17:30:00",
            stop: "2026-06-03 19:00:00",
        )

        let snapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: workspace.deviation,
            days: 7,
        ).load(now: try date("2026-06-04 20:00:00"))

        let cell = try XCTUnwrap(snapshot.days.flatMap(\.cells).first)
        assertEquals(cell.identity, "2026-06-04 Session 4")
        assertEquals(cell.status, .fulfilled)
        assertEquals(dateKey(cell.date), "2026-06-04")
        assertEquals(dateKey(cell.from), "2026-06-03")
    }

    func testScheduleHeatmapAggregatorShowsOnlyCurrentWeek() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-14 Session 1.md"),
            from: "2026-06-14T10:00",
            to: "2026-06-14T12:00",
        )
        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-15 Session 1.md"),
            from: "2026-06-15T10:00",
            to: "2026-06-15T12:00",
        )
        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-21 Session 1.md"),
            from: "2026-06-21T10:00",
            to: "2026-06-21T12:00",
        )
        try writeSchedule(
            workspace.schedule.appending(component: "2026-06-22 Session 1.md"),
            from: "2026-06-22T10:00",
            to: "2026-06-22T12:00",
        )

        let snapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: workspace.deviation,
            days: 14,
        ).load(now: try date("2026-06-18 12:00:00"))

        assertEquals(snapshot.days.count, 7)
        assertEquals(snapshot.days.map { weekday($0.date) }, [
            "Mon",
            "Tue",
            "Wed",
            "Thu",
            "Fri",
            "Sat",
            "Sun",
        ])
        assertEquals(snapshot.days.flatMap(\.cells).map(\.identity), [
            "2026-06-15 Session 1",
        ])
    }

    func testScheduleHeatmapAggregatorReportsMissingDirectories() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace.root) }

        let missingSchedule = workspace.root.appending(component: "missing-schedule", directoryHint: .isDirectory)
        let missingToggl = workspace.root.appending(component: "missing-toggl", directoryHint: .isDirectory)

        let missingScheduleSnapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: missingSchedule,
            togglEntriesDirectory: workspace.toggl,
            deviationDirectory: workspace.deviation,
            days: 7,
        ).load(now: try date("2026-06-04 20:00:00"))
        assertEquals(missingScheduleSnapshot.errorMessage, "Can't read schedules")

        let missingTogglSnapshot = ScheduleHeatmapAggregator(
            scheduleDirectory: workspace.schedule,
            togglEntriesDirectory: missingToggl,
            deviationDirectory: workspace.deviation,
            days: 7,
        ).load(now: try date("2026-06-04 20:00:00"))
        assertEquals(missingTogglSnapshot.errorMessage, "Can't read Toggl entries")
    }

    private func makeWorkspace() throws -> (
        root: URL,
        schedule: URL,
        toggl: URL,
        deviation: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(component: "winmux-schedule-heatmap-\(UUID().uuidString)", directoryHint: .isDirectory)
        let schedule = root.appending(component: "schedule", directoryHint: .isDirectory)
        let toggl = root.appending(component: "toggl", directoryHint: .isDirectory)
        let deviation = root.appending(component: "deviation", directoryHint: .isDirectory)

        try FileManager.default.createDirectory(at: schedule, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toggl, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: deviation, withIntermediateDirectories: true)

        return (root, schedule, toggl, deviation)
    }

    private func writeSchedule(_ url: URL, from: String, to: String) throws {
        let sessionName = url.deletingPathExtension().lastPathComponent.components(separatedBy: " ").suffix(2).joined(separator: " ")
        let text =
            """
            ---
            session_name: \(sessionName)
            project:
            from: \(from)
            to: \(to)
            Estimated: 2
            Actual:
            ddl:
            done:
            ---
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeTogglEntry(_ url: URL, start: String, stop: String) throws {
        let text =
            """
            ---
            start: "\(start)"
            stop: "\(stop)"
            duration: 0
            project: "Test"
            description: ""
            tags:
            ---
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func writeDeviation(_ url: URL) throws {
        try "---\n---\n".write(to: url, atomically: true, encoding: .utf8)
    }

    private func date(_ raw: String) throws -> Date {
        try XCTUnwrap(makeDateFormatter().date(from: raw))
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = makeDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func weekday(_ date: Date) -> String {
        let formatter = makeDateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date)
    }

    private func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
