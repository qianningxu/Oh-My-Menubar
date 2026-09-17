@testable import AppBundle
import Foundation
import SQLite3
import XCTest

final class WorkspaceSidebarTodayFocusWidgetTest: XCTestCase {
    @MainActor
    func testLoaderDoesNotBlockMainActorWhileReading() async {
        let probe = TodayFocusLoaderProbe(blocksFirstLoad: true)
        defer { probe.releaseFirstLoad() }
        let loader = WorkspaceSidebarTodayFocusLoader { dataSource, now in
            probe.load(dataSource: dataSource, now: now)
        }
        let now = Date(timeIntervalSinceReferenceDate: 1_000_020)

        loader.refresh(dataSource: URL(filePath: "/tmp/today-focus"), now: now)
        let didStart = await waitUntil { probe.didStartFirstLoad }
        XCTAssertTrue(didStart)

        var mainActorHeartbeat = false
        Task { @MainActor in
            mainActorHeartbeat = true
        }
        let didRunHeartbeat = await waitUntil { mainActorHeartbeat }
        XCTAssertTrue(didRunHeartbeat)
        XCTAssertNil(loader.snapshot)

        probe.releaseFirstLoad()
        let didPublish = await waitUntil { loader.snapshot != nil }
        XCTAssertTrue(didPublish)
        XCTAssertEqual(loader.snapshot?.focusedSeconds, 100)
    }

    @MainActor
    func testLoaderCoalescesRepeatedRefreshesWithinTheSameMinute() async {
        let probe = TodayFocusLoaderProbe(blocksFirstLoad: true)
        defer { probe.releaseFirstLoad() }
        let loader = WorkspaceSidebarTodayFocusLoader { dataSource, now in
            probe.load(dataSource: dataSource, now: now)
        }
        let dataSource = URL(filePath: "/tmp/today-focus")
        let now = Date(timeIntervalSinceReferenceDate: 1_000_020)

        loader.refresh(dataSource: dataSource, now: now)
        loader.refresh(dataSource: dataSource, now: now.addingTimeInterval(20))
        loader.refresh(dataSource: dataSource, now: now.addingTimeInterval(40))

        let didStart = await waitUntil { probe.didStartFirstLoad }
        XCTAssertTrue(didStart)
        XCTAssertEqual(probe.loadCount, 1)

        probe.releaseFirstLoad()
        let didPublish = await waitUntil { loader.snapshot != nil }
        XCTAssertTrue(didPublish)
        loader.refresh(dataSource: dataSource, now: now.addingTimeInterval(50))
        await Task.yield()
        XCTAssertEqual(probe.loadCount, 1)
    }

    @MainActor
    func testLoaderDoesNotPublishAStaleRefresh() async {
        let probe = TodayFocusLoaderProbe(blocksFirstLoad: true)
        defer { probe.releaseFirstLoad() }
        let loader = WorkspaceSidebarTodayFocusLoader { dataSource, now in
            probe.load(dataSource: dataSource, now: now)
        }
        let dataSource = URL(filePath: "/tmp/today-focus")
        let firstMinute = Date(timeIntervalSinceReferenceDate: 1_000_020)
        let secondMinute = firstMinute.addingTimeInterval(60)

        loader.refresh(dataSource: dataSource, now: firstMinute)
        let didStartFirst = await waitUntil { probe.didStartFirstLoad }
        XCTAssertTrue(didStartFirst)

        loader.refresh(dataSource: dataSource, now: secondMinute)
        let didPublishSecond = await waitUntil { loader.snapshot?.focusedSeconds == 200 }
        XCTAssertTrue(didPublishSecond)

        probe.releaseFirstLoad()
        let didFinishBoth = await waitUntil { probe.completedLoadCount == 2 }
        XCTAssertTrue(didFinishBoth)
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertEqual(loader.snapshot?.focusedSeconds, 200)
    }

    func testAggregatorReadsTodayFocusFromSelfDataSQLite() throws {
        let previousTimeZone = NSTimeZone.default
        NSTimeZone.default = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        defer { NSTimeZone.default = previousTimeZone }

        let dataDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-today-focus-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let sqliteURL = dataDirectory.appending(component: "self_data.sqlite")
        try makeDatabase(at: sqliteURL)
        try execute(
            """
            insert into time_entries (project_id, start_at_utc, stop_at_utc, duration_seconds) values
                (1, '2026-07-28T23:00:00Z', '2026-07-29T01:00:00Z', 7200),
                (1, '2026-07-29T08:00:00Z', '2026-07-29T12:00:00Z', 14400),
                (1, '2026-07-30T08:00:00Z', '2026-07-30T09:00:00Z', 3600);
            """,
            at: sqliteURL,
        )

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-29T10:00:00Z"))
        let snapshot = TodayFocusAggregator(dataSource: dataDirectory).load(now: now)

        assertNil(snapshot.errorMessage)
        XCTAssertEqual(snapshot.focusedSeconds, 3 * 3600, accuracy: 1)
        assertEquals(snapshot.targetHours, 11)
        assertEquals(snapshot.percentage, 27)
        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertEqual(snapshot.days.map(\.focusedSeconds), [0, 3600, 3 * 3600, 0, 0, 0, 0])
        XCTAssertEqual(snapshot.days.firstIndex(where: \.isToday), 2)
        XCTAssertEqual(snapshot.days.filter(\.isFuture).count, 4)
        XCTAssertEqual(snapshot.averageFocusedSeconds, 4 * 3600 / 3, accuracy: 1)
    }

    func testAggregatorReportsMissingSelfData() {
        let missing = FileManager.default.temporaryDirectory
            .appending(component: "missing-self-data-\(UUID().uuidString)", directoryHint: .isDirectory)
        let snapshot = TodayFocusAggregator(dataSource: missing).load()
        assertEquals(snapshot.errorMessage, "Can't read self_data")
    }

    func testAggregatorUsesElevenHourTargetEveryDay() throws {
        let missing = FileManager.default.temporaryDirectory
            .appending(component: "missing-self-data-\(UUID().uuidString)", directoryHint: .isDirectory)
        let formatter = ISO8601DateFormatter()

        for day in 2 ... 8 {
            let date = try XCTUnwrap(formatter.date(from: "2026-08-0\(day)T12:00:00Z"))
            XCTAssertEqual(TodayFocusAggregator(dataSource: missing).load(now: date).targetHours, 11)
        }
    }

    func testAggregatorIncludesUnassignedTimeThatCrossesMidnight() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-today-focus-unassigned-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let sqliteURL = dataDirectory.appending(component: "self_data.sqlite")
        try makeDatabase(at: sqliteURL)
        try execute(
            """
            insert into time_entries (project_id, start_at_utc, stop_at_utc, duration_seconds) values
                (null, '2026-07-28T18:00:00Z', '2026-07-29T08:00:00Z', 50400),
                (1, '2026-07-29T08:00:00Z', '2026-07-29T11:30:00Z', 12600);
            """,
            at: sqliteURL,
        )

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-29T12:00:00Z"))
        let snapshot = TodayFocusAggregator(dataSource: dataDirectory).load(now: now)

        assertNil(snapshot.errorMessage)
        XCTAssertEqual(snapshot.focusedSeconds, 11.5 * 3600, accuracy: 1)
        XCTAssertEqual(snapshot.days.map(\.focusedSeconds), [0, 6 * 3600, 11.5 * 3600, 0, 0, 0, 0])
    }

    func testAggregatorRetriesAReadThatIsBrieflyUnavailable() throws {
        let dataDirectory = FileManager.default.temporaryDirectory
            .appending(component: "winmux-today-focus-retry-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let sqliteURL = dataDirectory.appending(component: "self_data.sqlite")
        try makeDatabase(at: sqliteURL)
        try execute(
            """
            insert into time_entries (start_at_utc, stop_at_utc, duration_seconds) values
                ('2026-07-29T08:00:00Z', '2026-07-29T09:00:00Z', 3600);
            """,
            at: sqliteURL,
        )

        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: sqliteURL.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sqliteURL.path)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: sqliteURL.path)
        }

        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-29T10:00:00Z"))
        let snapshot = TodayFocusAggregator(dataSource: dataDirectory).load(now: now)

        assertNil(snapshot.errorMessage)
        XCTAssertEqual(snapshot.focusedSeconds, 3600, accuracy: 1)
    }

    private func makeDatabase(at url: URL) throws {
        try execute(
            """
            create table time_entries (
                project_id integer,
                start_at_utc text not null,
                stop_at_utc text,
                duration_seconds real not null
            );
            """,
            at: url,
        )
    }

    private func execute(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "WorkspaceSidebarTodayFocusWidgetTest", code: 1)
        }
        defer { sqlite3_close(database) }

        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            throw NSError(
                domain: "WorkspaceSidebarTodayFocusWidgetTest",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message],
            )
        }
    }

    @MainActor
    private func waitUntil(_ predicate: @MainActor () -> Bool) async -> Bool {
        for _ in 0 ..< 1_000 {
            if predicate() {
                return true
            }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return false
    }
}

private final class TodayFocusLoaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let firstLoadGate = DispatchSemaphore(value: 0)
    private let blocksFirstLoad: Bool
    private var didReleaseFirstLoad = false
    private var _didStartFirstLoad = false
    private var _loadCount = 0
    private var _completedLoadCount = 0

    init(blocksFirstLoad: Bool) {
        self.blocksFirstLoad = blocksFirstLoad
    }

    var didStartFirstLoad: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _didStartFirstLoad
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _loadCount
    }

    var completedLoadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _completedLoadCount
    }

    func load(dataSource _: URL, now _: Date) -> TodayFocusSnapshot {
        lock.lock()
        _loadCount += 1
        let invocation = _loadCount
        if invocation == 1 {
            _didStartFirstLoad = true
        }
        lock.unlock()

        if invocation == 1, blocksFirstLoad {
            firstLoadGate.wait()
        }
        let snapshot = TodayFocusSnapshot(
            focusedSeconds: TimeInterval(invocation * 100),
            targetHours: 11,
            errorMessage: nil,
        )
        lock.lock()
        _completedLoadCount += 1
        lock.unlock()
        return snapshot
    }

    func releaseFirstLoad() {
        lock.lock()
        guard !didReleaseFirstLoad else {
            lock.unlock()
            return
        }
        didReleaseFirstLoad = true
        lock.unlock()
        firstLoadGate.signal()
    }
}
