import Foundation
import SQLite3

struct SidebarSelfDataTimeEntry: Sendable {
    let start: Date
    let stop: Date
    let projectID: Int64?
    let projectName: String?

    var isAssignedToProject: Bool {
        projectID != nil
    }
}

struct SidebarSelfDataScheduleBlock: Sendable {
    let identity: String
    let fileDate: Date
    let sessionNumber: Int
    let sessionName: String
    let from: Date
    let to: Date
    let done: Bool
}

struct SidebarSelfDataSpendingTransaction: Sendable {
    let created: Date
    let amount: Double
}

struct SidebarSelfDataSleepNight: Sendable {
    let localDate: Date
    let sleepSeconds: TimeInterval
}

struct SidebarSelfDataPeriod: Sendable {
    let id: Int64
    let name: String
    let from: Date
    let to: Date
}

enum SidebarSelfDataStore {
    private static let databaseRetryDelays: [TimeInterval] = [0, 0.05, 0.15, 0.3]
    private static let databaseBusyTimeoutMilliseconds: Int32 = 1_000

    static func sqliteURL(for source: URL) -> URL? {
        if source.pathExtension == "sqlite", FileManager.default.fileExists(atPath: source.path) {
            return source
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let candidate = source.appending(component: "self_data.sqlite")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static func loadTimeEntries(from sqliteURL: URL, now: Date) -> [SidebarSelfDataTimeEntry]? {
        let utcDateFormatter = makeUTCDateFormatter()
        return withDatabase(sqliteURL) { database in
            query(database, sql: "select start_at_utc, stop_at_utc, duration_seconds, project_id, project_name from time_entries") { statement in
                guard let start = dateColumn(statement, 0, formatter: utcDateFormatter) else { return nil }
                let rawStop = dateColumn(statement, 1, formatter: utcDateFormatter)
                let durationSeconds = sqlite3_column_double(statement, 2)
                let stop = rawStop ?? start.addingTimeInterval(durationSeconds)
                let effectiveStop = min(stop, now)
                guard effectiveStop > start else { return nil }
                let projectID = sqlite3_column_type(statement, 3) == SQLITE_NULL
                    ? nil
                    : sqlite3_column_int64(statement, 3)
                return SidebarSelfDataTimeEntry(
                    start: start,
                    stop: effectiveStop,
                    projectID: projectID,
                    projectName: textColumn(statement, 4)
                )
            }
        }
    }

    static func loadScheduleBlocks(from sqliteURL: URL) -> [SidebarSelfDataScheduleBlock]? {
        let utcDateFormatter = makeUTCDateFormatter()
        let localDateFormatter = makeLocalDateFormatter()
        return withDatabase(sqliteURL) { database in
            query(
                database,
                sql: "select id, session_name, start_at_utc, end_at_utc, local_date, done, source_id from schedule_blocks",
            ) { statement -> SidebarSelfDataScheduleBlock? in
                guard let from = dateColumn(statement, 2, formatter: utcDateFormatter),
                      let to = dateColumn(statement, 3, formatter: utcDateFormatter),
                      to > from
                else {
                    return nil
                }

                let id = sqlite3_column_int64(statement, 0)
                let sessionName = textColumn(statement, 1) ?? "Session"
                let localDate = textColumn(statement, 4)
                let sourceIdentity = textColumn(statement, 6)
                    .map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
                let identity = sourceIdentity ?? "\(localDate ?? "schedule") \(sessionName)"
                let parsedIdentity = parseScheduleIdentity(identity, formatter: localDateFormatter)
                let fileDate = parsedIdentity?.fileDate
                    ?? localDate.flatMap { localDateFormatter.date(from: $0) }
                    ?? Calendar.current.startOfDay(for: from)
                let sessionNumber = parsedIdentity?.sessionNumber ?? Int(id)
                let done = sqlite3_column_type(statement, 5) != SQLITE_NULL && sqlite3_column_int(statement, 5) != 0

                return SidebarSelfDataScheduleBlock(
                    identity: identity,
                    fileDate: fileDate,
                    sessionNumber: sessionNumber,
                    sessionName: sessionName,
                    from: from,
                    to: to,
                    done: done,
                )
            }
        }
    }

    static func loadSpendingTransactions(from sqliteURL: URL) -> [SidebarSelfDataSpendingTransaction]? {
        let utcDateFormatter = makeUTCDateFormatter()
        return withDatabase(sqliteURL) { database in
            query(database, sql: "select created_at_utc, amount_minor from spending_transactions") { statement in
                guard let created = dateColumn(statement, 0, formatter: utcDateFormatter) else { return nil }
                let amountMinor = sqlite3_column_double(statement, 1)
                guard amountMinor < 0 else { return nil }
                return SidebarSelfDataSpendingTransaction(
                    created: created,
                    amount: -amountMinor / 100,
                )
            }
        }
    }

    static func loadSleepNights(from sqliteURL: URL) -> [SidebarSelfDataSleepNight]? {
        let localDateFormatter = makeLocalDateFormatter()
        return withDatabase(sqliteURL) { database in
            query(
                database,
                sql: """
                    select
                      local_date,
                      case
                        when core_seconds + deep_seconds + rem_seconds > 0
                          then core_seconds + deep_seconds + rem_seconds
                        else asleep_seconds
                      end
                    from sleep_nights
                    """,
            ) { statement in
                guard let localDate = textColumn(statement, 0).flatMap({ localDateFormatter.date(from: $0) }) else {
                    return nil
                }
                return SidebarSelfDataSleepNight(
                    localDate: localDate,
                    sleepSeconds: TimeInterval(max(0, sqlite3_column_int64(statement, 1))),
                )
            }
        }
    }

    static func loadCurrentPeriod(from sqliteURL: URL, now: Date) -> SidebarSelfDataPeriod? {
        let localDateFormatter = makeLocalDateFormatter()
        guard let periods = withDatabase(sqliteURL, { database in
            query(
                database,
                sql: """
                    select id, name, "from", "to"
                    from period
                    order by "from" desc
                    """,
            ) { statement in
                periodColumn(statement, formatter: localDateFormatter)
            }
        }) else {
            return nil
        }
        let today = Calendar.current.startOfDay(for: now)
        return periods.first { period in
            period.from <= today && period.to >= today
        } ?? periods.min { lhs, rhs in
            abs(lhs.from.timeIntervalSince(today)) < abs(rhs.from.timeIntervalSince(today))
        }
    }

    private static func withDatabase<T>(_ url: URL, _ body: (OpaquePointer) -> T?) -> T? {
        for (attempt, retryDelay) in databaseRetryDelays.enumerated() {
            if retryDelay > 0 {
                Thread.sleep(forTimeInterval: retryDelay)
            }

            var database: OpaquePointer?
            let openFlags = attempt == 0 ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
            guard sqlite3_open_v2(url.path, &database, openFlags, nil) == SQLITE_OK,
                  let database
            else {
                if let database {
                    sqlite3_close(database)
                }
                continue
            }

            sqlite3_busy_timeout(database, databaseBusyTimeoutMilliseconds)
            guard sqlite3_exec(database, "PRAGMA query_only = ON", nil, nil, nil) == SQLITE_OK else {
                sqlite3_close(database)
                continue
            }
            let result = body(database)
            sqlite3_close(database)
            if let result {
                return result
            }
        }
        return nil
    }

    private static func query<T>(
        _ database: OpaquePointer,
        sql: String,
        row: (OpaquePointer) -> T?,
    ) -> [T]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let value = row(statement) {
                    rows.append(value)
                }
            case SQLITE_DONE:
                return rows
            default:
                return nil
            }
        }
    }

    private static func textColumn(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: text)
    }

    private static func dateColumn(
        _ statement: OpaquePointer,
        _ column: Int32,
        formatter: ISO8601DateFormatter
    ) -> Date? {
        textColumn(statement, column).flatMap { formatter.date(from: $0) }
    }

    private static func parseScheduleIdentity(
        _ identity: String,
        formatter: DateFormatter
    ) -> (fileDate: Date, sessionNumber: Int)? {
        let pattern = #"^(\d{4}-\d{2}-\d{2}) Session ([0-9]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(identity.startIndex ..< identity.endIndex, in: identity)
        guard let match = regex.firstMatch(in: identity, range: nsRange),
              let dateRange = Range(match.range(at: 1), in: identity),
              let sessionRange = Range(match.range(at: 2), in: identity),
              let fileDate = formatter.date(from: String(identity[dateRange])),
              let sessionNumber = Int(identity[sessionRange])
        else {
            return nil
        }
        return (fileDate, sessionNumber)
    }

    private static func periodColumn(
        _ statement: OpaquePointer,
        formatter: DateFormatter
    ) -> SidebarSelfDataPeriod? {
        guard let name = textColumn(statement, 1),
              let fromRaw = textColumn(statement, 2),
              let toRaw = textColumn(statement, 3),
              let from = formatter.date(from: fromRaw),
              let to = formatter.date(from: toRaw)
        else {
            return nil
        }
        return SidebarSelfDataPeriod(
            id: sqlite3_column_int64(statement, 0),
            name: name,
            from: from,
            to: to,
        )
    }

    private static func makeUTCDateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeLocalDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
