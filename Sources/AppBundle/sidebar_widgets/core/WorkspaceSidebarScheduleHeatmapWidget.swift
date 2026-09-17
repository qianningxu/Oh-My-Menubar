import Foundation
import SwiftUI

private let scheduleHeatmapFulfilledColor = workspaceSidebarWidgetSemanticColor(.green, .color7)
private let scheduleHeatmapReflectedColor = workspaceSidebarWidgetSemanticColor(.amber, .color8)
private let scheduleHeatmapUnfulfilledColor = workspaceSidebarWidgetSemanticColor(.red, .color7)

struct WorkspaceSidebarScheduleHeatmapWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    let schedulePath: String
    let togglEntriesPath: String
    let deviationPath: String
    let days: Int

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = ScheduleHeatmapAggregator(
                scheduleDirectory: URL(filePath: schedulePath, directoryHint: .isDirectory),
                togglEntriesDirectory: URL(filePath: togglEntriesPath, directoryHint: .isDirectory),
                deviationDirectory: URL(filePath: deviationPath, directoryHint: .isDirectory),
                days: days,
            ).load(now: context.date)

            Group {
                if isCompact {
                    WorkspaceSidebarCompactScheduleHeatmapCard(
                        snapshot: snapshot,
                        sectionWidth: sectionWidth,
                        days: days,
                    )
                } else {
                    WorkspaceSidebarExpandedScheduleHeatmapCard(
                        snapshot: snapshot,
                        sectionWidth: sectionWidth,
                        days: days,
                    )
                }
            }
        }
        .id(id)
    }
}

enum ScheduleHeatmapStatus: String, Sendable {
    case fulfilled
    case reflected
    case unfulfilled
}

struct ScheduleHeatmapCell: Equatable, Identifiable, Sendable {
    let identity: String
    let date: Date
    let sessionNumber: Int
    let sessionName: String
    let from: Date
    let to: Date
    let status: ScheduleHeatmapStatus
    let coveredSeconds: TimeInterval
    let durationSeconds: TimeInterval

    var id: String { identity }
}

struct ScheduleHeatmapDay: Equatable, Identifiable, Sendable {
    let date: Date
    let cells: [ScheduleHeatmapCell]

    var id: Date { date }
}

struct ScheduleHeatmapSnapshot: Equatable, Sendable {
    var days: [ScheduleHeatmapDay] = []
    var fulfilledCount: Int = 0
    var reflectedCount: Int = 0
    var unfulfilledCount: Int = 0
    var scannedScheduleCount: Int = 0
    var scannedTogglEntryCount: Int = 0
    var errorMessage: String? = nil

    var totalCount: Int {
        fulfilledCount + reflectedCount + unfulfilledCount
    }
}

struct ScheduleHeatmapAggregator: Sendable {
    let scheduleDirectory: URL
    let togglEntriesDirectory: URL
    let deviationDirectory: URL
    let days: Int

    func load(now: Date = Date()) -> ScheduleHeatmapSnapshot {
        guard days > 0 else {
            return ScheduleHeatmapSnapshot(errorMessage: "Invalid schedule window")
        }

        let fileManager = FileManager.default
        let deviationLookup = makeDeviationLookup(fileManager: fileManager)
        if let scheduleSqliteURL = SidebarSelfDataStore.sqliteURL(for: scheduleDirectory),
           let togglSqliteURL = SidebarSelfDataStore.sqliteURL(for: togglEntriesDirectory)
        {
            return loadFromSelfData(
                scheduleSqliteURL: scheduleSqliteURL,
                togglSqliteURL: togglSqliteURL,
                deviationLookup: deviationLookup,
                fileManager: fileManager,
                now: now,
            )
        }

        guard Self.directoryExists(scheduleDirectory, fileManager: fileManager) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read schedules")
        }
        guard Self.directoryExists(togglEntriesDirectory, fileManager: fileManager) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read Toggl entries")
        }

        let scheduleUrls: [URL]
        do {
            scheduleUrls = try fileManager.contentsOfDirectory(
                at: scheduleDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
        } catch {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read schedules")
        }

        let togglEntryUrls: [URL]
        do {
            togglEntryUrls = try fileManager.contentsOfDirectory(
                at: togglEntriesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
        } catch {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read Toggl entries")
        }

        let calendar = Self.scheduleCalendar()
        guard let dayStarts = Self.currentWeekDayStarts(now: now, calendar: calendar) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Invalid schedule window")
        }
        var cellsByDay = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, [ScheduleHeatmapCell]()) })

        let scheduleFormatters = ScheduleHeatmapSchedule.makeFormatters()
        let togglFormatter = ScheduleHeatmapTogglEntry.makeFormatter()
        let togglEntries = togglEntryUrls
            .filter { $0.pathExtension == "md" }
            .compactMap { ScheduleHeatmapTogglEntry.parse(url: $0, formatter: togglFormatter, now: now) }
        var scannedScheduleCount = 0

        for url in scheduleUrls where url.pathExtension == "md" {
            guard let schedule = ScheduleHeatmapSchedule.parse(url: url, formatters: scheduleFormatters) else { continue }
            scannedScheduleCount += 1

            let dayStart = calendar.startOfDay(for: schedule.fileDate)
            guard cellsByDay[dayStart] != nil else { continue }
            guard schedule.to <= now else { continue }

            let coveredSeconds = Self.coveredSeconds(for: schedule, by: togglEntries)
            let durationSeconds = schedule.to.timeIntervalSince(schedule.from)
            guard durationSeconds > 0 else { continue }

            let status: ScheduleHeatmapStatus
            if coveredSeconds / durationSeconds >= 0.8 {
                status = .fulfilled
            } else if deviationLookup.contains(identity: schedule.identity, fileManager: fileManager) {
                status = .reflected
            } else {
                status = .unfulfilled
            }

            cellsByDay[dayStart, default: []].append(ScheduleHeatmapCell(
                identity: schedule.identity,
                date: dayStart,
                sessionNumber: schedule.sessionNumber,
                sessionName: schedule.sessionName,
                from: schedule.from,
                to: schedule.to,
                status: status,
                coveredSeconds: coveredSeconds,
                durationSeconds: durationSeconds,
            ))
        }

        let heatmapDays = dayStarts.map { dayStart in
            ScheduleHeatmapDay(
                date: dayStart,
                cells: (cellsByDay[dayStart] ?? []).sorted { lhs, rhs in
                    if lhs.sessionNumber != rhs.sessionNumber {
                        return lhs.sessionNumber < rhs.sessionNumber
                    }
                    return lhs.from < rhs.from
                },
            )
        }
        let cells = heatmapDays.flatMap(\.cells)

        return ScheduleHeatmapSnapshot(
            days: heatmapDays,
            fulfilledCount: cells.filter { $0.status == .fulfilled }.count,
            reflectedCount: cells.filter { $0.status == .reflected }.count,
            unfulfilledCount: cells.filter { $0.status == .unfulfilled }.count,
            scannedScheduleCount: scannedScheduleCount,
            scannedTogglEntryCount: togglEntries.count,
            errorMessage: nil,
        )
    }

    private func loadFromSelfData(
        scheduleSqliteURL: URL,
        togglSqliteURL: URL,
        deviationLookup: ScheduleHeatmapDeviationLookup,
        fileManager: FileManager,
        now: Date,
    ) -> ScheduleHeatmapSnapshot {
        guard let schedules = SidebarSelfDataStore.loadScheduleBlocks(from: scheduleSqliteURL) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read schedules")
        }
        guard let entries = SidebarSelfDataStore.loadTimeEntries(from: togglSqliteURL, now: now) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Can't read Toggl entries")
        }

        return summarize(
            schedules: schedules.map {
                ScheduleHeatmapSchedule(
                    identity: $0.identity,
                    fileDate: $0.fileDate,
                    sessionNumber: $0.sessionNumber,
                    sessionName: $0.sessionName,
                    from: $0.from,
                    to: $0.to,
                    isDone: $0.done,
                )
            },
            togglEntries: entries.map { ScheduleHeatmapTogglEntry(start: $0.start, stop: $0.stop) },
            deviationLookup: deviationLookup,
            fileManager: fileManager,
            now: now,
        )
    }

    private func summarize(
        schedules: [ScheduleHeatmapSchedule],
        togglEntries: [ScheduleHeatmapTogglEntry],
        deviationLookup: ScheduleHeatmapDeviationLookup,
        fileManager: FileManager,
        now: Date,
    ) -> ScheduleHeatmapSnapshot {
        let calendar = Self.scheduleCalendar()
        guard let dayStarts = Self.currentWeekDayStarts(now: now, calendar: calendar) else {
            return ScheduleHeatmapSnapshot(errorMessage: "Invalid schedule window")
        }
        var cellsByDay = Dictionary(uniqueKeysWithValues: dayStarts.map { ($0, [ScheduleHeatmapCell]()) })

        for schedule in schedules {
            let dayStart = calendar.startOfDay(for: schedule.fileDate)
            guard cellsByDay[dayStart] != nil else { continue }
            guard schedule.to <= now else { continue }

            let coveredSeconds = Self.coveredSeconds(for: schedule, by: togglEntries)
            let durationSeconds = schedule.to.timeIntervalSince(schedule.from)
            guard durationSeconds > 0 else { continue }

            let status: ScheduleHeatmapStatus
            if schedule.isDone || coveredSeconds / durationSeconds >= 0.8 {
                status = .fulfilled
            } else if deviationLookup.contains(identity: schedule.identity, fileManager: fileManager) {
                status = .reflected
            } else {
                status = .unfulfilled
            }

            cellsByDay[dayStart, default: []].append(ScheduleHeatmapCell(
                identity: schedule.identity,
                date: dayStart,
                sessionNumber: schedule.sessionNumber,
                sessionName: schedule.sessionName,
                from: schedule.from,
                to: schedule.to,
                status: status,
                coveredSeconds: coveredSeconds,
                durationSeconds: durationSeconds,
            ))
        }

        let heatmapDays = dayStarts.map { dayStart in
            ScheduleHeatmapDay(
                date: dayStart,
                cells: (cellsByDay[dayStart] ?? []).sorted { lhs, rhs in
                    if lhs.sessionNumber != rhs.sessionNumber {
                        return lhs.sessionNumber < rhs.sessionNumber
                    }
                    return lhs.from < rhs.from
                },
            )
        }
        let cells = heatmapDays.flatMap(\.cells)

        return ScheduleHeatmapSnapshot(
            days: heatmapDays,
            fulfilledCount: cells.filter { $0.status == .fulfilled }.count,
            reflectedCount: cells.filter { $0.status == .reflected }.count,
            unfulfilledCount: cells.filter { $0.status == .unfulfilled }.count,
            scannedScheduleCount: schedules.count,
            scannedTogglEntryCount: togglEntries.count,
            errorMessage: nil,
        )
    }

    private static func directoryExists(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func makeDeviationLookup(fileManager: FileManager) -> ScheduleHeatmapDeviationLookup {
        var directories: [URL] = []
        if Self.directoryExists(deviationDirectory, fileManager: fileManager) {
            directories.append(deviationDirectory)
        }

        let nestedDeviationDirectory = deviationDirectory.appending(component: "Deviation", directoryHint: .isDirectory)
        if Self.directoryExists(nestedDeviationDirectory, fileManager: fileManager) {
            directories.append(nestedDeviationDirectory)
        }

        return ScheduleHeatmapDeviationLookup(directories: directories)
    }

    private static func scheduleCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale.current
        return calendar
    }

    private static func currentWeekDayStarts(now: Date, calendar: Calendar) -> [Date]? {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return nil
        }
        let days = calendar.range(of: .weekday, in: .weekOfYear, for: now)?.count ?? 7
        return (0 ..< days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }
    }

    private static func coveredSeconds(
        for schedule: ScheduleHeatmapSchedule,
        by entries: [ScheduleHeatmapTogglEntry],
    ) -> TimeInterval {
        var overlaps = entries.compactMap { entry -> ScheduleHeatmapDateInterval? in
            let start = max(entry.start, schedule.from)
            let end = min(entry.stop, schedule.to)
            guard end > start else { return nil }
            return ScheduleHeatmapDateInterval(start: start, end: end)
        }
        overlaps.sort { lhs, rhs in lhs.start < rhs.start }

        var mergedSeconds: TimeInterval = 0
        var current: ScheduleHeatmapDateInterval?

        for interval in overlaps {
            guard let active = current else {
                current = interval
                continue
            }

            if interval.start <= active.end {
                current = ScheduleHeatmapDateInterval(start: active.start, end: max(active.end, interval.end))
            } else {
                mergedSeconds += active.end.timeIntervalSince(active.start)
                current = interval
            }
        }

        if let current {
            mergedSeconds += current.end.timeIntervalSince(current.start)
        }

        return mergedSeconds
    }
}

private struct ScheduleHeatmapDeviationLookup: Sendable {
    let directories: [URL]

    func contains(identity: String, fileManager: FileManager) -> Bool {
        directories.contains { directory in
            fileManager.fileExists(atPath: directory.appending(component: "\(identity).md").path)
        }
    }
}

private struct ScheduleHeatmapDateInterval {
    let start: Date
    let end: Date
}

private struct ScheduleHeatmapSchedule {
    let identity: String
    let fileDate: Date
    let sessionNumber: Int
    let sessionName: String
    let from: Date
    let to: Date
    var isDone: Bool = false

    static func parse(url: URL, formatters: ScheduleHeatmapScheduleFormatters) -> ScheduleHeatmapSchedule? {
        let identity = url.deletingPathExtension().lastPathComponent
        guard let identityComponents = parseIdentity(identity),
              let fileDate = formatters.fileDate.date(from: identityComponents.dateKey),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return nil
        }

        let fields = ScheduleHeatmapFrontMatter.fields(in: text)
        guard let fromRaw = fields["from"],
              let toRaw = fields["to"],
              let from = formatters.scheduleTime.date(from: fromRaw),
              let to = formatters.scheduleTime.date(from: toRaw),
              to > from
        else {
            return nil
        }

        return ScheduleHeatmapSchedule(
            identity: identity,
            fileDate: fileDate,
            sessionNumber: identityComponents.sessionNumber,
            sessionName: fields["session_name"] ?? "Session \(identityComponents.sessionNumber)",
            from: from,
            to: to,
        )
    }

    static func makeFormatters() -> ScheduleHeatmapScheduleFormatters {
        let fileDate = DateFormatter()
        fileDate.locale = Locale(identifier: "en_US_POSIX")
        fileDate.timeZone = .current
        fileDate.dateFormat = "yyyy-MM-dd"

        let scheduleTime = DateFormatter()
        scheduleTime.locale = Locale(identifier: "en_US_POSIX")
        scheduleTime.timeZone = .current
        scheduleTime.dateFormat = "yyyy-MM-dd'T'HH:mm"

        return ScheduleHeatmapScheduleFormatters(fileDate: fileDate, scheduleTime: scheduleTime)
    }

    private static func parseIdentity(_ identity: String) -> (dateKey: String, sessionNumber: Int)? {
        let pattern = #"^(\d{4}-\d{2}-\d{2}) Session ([0-9]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(identity.startIndex ..< identity.endIndex, in: identity)
        guard let match = regex.firstMatch(in: identity, range: nsRange),
              let dateRange = Range(match.range(at: 1), in: identity),
              let sessionRange = Range(match.range(at: 2), in: identity),
              let sessionNumber = Int(identity[sessionRange])
        else {
            return nil
        }
        return (String(identity[dateRange]), sessionNumber)
    }
}

private struct ScheduleHeatmapScheduleFormatters {
    let fileDate: DateFormatter
    let scheduleTime: DateFormatter
}

private struct ScheduleHeatmapTogglEntry {
    let start: Date
    let stop: Date

    static func parse(url: URL, formatter: DateFormatter, now: Date) -> ScheduleHeatmapTogglEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = ScheduleHeatmapFrontMatter.fields(in: text)
        guard let startRaw = fields["start"], let start = formatter.date(from: startRaw) else { return nil }

        let stop = fields["stop"].flatMap { rawStop -> Date? in
            rawStop.isEmpty ? nil : formatter.date(from: rawStop)
        }
            ?? fields["duration"]
                .flatMap(Double.init)
                .map { start.addingTimeInterval($0 * 60 * 60) }
        guard let stop else { return nil }

        let effectiveStop = min(stop, now)
        guard effectiveStop > start else { return nil }
        return ScheduleHeatmapTogglEntry(start: start, stop: effectiveStop)
    }

    static func makeFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private enum ScheduleHeatmapFrontMatter {
    static func fields(in text: String) -> [String: String] {
        var fields: [String: String] = [:]
        var hasStartedFrontMatter = false

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine == "---" {
                if hasStartedFrontMatter {
                    break
                }
                hasStartedFrontMatter = true
                continue
            }

            guard hasStartedFrontMatter, let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = unquote(value)
        }

        return fields
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2,
              value.first == "\"",
              value.last == "\""
        else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }
}

private struct WorkspaceSidebarCompactScheduleHeatmapCard: View {
    let snapshot: ScheduleHeatmapSnapshot
    let sectionWidth: CGFloat
    let days: Int

    var body: some View {
        VStack(alignment: .center, spacing: standardGap * 3.5) {
            ScheduleHeatmapIcon()
                .frame(width: 18, height: 18)
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                .padding(standardGap * 3)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(workspaceSidebarWidgetComponentBackground(.normal))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(workspaceSidebarWidgetBorder(.normal), lineWidth: 1)
                        }
                }
            if snapshot.errorMessage == nil {
                Text(scheduleHeatmapPercentText(snapshot.fulfilledCount, of: snapshot.totalCount))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(compactPercentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                    .lineLimit(1)
            }
        }
        .frame(width: sectionWidth, height: 96, alignment: .center)
        .background(WorkspaceSidebarStatusCardBackground())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        if let errorMessage = snapshot.errorMessage {
            return errorMessage
        }
        return "Schedule, \(scheduleHeatmapPercentText(snapshot.fulfilledCount, of: snapshot.totalCount)) done, \(scheduleHeatmapPercentText(snapshot.reflectedCount, of: snapshot.totalCount)) reflected, \(scheduleHeatmapPercentText(snapshot.unfulfilledCount, of: snapshot.totalCount)) missed this week"
    }

    private var compactPercentColor: WorkspaceSidebarWidgetShapeStyle {
        let ratio = snapshot.totalCount > 0
            ? Double(snapshot.fulfilledCount) / Double(snapshot.totalCount)
            : 0
        if ratio > 0.75 {
            return scheduleHeatmapFulfilledColor
        }
        if ratio >= 0.5 {
            return scheduleHeatmapReflectedColor
        }
        return scheduleHeatmapUnfulfilledColor
    }
}

private struct WorkspaceSidebarExpandedScheduleHeatmapCard: View {
    let snapshot: ScheduleHeatmapSnapshot
    let sectionWidth: CGFloat
    let days: Int

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 5) {
            HStack(alignment: .firstTextBaseline, spacing: standardGap * 4) {
                HStack(spacing: standardGap * 3) {
                    ScheduleHeatmapIcon()
                        .frame(width: 13, height: 13)
                    Text("Schedule")
                }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))

                Spacer(minLength: 8)

                if snapshot.errorMessage == nil, snapshot.totalCount > 0 {
                    ScheduleHeatmapInlineRates(snapshot: snapshot)
                }
            }

            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if snapshot.totalCount == 0 {
                Text("No completed sessions")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScheduleHeatmapGrid(
                    days: snapshot.days,
                    showsLabels: true,
                    cellHeight: 12,
                    columnSpacing: standardGap * 2.5,
                    rowSpacing: standardGap * 2.5,
                )
            }
        }
        .padding(.horizontal, standardGap * 6)
        .padding(.vertical, standardGap * 5.5)
        .frame(width: sectionWidth, alignment: .leading)
        .background(WorkspaceSidebarStatusCardBackground())
        .accessibilityElement(children: .combine)
    }

}

private struct ScheduleHeatmapGrid: View {
    let days: [ScheduleHeatmapDay]
    let showsLabels: Bool
    let cellHeight: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    private var sessionNumbers: [Int] {
        let maxSessionNumber = max(days.flatMap(\.cells).map(\.sessionNumber).max() ?? 0, 5)
        return Array(1 ... maxSessionNumber)
    }

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(days) { day in
                VStack(spacing: rowSpacing) {
                    if showsLabels {
                        Text(scheduleHeatmapWeekdayText(day.date))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                            .lineLimit(1)
                            .frame(height: 12)
                    }

                    ForEach(sessionNumbers, id: \.self) { sessionNumber in
                        if let cell = day.cells.first(where: { $0.sessionNumber == sessionNumber }) {
                            ScheduleHeatmapStatusCell(cell: cell, height: cellHeight)
                        } else {
                            ScheduleHeatmapEmptyCell(height: cellHeight)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScheduleHeatmapStatusCell: View {
    let cell: ScheduleHeatmapCell
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(workspaceSidebarWidgetBorder(.normal), lineWidth: 0.5)
            }
            .frame(height: height)
            .help(helpText)
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var color: WorkspaceSidebarWidgetShapeStyle {
        switch cell.status {
            case .fulfilled:
                scheduleHeatmapFulfilledColor
            case .reflected:
                scheduleHeatmapReflectedColor
            case .unfulfilled:
                scheduleHeatmapUnfulfilledColor
        }
    }

    private var helpText: String {
        "\(cell.identity), \(statusText), \(scheduleHeatmapPercentText(cell.coveredSeconds / max(cell.durationSeconds, 1))) covered"
    }

    private var accessibilityLabel: String {
        "\(cell.identity), \(statusText)"
    }

    private var statusText: String {
        switch cell.status {
            case .fulfilled:
                "fulfilled"
            case .reflected:
                "reflected"
            case .unfulfilled:
                "unfulfilled"
        }
    }
}

private struct ScheduleHeatmapEmptyCell: View {
    let height: CGFloat

    var body: some View {
        WinMuxDesignTokens.transparent
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

private struct ScheduleHeatmapCompactRates: View {
    let snapshot: ScheduleHeatmapSnapshot

    var body: some View {
        HStack(spacing: standardGap * 2) {
            ScheduleHeatmapCompactRateText(color: scheduleHeatmapFulfilledColor, value: snapshot.fulfilledCount, total: snapshot.totalCount)
            ScheduleHeatmapCompactRateText(color: scheduleHeatmapReflectedColor, value: snapshot.reflectedCount, total: snapshot.totalCount)
            ScheduleHeatmapCompactRateText(color: scheduleHeatmapUnfulfilledColor, value: snapshot.unfulfilledCount, total: snapshot.totalCount)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct ScheduleHeatmapCompactRateText: View {
    let color: WorkspaceSidebarWidgetShapeStyle
    let value: Int
    let total: Int

    var body: some View {
        Text(scheduleHeatmapPercentText(value, of: total))
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct ScheduleHeatmapInlineRates: View {
    let snapshot: ScheduleHeatmapSnapshot

    var body: some View {
        HStack(spacing: standardGap * 3) {
            ScheduleHeatmapInlineRateText(color: scheduleHeatmapFulfilledColor, value: snapshot.fulfilledCount, total: snapshot.totalCount)
            ScheduleHeatmapInlineRateText(color: scheduleHeatmapReflectedColor, value: snapshot.reflectedCount, total: snapshot.totalCount)
            ScheduleHeatmapInlineRateText(color: scheduleHeatmapUnfulfilledColor, value: snapshot.unfulfilledCount, total: snapshot.totalCount)
        }
    }
}

private struct ScheduleHeatmapInlineRateText: View {
    let color: WorkspaceSidebarWidgetShapeStyle
    let value: Int
    let total: Int

    var body: some View {
        Text(scheduleHeatmapPercentText(value, of: total))
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct ScheduleHeatmapIcon: View {
    var body: some View {
        Canvas { context, size in
            let cellSize = min(size.width, size.height) * 0.22
            let gap = min(size.width, size.height) * 0.09
            let originX = (size.width - (cellSize * 3 + gap * 2)) / 2
            let originY = (size.height - (cellSize * 3 + gap * 2)) / 2
            for row in 0 ..< 3 {
                for column in 0 ..< 3 {
                    let rect = CGRect(
                        x: originX + CGFloat(column) * (cellSize + gap),
                        y: originY + CGFloat(row) * (cellSize + gap),
                        width: cellSize,
                        height: cellSize,
                    )
                    let path = Path(roundedRect: rect, cornerRadius: max(1, cellSize * 0.22))
                    context.fill(path, with: .foreground)
                }
            }
        }
    }
}

private func scheduleHeatmapWeekdayText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
}

private func scheduleHeatmapPercentText(_ ratio: Double) -> String {
    "\(Int((max(0, min(ratio, 1)) * 100).rounded()))%"
}

private func scheduleHeatmapPercentText(_ value: Int, of total: Int) -> String {
    guard total > 0 else { return "0%" }
    return scheduleHeatmapPercentText(Double(value) / Double(total))
}
