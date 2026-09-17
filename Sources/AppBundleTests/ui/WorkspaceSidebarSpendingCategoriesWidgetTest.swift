@testable import AppBundle
import Foundation
import SQLite3
import XCTest

final class WorkspaceSidebarSpendingCategoriesWidgetTest: XCTestCase {
    func testSpendingCategoryAggregatorSummarizesPastFourRollingWeeks() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        let entriesDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-spending-widget-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: entriesDirectory) }

        try writeEntry(
            entriesDirectory.appending(component: "week-four-one.md"),
            created: "2026-06-02T10:00:00.000Z",
            amount: 12.50,
            category: "groceries",
        )
        try writeEntry(
            entriesDirectory.appending(component: "week-four-two.md"),
            created: "2026-05-27T09:00:00Z",
            amount: 2.50,
            category: "groceries",
        )
        try writeEntry(
            entriesDirectory.appending(component: "week-two.md"),
            created: "2026-05-16T09:00:00.000Z",
            amount: 10,
            category: "eating_out",
        )
        try writeEntry(
            entriesDirectory.appending(component: "week-one.md"),
            created: "2026-05-10T09:00:00.000Z",
            amount: 5,
            category: "transport",
        )
        try writeEntry(
            entriesDirectory.appending(component: "old.md"),
            created: "2026-04-20T09:00:00.000Z",
            amount: 100,
            category: "shopping",
        )
        try writeEntry(
            entriesDirectory.appending(component: "future.md"),
            created: "2026-06-03T09:00:00.000Z",
            amount: 40,
            category: "shopping",
        )

        let now = try XCTUnwrap(makeSpendingTestDateFormatter().date(from: "2026-06-02T12:00:00.000Z"))
        let snapshot = SpendingCategoryAggregator(entriesDirectory: entriesDirectory, days: 28).load(now: now)

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.weeks.map { makeSpendingTestDateFormatter().string(from: $0.startDate) }, [
            "2026-05-27T00:00:00.000Z",
            "2026-05-20T00:00:00.000Z",
            "2026-05-13T00:00:00.000Z",
            "2026-05-06T00:00:00.000Z",
        ])
        assertEquals(snapshot.weeks.map { makeSpendingTestDateFormatter().string(from: $0.endDate) }, [
            "2026-06-02T00:00:00.000Z",
            "2026-05-26T00:00:00.000Z",
            "2026-05-19T00:00:00.000Z",
            "2026-05-12T00:00:00.000Z",
        ])
        assertEquals(snapshot.weeks.map { Int(($0.amount * 100).rounded()) }, [1500, 0, 1000, 500])
        assertEquals(snapshot.weeks.map(\.transactionCount), [2, 0, 1, 1])
        assertEquals(Int((snapshot.totalAmount * 100).rounded()), 3000)
        assertEquals(snapshot.transactionCount, 4)
        assertEquals(snapshot.scannedEntryCount, 6)
    }

    func testSpendingCategoryAggregatorReportsMissingDirectory() {
        let missingDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-missing-\(UUID().uuidString)", directoryHint: .isDirectory)
        let snapshot = SpendingCategoryAggregator(entriesDirectory: missingDirectory, days: 30).load()

        assertEquals(snapshot.errorMessage, "Can't read spending entries")
        assertEquals(snapshot.weeks, [])
    }

    func testSpendingCategoryAggregatorCountsOnlySqliteOutflows() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        let entriesDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-spending-sqlite-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: entriesDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: entriesDirectory) }

        let sqliteURL = entriesDirectory.appending(component: "self_data.sqlite")
        try makeSpendingSQLiteDatabase(at: sqliteURL, rows: [
            ("2026-06-10T13:27:58Z", "2026-06-10", -5577),
            ("2026-06-10T13:27:58Z", "2026-06-10", 5577),
            ("2026-06-12T19:43:59Z", "2026-06-12", 0),
            ("2026-06-11T10:31:56Z", "2026-06-11", -200),
        ])

        let now = try XCTUnwrap(makeSpendingTestDateFormatter().date(from: "2026-06-16T12:00:00.000Z"))
        let snapshot = SpendingCategoryAggregator(entriesDirectory: entriesDirectory, days: 28).load(now: now)

        assertNil(snapshot.errorMessage)
        assertEquals(snapshot.weeks.map { Int(($0.amount * 100).rounded()) }, [5777, 0, 0, 0])
        assertEquals(snapshot.weeks.map(\.transactionCount), [2, 0, 0, 0])
        assertEquals(Int((snapshot.totalAmount * 100).rounded()), 5777)
        assertEquals(snapshot.transactionCount, 2)
        assertEquals(snapshot.scannedEntryCount, 2)
    }

    private func writeEntry(_ url: URL, created: String, amount: Double, category: String) throws {
        let text =
            """
            ---
            created: "\(created)"
            description: ""
            merchant_name: "Test"
            amount: \(amount)
            category: "\(category)"
            ---
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func makeSpendingSQLiteDatabase(at url: URL, rows: [(created: String, localDate: String, amountMinor: Int)]) throws {
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &database), SQLITE_OK)
        guard let database else {
            XCTFail("Expected SQLite database to open")
            return
        }
        defer { sqlite3_close(database) }

        try execute(
            database,
            """
            CREATE TABLE spending_transactions (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              created_at_utc TEXT NOT NULL,
              local_date TEXT NOT NULL,
              description TEXT NOT NULL,
              merchant_name TEXT,
              amount_minor INTEGER NOT NULL,
              currency TEXT NOT NULL,
              category TEXT NOT NULL,
              source_kind TEXT,
              source_id TEXT,
              source_hash TEXT,
              synced_at_utc TEXT,
              metadata_json TEXT NOT NULL DEFAULT '{}'
            );
            """,
        )

        for row in rows {
            try execute(
                database,
                """
                INSERT INTO spending_transactions (
                    created_at_utc, local_date, description, merchant_name, amount_minor, currency, category, metadata_json
                ) VALUES (
                    '\(row.created)', '\(row.localDate)', 'Test', 'Test', \(row.amountMinor), 'GBP', 'groceries', '{}'
                );
                """,
            )
        }
    }

    private func execute(_ database: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "WorkspaceSidebarSpendingCategoriesWidgetTest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: message,
            ])
        }
    }

    private func makeSpendingTestDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
