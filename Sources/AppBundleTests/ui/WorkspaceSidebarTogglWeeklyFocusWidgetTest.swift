@testable import AppBundle
import Foundation
import XCTest

final class WorkspaceSidebarTogglWeeklyFocusWidgetTest: XCTestCase {
    @MainActor
    func testLoaderPublishesFreshSnapshotsOnEveryRefresh() async throws {
        let firstNow = try date("2026-09-04 12:00:00")
        let secondNow = try date("2026-09-04 12:01:00")
        let loader = WorkspaceSidebarTogglWeeklyFocusLoader { _, _, now in
            TogglWeeklyFocusSnapshot(totalWeekSeconds: now.timeIntervalSince1970)
        }
        let entriesDirectory = URL(filePath: "/tmp/toggl-weekly-focus", directoryHint: .isDirectory)

        await loader.refresh(entriesDirectory: entriesDirectory, targetDate: "2026-09-13", now: firstNow)
        assertEquals(loader.snapshot?.totalWeekSeconds, firstNow.timeIntervalSince1970)

        await loader.refresh(entriesDirectory: entriesDirectory, targetDate: "2026-09-13", now: secondNow)
        assertEquals(loader.snapshot?.totalWeekSeconds, secondNow.timeIntervalSince1970)
    }

    func testAggregatorBuildsCurrentWeekFocusByDay() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        let entriesDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-toggl-weekly-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: entriesDirectory) }

        try writeEntry(
            entriesDirectory.appending(component: "current-week.md"),
            start: "2026-06-16 06:00:00",
            stop: "2026-06-16 11:00:00",
        )
        try writeEntry(
            entriesDirectory.appending(component: "future-week.md"),
            start: "2026-06-22 10:00:00",
            stop: "2026-06-22 12:00:00",
        )

        let snapshot = TogglWeeklyFocusAggregator(
            entriesDirectory: entriesDirectory,
            targetDateString: "2026-09-13",
        ).load(now: try date("2026-06-16 12:00:00"))

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.weeks.map { dateKey($0.startDate) }, [
            "2026-06-14",
            "2026-06-21",
            "2026-06-28",
            "2026-07-05",
            "2026-07-12",
            "2026-07-19",
            "2026-07-26",
            "2026-08-02",
            "2026-08-09",
            "2026-08-16",
            "2026-08-23",
            "2026-08-30",
            "2026-09-06",
            "2026-09-13",
        ])
        assertEquals(dateKey(try XCTUnwrap(snapshot.weeks.last).endDate), "2026-09-13")
        assertEquals(snapshot.weeksLeft, 13)
        assertEquals(snapshot.weeks.first?.isCurrent, true)
        assertEquals(snapshot.weeks.dropFirst().allSatisfy(\.isFuture), true)
        assertEquals(Int((snapshot.averageDailySeconds / 60 / 60 * 10).rounded()), 17)
        assertEquals(Int((snapshot.currentWeekDailyAverageSeconds / 60 / 60 * 10).rounded()), 25)
        assertEquals(Int((snapshot.totalWeekSeconds / 60 / 60 * 10).rounded()), 50)
        assertEquals(snapshot.days.map { dateKey($0.date) }, [
            "2026-06-15",
            "2026-06-16",
            "2026-06-17",
            "2026-06-18",
            "2026-06-19",
            "2026-06-20",
            "2026-06-21",
        ])
        assertEquals(snapshot.days.map { Int(($0.totalSeconds / 60 / 60 * 10).rounded()) }, [0, 50, 0, 0, 0, 0, 0])
        assertEquals(snapshot.days.map(\.isToday), [false, true, false, false, false, false, false])
        assertEquals(snapshot.days.map(\.isFuture), [false, false, true, true, true, true, true])
        assertEquals(snapshot.weeks.dropFirst().map(\.totalSeconds), Array(repeating: TimeInterval(0), count: 13))
    }

    func testAggregatorReportsTargetAndDirectoryErrors() throws {
        let entriesDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-toggl-weekly-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: entriesDirectory) }

        let now = try date("2026-06-16 12:00:00")
        let invalidTarget = TogglWeeklyFocusAggregator(
            entriesDirectory: entriesDirectory,
            targetDateString: "13-09-2026",
        ).load(now: now)
        assertEquals(invalidTarget.errorMessage, "Invalid target date")

        let passedTarget = TogglWeeklyFocusAggregator(
            entriesDirectory: entriesDirectory,
            targetDateString: "2026-06-15",
        ).load(now: now)
        assertEquals(passedTarget.errorMessage, "Target date has passed")

        let missingDirectory = entriesDirectory.appending(component: "missing", directoryHint: .isDirectory)
        let missingEntries = TogglWeeklyFocusAggregator(
            entriesDirectory: missingDirectory,
            targetDateString: "2026-09-13",
        ).load(now: now)
        assertEquals(missingEntries.errorMessage, "Can't read Toggl entries")
    }

    func testWeekLabelTextUsesMonthMarkersAndOrdinalDays() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        let weeks = try [
            "2026-06-14",
            "2026-06-21",
            "2026-06-28",
            "2026-07-05",
            "2026-07-12",
            "2026-07-19",
            "2026-07-26",
            "2026-08-02",
            "2026-08-09",
            "2026-08-16",
            "2026-08-23",
            "2026-08-30",
            "2026-09-06",
            "2026-09-13",
        ].map(week)

        assertEquals(weeks.indices.map { index in
            togglWeeklyFocusWeekLabelText(
                for: weeks[index],
                previousWeek: index == 0 ? nil : weeks[index - 1],
            )
        }, [
            "14th",
            "21st",
            "28th",
            "JULY",
            "12th",
            "19th",
            "26th",
            "AUGUST",
            "9th",
            "16th",
            "23rd",
            "30th",
            "SEPTEMBER",
            "13th",
        ])
    }

    func testDayLabelTextUsesWeekdayAbbreviations() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        assertEquals(togglWeeklyFocusDayLabelText(for: try date("2026-06-15 00:00:00")), "MON")
        assertEquals(togglWeeklyFocusDayLabelText(for: try date("2026-06-16 00:00:00")), "TUE")
    }

    func testPeriodMonthLabelAlwaysUsesThreeCharacters() throws {
        assertEquals(togglPeriodFocusMonthLabel(for: try date("2026-09-06 00:00:00")), "Sep")
    }

    private func writeEntry(_ url: URL, start: String, stop: String) throws {
        let text =
            """
            ---
            start: "\(start)"
            stop: "\(stop)"
            duration: 0
            project: "Focus"
            description: ""
            tags:
            ---
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func date(_ raw: String) throws -> Date {
        try XCTUnwrap(makeDateFormatter().date(from: raw))
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = makeDateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func week(_ startDate: String) throws -> TogglWeeklyFocusWeek {
        TogglWeeklyFocusWeek(
            startDate: try date("\(startDate) 00:00:00"),
            endDate: try date("\(startDate) 00:00:00"),
            dayCount: 7,
            totalSeconds: 0,
            isFuture: true,
            isCurrent: false,
        )
    }

    private func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}
