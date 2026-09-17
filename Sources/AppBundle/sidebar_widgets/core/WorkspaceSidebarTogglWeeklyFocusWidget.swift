import Charts
import Foundation
import SwiftUI

private let togglWeekFocusTextColor = workspaceSidebarWidgetColor(.color9)
private let togglWeekFocusBackgroundColor = workspaceSidebarWidgetColor(.color1)
private let togglWeekFocusBorderColor = workspaceSidebarWidgetColor(.color4)
private let togglWeekFocusFillColor = workspaceSidebarWidgetColor(.color7)
private let togglWeekFocusCurrentFillColor = workspaceSidebarWidgetColor(.color8)
private let togglWeeklyFocusMaxDailySeconds: TimeInterval = 4.5 * 60 * 60
private let togglWeeklyFocusStartDateString = "2026-06-14"
private let togglPeriodFocusChartHeight: CGFloat = 92
private let togglPeriodFocusGuidelines: [Double] = [8.7, 6.5]
private let togglPeriodFocusGuidelineColor = workspaceSidebarWidgetColor(.color6)
private let togglPeriodFocusDotColor = workspaceSidebarWidgetColor(.color9)
private let togglWeeklyFocusRefreshInterval: Duration = .seconds(60)

struct WorkspaceSidebarTogglWeeklyFocusWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    let entriesPath: String
    let targetDate: String
    @StateObject private var loader = WorkspaceSidebarTogglWeeklyFocusLoader()

    var body: some View {
        let entriesDirectory = URL(filePath: entriesPath, directoryHint: .isDirectory)
        let refreshKey = TogglWeeklyFocusRefreshKey(entriesDirectory: entriesDirectory, targetDate: targetDate)

        Group {
            if !isCompact {
                WorkspaceSidebarExpandedTogglWeeklyFocusCard(
                    snapshot: loader.snapshot ?? TogglWeeklyFocusSnapshot(),
                    sectionWidth: sectionWidth,
                )
            }
        }
        .task(id: refreshKey) {
            await loader.refreshContinuously(
                entriesDirectory: entriesDirectory,
                targetDate: targetDate,
            )
        }
        .id(id)
    }
}

struct WorkspaceSidebarTogglWeekFocusWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    let entriesPath: String
    let targetDate: String
    @StateObject private var loader = WorkspaceSidebarTogglWeeklyFocusLoader()

    var body: some View {
        let entriesDirectory = URL(filePath: entriesPath, directoryHint: .isDirectory)
        let refreshKey = TogglWeeklyFocusRefreshKey(entriesDirectory: entriesDirectory, targetDate: targetDate)

        Group {
            if isCompact {
                WorkspaceSidebarCompactTogglWeekFocusCard(
                    snapshot: loader.snapshot ?? TogglWeeklyFocusSnapshot(),
                    sectionWidth: sectionWidth,
                )
            } else {
                WorkspaceSidebarExpandedTogglWeekFocusCard(
                    snapshot: loader.snapshot ?? TogglWeeklyFocusSnapshot(),
                    sectionWidth: sectionWidth,
                )
            }
        }
        .task(id: refreshKey) {
            await loader.refreshContinuously(
                entriesDirectory: entriesDirectory,
                targetDate: targetDate,
            )
        }
        .id(id)
    }
}

private struct TogglWeeklyFocusRefreshKey: Hashable, Sendable {
    let entriesDirectory: URL
    let targetDate: String
}

@MainActor
final class WorkspaceSidebarTogglWeeklyFocusLoader: ObservableObject {
    typealias Load = @Sendable (URL, String, Date) -> TogglWeeklyFocusSnapshot

    @Published private(set) var snapshot: TogglWeeklyFocusSnapshot?

    private let load: Load

    init(load: @escaping Load = { entriesDirectory, targetDate, now in
        TogglWeeklyFocusAggregator(
            entriesDirectory: entriesDirectory,
            targetDateString: targetDate,
        ).load(now: now)
    }) {
        self.load = load
    }

    func refresh(entriesDirectory: URL, targetDate: String, now: Date = Date()) async {
        let load = load
        let nextSnapshot = await Task.detached(priority: .utility) {
            load(entriesDirectory, targetDate, now)
        }.value
        guard !Task.isCancelled else { return }
        snapshot = nextSnapshot
    }

    func refreshContinuously(entriesDirectory: URL, targetDate: String) async {
        while !Task.isCancelled {
            await refresh(entriesDirectory: entriesDirectory, targetDate: targetDate)
            do {
                try await Task.sleep(for: togglWeeklyFocusRefreshInterval)
            } catch {
                return
            }
        }
    }
}

struct TogglWeeklyFocusWeek: Equatable, Identifiable, Sendable {
    let startDate: Date
    let endDate: Date
    let dayCount: Int
    let totalSeconds: TimeInterval
    let isFuture: Bool
    let isCurrent: Bool

    var id: Date { startDate }

    var averageDailySeconds: TimeInterval {
        guard dayCount > 0 else { return 0 }
        return totalSeconds / TimeInterval(dayCount)
    }

    var averageDailyHours: Double {
        averageDailySeconds / 3600
    }
}

struct TogglWeeklyFocusDay: Equatable, Identifiable, Sendable {
    let date: Date
    let totalSeconds: TimeInterval
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }
}

struct TogglWeeklyFocusSnapshot: Equatable, Sendable {
    var weeks: [TogglWeeklyFocusWeek] = []
    var days: [TogglWeeklyFocusDay] = []
    var averageDailySeconds: TimeInterval = 0
    var currentWeekDailyAverageSeconds: TimeInterval = 0
    var totalWeekSeconds: TimeInterval = 0
    var weeksLeft: Int = 0
    var scannedEntryCount: Int = 0
    var errorMessage: String? = nil
}

struct TogglWeeklyFocusAggregator: Sendable {
    let entriesDirectory: URL
    let targetDateString: String

    func load(now: Date = Date()) -> TogglWeeklyFocusSnapshot {
        if let sqliteURL = SidebarSelfDataStore.sqliteURL(for: entriesDirectory) {
            return loadFromSelfData(sqliteURL: sqliteURL, now: now)
        }

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: entriesDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Can't read Toggl entries")
        }

        let entryUrls: [URL]
        do {
            entryUrls = try fileManager.contentsOfDirectory(
                at: entriesDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
            )
        } catch {
            return TogglWeeklyFocusSnapshot(errorMessage: "Can't read Toggl entries")
        }

        let entryFormatter = Self.makeTogglDateFormatter()
        var entries: [TogglWeeklyFocusEntry] = []

        for url in entryUrls where url.pathExtension == "md" {
            guard let entry = TogglWeeklyFocusEntry.parse(url: url, formatter: entryFormatter, now: now) else { continue }
            entries.append(entry)
        }

        return summarize(entries: entries, scannedEntryCount: entries.count, now: now)
    }

    private func loadFromSelfData(sqliteURL: URL, now: Date) -> TogglWeeklyFocusSnapshot {
        guard let entries = SidebarSelfDataStore.loadTimeEntries(from: sqliteURL, now: now) else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Can't read Toggl entries")
        }

        return summarize(
            entries: entries.map { TogglWeeklyFocusEntry(start: $0.start, stop: $0.stop) },
            scannedEntryCount: entries.count,
            now: now,
        )
    }

    private func summarize(entries: [TogglWeeklyFocusEntry], scannedEntryCount: Int, now: Date) -> TogglWeeklyFocusSnapshot {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale.current
        let todayStart = calendar.startOfDay(for: now)
        let targetDateFormatter = Self.makeTargetDateFormatter()
        guard let rawTargetDate = targetDateFormatter.date(from: targetDateString) else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Invalid target date")
        }
        let targetDay = calendar.startOfDay(for: rawTargetDate)
        guard targetDay >= todayStart else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Target date has passed")
        }

        guard let weekStart = Self.focusStartDay(calendar: calendar), weekStart <= targetDay else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Invalid target window")
        }
        let weeks = Self.weekWindows(startingAt: weekStart, targetDay: targetDay, calendar: calendar)
        guard !weeks.isEmpty else {
            return TogglWeeklyFocusSnapshot(errorMessage: "Invalid target window")
        }

        var totalsByWeek = Array(repeating: TimeInterval(0), count: weeks.count)
        let currentWeekDays = Self.currentWeekDays(containing: todayStart, calendar: calendar) ?? []
        var totalsByDay = Array(repeating: TimeInterval(0), count: currentWeekDays.count)
        for entry in entries {
            for index in weeks.indices {
                guard weeks[index].contains(entry.start) else { continue }
                totalsByWeek[index] += entry.stop.timeIntervalSince(entry.start)
                break
            }
            for index in currentWeekDays.indices {
                guard currentWeekDays[index].contains(entry.start) else { continue }
                totalsByDay[index] += entry.stop.timeIntervalSince(entry.start)
                break
            }
        }

        let summarizedWeeks = weeks.enumerated().map { index, week -> TogglWeeklyFocusWeek in
            let isCurrent = week.contains(todayStart)
            let dayCount = isCurrent
                ? Self.elapsedDayCount(from: week.startDate, to: todayStart, maxCount: week.dayCount, calendar: calendar)
                : week.dayCount
            return TogglWeeklyFocusWeek(
                startDate: week.startDate,
                endDate: week.endDate,
                dayCount: dayCount,
                totalSeconds: totalsByWeek[index],
                isFuture: week.startDate > todayStart,
                isCurrent: isCurrent,
            )
        }
        let currentAverage = summarizedWeeks.first(where: \.isCurrent)?.averageDailySeconds
            ?? summarizedWeeks.first?.averageDailySeconds
            ?? 0
        let weeksLeft = max(0, summarizedWeeks.filter { $0.startDate > todayStart }.count)
        let summarizedDays = currentWeekDays.enumerated().map { index, day -> TogglWeeklyFocusDay in
            TogglWeeklyFocusDay(
                date: day.startDate,
                totalSeconds: totalsByDay[index],
                isToday: day.contains(todayStart),
                isFuture: day.startDate > todayStart,
            )
        }
        let currentWeekElapsedDayCount = max(1, summarizedDays.filter { !$0.isFuture }.count)
        let totalWeekSeconds = totalsByDay.reduce(0, +)

        return TogglWeeklyFocusSnapshot(
            weeks: summarizedWeeks,
            days: summarizedDays,
            averageDailySeconds: currentAverage,
            currentWeekDailyAverageSeconds: totalWeekSeconds / TimeInterval(currentWeekElapsedDayCount),
            totalWeekSeconds: totalWeekSeconds,
            weeksLeft: weeksLeft,
            scannedEntryCount: scannedEntryCount,
            errorMessage: nil,
        )
    }

    private static func currentWeekDays(containing day: Date, calendar: Calendar) -> [TogglWeeklyFocusDayWindow]? {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: day)?.start else {
            return nil
        }
        let dayCount = calendar.range(of: .weekday, in: .weekOfYear, for: day)?.count ?? 7
        return (0 ..< dayCount).compactMap { offset in
            guard let startDate = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let endExclusive = calendar.date(byAdding: .day, value: 1, to: startDate)
            else {
                return nil
            }
            return TogglWeeklyFocusDayWindow(startDate: startDate, endExclusive: endExclusive)
        }
    }

    private static func weekWindows(
        startingAt startDate: Date,
        targetDay: Date,
        calendar: Calendar,
    ) -> [TogglWeeklyFocusWeekWindow] {
        var result: [TogglWeeklyFocusWeekWindow] = []
        var currentStart = startDate

        while currentStart <= targetDay {
            guard let nextStart = calendar.date(byAdding: .day, value: 7, to: currentStart),
                  let fullWeekEnd = calendar.date(byAdding: .day, value: 6, to: currentStart)
            else {
                break
            }

            let endDate = min(fullWeekEnd, targetDay)
            let dayCount = (calendar.dateComponents([.day], from: currentStart, to: endDate).day ?? 0) + 1
            result.append(TogglWeeklyFocusWeekWindow(
                startDate: currentStart,
                endDate: endDate,
                endExclusive: nextStart,
                dayCount: max(1, dayCount),
            ))
            currentStart = nextStart
        }

        return result
    }

    private static func elapsedDayCount(
        from startDate: Date,
        to day: Date,
        maxCount: Int,
        calendar: Calendar,
    ) -> Int {
        let elapsedDays = (calendar.dateComponents([.day], from: startDate, to: day).day ?? 0) + 1
        return max(1, min(elapsedDays, maxCount))
    }

    private static func focusStartDay(calendar: Calendar) -> Date? {
        makeTargetDateFormatter().date(from: togglWeeklyFocusStartDateString).map {
            calendar.startOfDay(for: $0)
        }
    }

    private static func makeTogglDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func makeTargetDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct TogglWeeklyFocusWeekWindow {
    let startDate: Date
    let endDate: Date
    let endExclusive: Date
    let dayCount: Int

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endExclusive
    }
}

private struct TogglWeeklyFocusDayWindow {
    let startDate: Date
    let endExclusive: Date

    func contains(_ date: Date) -> Bool {
        date >= startDate && date < endExclusive
    }
}

private struct TogglWeeklyFocusEntry {
    let start: Date
    let stop: Date

    static func parse(url: URL, formatter: DateFormatter, now: Date) -> TogglWeeklyFocusEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let fields = TogglWeeklyFocusFrontMatter.fields(in: text)
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
        return TogglWeeklyFocusEntry(start: start, stop: effectiveStop)
    }
}

private enum TogglWeeklyFocusFrontMatter {
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

private struct WorkspaceSidebarExpandedTogglWeeklyFocusCard: View {
    let snapshot: TogglWeeklyFocusSnapshot
    let sectionWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.section) {
            HStack(alignment: .firstTextBaseline, spacing: WinMuxSpacing.regular) {
                Text("Periodically focus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.content(.primary))

                Spacer(minLength: 2)

                Text(averageText)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.errorMessage == nil ? palette.content(.secondary) : palette.color(.red, .color9))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
                    .lineLimit(2)
            } else if snapshot.weeks.isEmpty {
                Text("No weeks")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TogglPeriodFocusLineChart(
                    weeks: snapshot.weeks,
                    averageHours: snapshot.averageDailySeconds / 3600,
                    palette: palette,
                )
                    .frame(height: togglPeriodFocusChartHeight + 20)
                    .padding(.horizontal, standardGap * 0)
            }
        }
        .padding(workspaceSidebarWidgetContentPadding)
        .frame(width: sectionWidth, alignment: .leading)
        .background(TogglPeriodFocusCardBackground(palette: palette))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var averageText: String {
        snapshot.errorMessage == nil
            ? togglWeeklyFocusCompactHoursText(snapshot.averageDailySeconds)
            : "--"
    }

    private var accessibilitySummary: String {
        if let errorMessage = snapshot.errorMessage {
            return errorMessage
        }
        return "Periodically focus, \(togglWeeklyFocusAccessibilityHoursText(snapshot.averageDailySeconds)) average daily focus"
    }
}

private struct WorkspaceSidebarCompactTogglWeekFocusCard: View {
    let snapshot: TogglWeeklyFocusSnapshot
    let sectionWidth: CGFloat

    var body: some View {
        VStack(alignment: .center, spacing: standardGap * 3.5) {
            TogglWeekFocusIcon()
                .frame(width: 18, height: 18)
                .foregroundStyle(togglWeekFocusTextColor)
                .padding(standardGap * 3)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(togglWeekFocusBackgroundColor)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(togglWeekFocusBorderColor, lineWidth: 1)
                        }
                }

            if let errorMessage = snapshot.errorMessage {
                Text("!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                    .lineLimit(1)
                    .help(errorMessage)
            } else {
                Text(togglWeeklyFocusCompactHoursText(snapshot.currentWeekDailyAverageSeconds))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                VStack(spacing: standardGap * 0.5) {
                    Text("this")
                    Text("week")
                }
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                .lineLimit(1)
            }
        }
        .frame(width: sectionWidth, height: 150, alignment: .center)
        .background(WorkspaceSidebarStatusCardBackground())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        if let errorMessage = snapshot.errorMessage {
            return errorMessage
        }
        return "Focus of the week, \(togglWeeklyFocusAccessibilityHoursText(snapshot.currentWeekDailyAverageSeconds)) daily average"
    }
}

private struct WorkspaceSidebarExpandedTogglWeekFocusCard: View {
    let snapshot: TogglWeeklyFocusSnapshot
    let sectionWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 5) {
            HStack(alignment: .firstTextBaseline, spacing: standardGap * 4) {
                HStack(spacing: standardGap * 3) {
                    TogglWeekFocusIcon()
                        .frame(width: 13, height: 13)
                    Text("Week")
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(togglWeekFocusTextColor)

                Spacer(minLength: 8)

                if snapshot.errorMessage == nil {
                    Text(togglWeeklyFocusCompactHoursText(snapshot.totalWeekSeconds))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                        .lineLimit(1)
                }
            }

            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if snapshot.days.isEmpty {
                Text("No days")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TogglWeeklyFocusDayList(days: snapshot.days)
            }
        }
        .padding(workspaceSidebarUnifiedGap)
        .frame(width: sectionWidth, alignment: .leading)
        .background(WorkspaceSidebarStatusCardBackground())
        .accessibilityElement(children: .combine)
    }
}

private struct TogglPeriodFocusLineChart: View {
    let weeks: [TogglWeeklyFocusWeek]
    let averageHours: Double
    let palette: WinMuxOverlayPalette

    private var completedWeeks: [TogglWeeklyFocusWeek] {
        weeks.filter { !$0.isFuture }
    }

    private var yDomain: ClosedRange<Double> {
        let values = completedWeeks.map(\.averageDailyHours)
        let upperBound = max(
            1,
            max(values.max() ?? 0, togglPeriodFocusGuidelines.max() ?? 0) * 1.08,
        )
        return 0 ... upperBound
    }

    private var xDomain: ClosedRange<Date> {
        let fallback = Date()
        return (weeks.first?.startDate ?? fallback) ... (weeks.last?.startDate ?? fallback)
    }

    var body: some View {
        chart
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(togglPeriodFocusMonthLabel(for: date))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(palette.content(.secondary))
                                .fixedSize(horizontal: true, vertical: false)
                                .offset(y: standardGap * 3)
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("X axis", 0))
                .foregroundStyle(palette.geistBorder(.normal))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(togglPeriodFocusGuidelines, id: \.self) { guideline in
                RuleMark(y: .value("Guideline", guideline))
                    .foregroundStyle(togglPeriodFocusGuidelineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .annotation(position: .trailing, alignment: .center, spacing: standardGap * 3) {
                        Text(String(format: "%.1fh", guideline))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(palette.content(.secondary).opacity(0.45))
                    }
            }

            if averageHours > 0 {
                RuleMark(y: .value("Average", averageHours))
                    .foregroundStyle(palette.content(.secondary).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: standardGap * 3) {
                        Text(String(format: "%.1fh", averageHours))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(palette.content(.primary))
                    }
            }

            ForEach(completedWeeks) { week in
                LineMark(
                    x: .value("Week", week.startDate),
                    y: .value("Daily average", week.averageDailyHours),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.highContrastBackground(.normal))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            ForEach(completedWeeks) { week in
                PointMark(
                    x: .value("Week", week.startDate),
                    y: .value("Daily average", week.averageDailyHours),
                )
                .foregroundStyle(
                    togglPeriodFocusDotColor
                )
                .symbolSize(week.isCurrent ? 34 : 20)
            }
        }
        .chartXScale(domain: xDomain, range: .plotDimension(startPadding: 0, endPadding: 0))
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.leading, standardGap * 0)
                .padding(.trailing, standardGap * 13)
                .padding(.bottom, standardGap * 4)
        }
    }

    private var axisDates: [Date] {
        weeks.enumerated().compactMap { index, week in
            guard index == 0 || Calendar.current.component(.month, from: week.startDate)
                != Calendar.current.component(.month, from: weeks[index - 1].startDate)
            else {
                return nil
            }
            return week.startDate
        }
    }
}

private struct TogglPeriodFocusCardBackground: View {
    let palette: WinMuxOverlayPalette

    var body: some View {
        RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
            .fill(palette.geistBackground(.primary))
            .overlay {
                RoundedRectangle(cornerRadius: workspaceSidebarStatusCornerRadius, style: .continuous)
                    .strokeBorder(palette.geistBorder(.normal), lineWidth: 0.75)
            }
    }
}

func togglPeriodFocusMonthLabel(for date: Date) -> String {
    let label = date.formatted(.dateTime.month(.abbreviated))
    return String(label.prefix(3))
}

private struct TogglWeeklyFocusDayList: View {
    let days: [TogglWeeklyFocusDay]

    private var maxSeconds: TimeInterval {
        max(togglWeeklyFocusMaxDailySeconds, days.map(\.totalSeconds).max() ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 3) {
            ForEach(days) { day in
                TogglWeeklyFocusDayRow(day: day, maxSeconds: maxSeconds)
            }
        }
    }
}

private struct TogglWeeklyFocusDayRow: View {
    let day: TogglWeeklyFocusDay
    let maxSeconds: TimeInterval

    private var ratio: CGFloat {
        guard maxSeconds > 0 else { return 0 }
        return CGFloat(max(0, min(day.totalSeconds / maxSeconds, 1)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: standardGap * 2) {
            HStack(alignment: .firstTextBaseline, spacing: standardGap * 4) {
                Text(togglWeeklyFocusDayLabelText(for: day.date))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(workspaceSidebarWidgetContent(day.isFuture ? .secondary : .primary))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(day.isFuture ? "--" : togglWeeklyFocusCompactHoursText(day.totalSeconds))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    .lineLimit(1)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(workspaceSidebarWidgetComponentBackground(day.isFuture ? .normal : .hover))

                    if !day.isFuture, day.totalSeconds > 0 {
                        Capsule()
                            .fill(day.isToday ? togglWeekFocusCurrentFillColor : togglWeekFocusFillColor)
                            .frame(width: max(3, geometry.size.width * ratio))
                    }
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    private var accessibilityText: String {
        let labelText = togglWeeklyFocusDayLabelText(for: day.date)
        if day.isFuture {
            return "\(labelText), future day"
        }
        return "\(labelText), \(togglWeeklyFocusAccessibilityHoursText(day.totalSeconds)) focus"
    }
}

private struct TogglPeriodFocusIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let lineWidth = max(1.2, size.width * 0.075)
            let circle = rect.insetBy(dx: size.width * 0.08, dy: size.height * 0.08)
            var path = Path(ellipseIn: circle)
            context.stroke(path, with: .foreground, lineWidth: lineWidth)

            path = Path(ellipseIn: rect.insetBy(dx: size.width * 0.27, dy: size.height * 0.27))
            context.stroke(path, with: .foreground, lineWidth: lineWidth)

            path = Path()
            path.addEllipse(in: CGRect(
                x: size.width * 0.45,
                y: size.height * 0.45,
                width: size.width * 0.10,
                height: size.height * 0.10,
            ))
            context.fill(path, with: .foreground)
        }
    }
}

private struct TogglWeekFocusIcon: View {
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let lineWidth = max(1.2, size.width * 0.075)
            let calendarRect = rect.insetBy(dx: size.width * 0.12, dy: size.height * 0.14)
            let radius = min(size.width, size.height) * 0.12
            var path = Path(roundedRect: calendarRect, cornerRadius: radius)
            context.stroke(path, with: .foreground, lineWidth: lineWidth)

            path = Path()
            path.move(to: CGPoint(x: calendarRect.minX, y: calendarRect.minY + calendarRect.height * 0.30))
            path.addLine(to: CGPoint(x: calendarRect.maxX, y: calendarRect.minY + calendarRect.height * 0.30))
            context.stroke(path, with: .foreground, lineWidth: lineWidth)

            for xRatio in [0.32, 0.50, 0.68] {
                for yRatio in [0.50, 0.68] {
                    path = Path(ellipseIn: CGRect(
                        x: size.width * xRatio - size.width * 0.035,
                        y: size.height * yRatio - size.height * 0.035,
                        width: size.width * 0.07,
                        height: size.height * 0.07,
                    ))
                    context.fill(path, with: .foreground)
                }
            }
        }
    }
}

private func togglWeeklyFocusCompactHoursText(_ seconds: TimeInterval) -> String {
    let hours = seconds / 60 / 60
    if hours >= 10 {
        return String(format: "%.0fh", hours)
    }
    return String(format: "%.1fh", hours)
}

private func togglWeeklyFocusAccessibilityHoursText(_ seconds: TimeInterval) -> String {
    let minutes = max(0, Int((seconds / 60).rounded()))
    let hours = minutes / 60
    let remainingMinutes = minutes % 60
    if hours == 0 {
        return "\(remainingMinutes) minutes"
    }
    if remainingMinutes == 0 {
        return "\(hours) hours"
    }
    return "\(hours) hours \(remainingMinutes) minutes"
}

func togglWeeklyFocusWeekLabelText(for week: TogglWeeklyFocusWeek, previousWeek: TogglWeeklyFocusWeek?) -> String {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = .current
    let month = calendar.component(.month, from: week.startDate)
    let previousMonth = previousWeek.map { calendar.component(.month, from: $0.startDate) }
    if previousMonth != nil, previousMonth != month {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: week.startDate).uppercased()
    }
    return "\(calendar.component(.day, from: week.startDate))\(togglWeeklyFocusOrdinalSuffix(for: week.startDate, calendar: calendar))"
}

func togglWeeklyFocusDayLabelText(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "EEE"
    return formatter.string(from: date).uppercased()
}

private func togglWeeklyFocusOrdinalSuffix(for date: Date, calendar: Calendar) -> String {
    let day = calendar.component(.day, from: date)
    let teenRemainder = day % 100
    if 11 ... 13 ~= teenRemainder {
        return "th"
    }
    switch day % 10 {
        case 1:
            return "st"
        case 2:
            return "nd"
        case 3:
            return "rd"
        default:
            return "th"
    }
}
