import Charts
import Foundation
import SwiftUI

private let todayFocusTargetHoursByWeekday = Array(repeating: 11, count: 7)
private let todayFocusChartHeight: CGFloat = 92
private let todayFocusGuidelines: [Double] = [8, 11]
private let todayFocusGuidelineColor = workspaceSidebarWidgetColor(.color6)
private let todayFocusCompactCellSpacing: CGFloat = workspaceSidebarStandardGap
private let todayFocusCompactCellCornerRadius: CGFloat = 5
private let todayFocusDotColor = workspaceSidebarWidgetColor(.color9)
private let todayFocusRefreshInterval: Duration = .seconds(60)

struct WorkspaceSidebarTodayFocusWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    let entriesPath: String
    @StateObject private var loader = WorkspaceSidebarTodayFocusLoader()

    var body: some View {
        let dataSource = URL(filePath: entriesPath, directoryHint: .isDirectory)

        TodayFocusCard(
            snapshot: loader.snapshot ?? TodayFocusSnapshot.placeholder(now: Date()),
            sectionWidth: sectionWidth,
            isCompact: isCompact,
        )
        .task(id: dataSource) {
            await loader.refreshContinuously(dataSource: dataSource)
        }
        .id(id)
    }
}

private struct TodayFocusRefreshKey: Hashable, Sendable {
    let dataSource: URL
    let minute: Int64

    init(dataSource: URL, now: Date) {
        self.dataSource = dataSource
        minute = Int64(now.timeIntervalSinceReferenceDate / 60)
    }
}

@MainActor
final class WorkspaceSidebarTodayFocusLoader: ObservableObject {
    typealias Load = @Sendable (URL, Date) -> TodayFocusSnapshot

    @Published private(set) var snapshot: TodayFocusSnapshot?

    private let load: Load
    private var activeRefreshKey: TodayFocusRefreshKey?
    private var completedRefreshKey: TodayFocusRefreshKey?
    private var refreshGeneration: UInt64 = 0
    private var loadTask: Task<Void, Never>?

    init(load: @escaping Load = { dataSource, now in
        TodayFocusAggregator(dataSource: dataSource).load(now: now)
    }) {
        self.load = load
    }

    func refresh(dataSource: URL, now: Date) {
        let key = TodayFocusRefreshKey(dataSource: dataSource, now: now)
        guard key != activeRefreshKey, key != completedRefreshKey else { return }

        activeRefreshKey = key
        refreshGeneration &+= 1
        let generation = refreshGeneration
        loadTask?.cancel()
        let load = load
        loadTask = Task { [weak self] in
            let nextSnapshot = await Task.detached(priority: .utility) {
                load(dataSource, now)
            }.value
            guard !Task.isCancelled, let self else { return }
            guard self.refreshGeneration == generation, self.activeRefreshKey == key else { return }

            self.snapshot = nextSnapshot
            self.completedRefreshKey = key
            self.activeRefreshKey = nil
            self.loadTask = nil
        }
    }

    func refreshContinuously(dataSource: URL) async {
        while !Task.isCancelled {
            refresh(dataSource: dataSource, now: Date())
            do {
                try await Task.sleep(for: todayFocusRefreshInterval)
            } catch {
                return
            }
        }
    }

    deinit {
        loadTask?.cancel()
    }
}

struct TodayFocusSnapshot: Equatable, Sendable {
    let focusedSeconds: TimeInterval
    let targetHours: Int
    let errorMessage: String?
    var days: [TodayFocusDay] = []

    var focusedHours: Double {
        focusedSeconds / 3600
    }

    var percentage: Int {
        guard targetHours > 0 else { return 0 }
        return Int((focusedHours / Double(targetHours) * 100).rounded())
    }

    var averageFocusedSeconds: TimeInterval {
        let elapsedDays = days.filter { !$0.isFuture }
        guard !elapsedDays.isEmpty else { return focusedSeconds }
        return elapsedDays.reduce(0) { $0 + $1.focusedSeconds } / TimeInterval(elapsedDays.count)
    }

    fileprivate static func placeholder(now: Date) -> TodayFocusSnapshot {
        TodayFocusSnapshot(
            focusedSeconds: 0,
            targetHours: todayFocusTargetHours(now: now),
            errorMessage: nil,
            days: todayFocusWeekDays(now: now),
        )
    }
}

struct TodayFocusDay: Equatable, Identifiable, Sendable {
    let date: Date
    let focusedSeconds: TimeInterval
    let isToday: Bool
    let isFuture: Bool

    var id: Date { date }

    var focusedHours: Double {
        focusedSeconds / 3600
    }
}

struct TodayFocusAggregator: Sendable {
    let dataSource: URL

    func load(now: Date = Date()) -> TodayFocusSnapshot {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        calendar.locale = Locale.current
        let targetHours = todayFocusTargetHours(now: now, calendar: calendar)
        let emptyDays = todayFocusWeekDays(now: now, calendar: calendar)

        guard let sqliteURL = SidebarSelfDataStore.sqliteURL(for: dataSource),
              let entries = SidebarSelfDataStore.loadTimeEntries(from: sqliteURL, now: now)
        else {
            return TodayFocusSnapshot(
                focusedSeconds: 0,
                targetHours: targetHours,
                errorMessage: "Can't read self_data",
                days: emptyDays,
            )
        }

        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else {
            return TodayFocusSnapshot(
                focusedSeconds: 0,
                targetHours: targetHours,
                errorMessage: "Can't resolve this week",
                days: emptyDays,
            )
        }

        let days = (0 ..< 7).compactMap { offset -> TodayFocusDay? in
            guard let start = calendar.date(byAdding: .day, value: offset, to: weekStart),
                  let end = calendar.date(byAdding: .day, value: 1, to: start)
            else { return nil }

            let focusedSeconds = entries.reduce(TimeInterval(0)) { total, entry in
                let overlap = min(min(entry.stop, now), end).timeIntervalSince(max(entry.start, start))
                return total + max(0, overlap)
            }
            return TodayFocusDay(
                date: start,
                focusedSeconds: focusedSeconds,
                isToday: calendar.isDate(start, inSameDayAs: now),
                isFuture: start > now,
            )
        }
        let focusedSeconds = days.first(where: \.isToday)?.focusedSeconds ?? 0
        return TodayFocusSnapshot(
            focusedSeconds: focusedSeconds,
            targetHours: targetHours,
            errorMessage: nil,
            days: days,
        )
    }
}

private func todayFocusWeekDays(now: Date, calendar inputCalendar: Calendar? = nil) -> [TodayFocusDay] {
    var calendar = inputCalendar ?? Calendar(identifier: .iso8601)
    calendar.timeZone = .current
    guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
    return (0 ..< 7).compactMap { offset in
        guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
        return TodayFocusDay(
            date: date,
            focusedSeconds: 0,
            isToday: calendar.isDate(date, inSameDayAs: now),
            isFuture: date > now,
        )
    }
}

private func todayFocusTargetHours(now: Date, calendar: Calendar = .current) -> Int {
    let weekday = calendar.component(.weekday, from: now) - 1
    return todayFocusTargetHoursByWeekday.indices.contains(weekday)
        ? todayFocusTargetHoursByWeekday[weekday]
        : 0
}

private struct TodayFocusCard: View {
    let snapshot: TodayFocusSnapshot
    let sectionWidth: CGFloat
    let isCompact: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        Group {
            if isCompact {
                TodayFocusCompactHourGrid(snapshot: snapshot, sectionWidth: sectionWidth, palette: palette)
                    .frame(width: sectionWidth, alignment: .center)
            } else {
                expandedCard
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: WinMuxSpacing.section) {
            HStack(alignment: .firstTextBaseline, spacing: WinMuxSpacing.regular) {
                Text("Weekly focus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.content(.primary))
                Spacer(minLength: 2)
                Text(averageText)
                    .monospacedDigit()
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(summaryColor)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            if let errorMessage = snapshot.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
                    .lineLimit(2)
            } else {
                TodayFocusWeekChart(snapshot: snapshot, palette: palette)
                    .frame(height: todayFocusChartHeight + 20)
            }
        }
        .padding(workspaceSidebarWidgetContentPadding)
        .frame(width: sectionWidth, alignment: .leading)
        .background(TodayFocusCardBackground(palette: palette))
    }

    private var averageText: String {
        if snapshot.errorMessage != nil {
            return "—"
        }
        return String(format: "%.1fh", snapshot.averageFocusedSeconds / 3600)
    }

    private var summaryColor: Color {
        if snapshot.errorMessage != nil {
            return palette.color(.red, .color9)
        }
        return palette.content(.secondary)
    }

    private var accessibilitySummary: String {
        if let errorMessage = snapshot.errorMessage {
            return errorMessage
        }
        return "This week's focus, \(String(format: "%.1f", snapshot.averageFocusedSeconds / 3600)) hours average per elapsed day"
    }
}

private struct TodayFocusCompactHourGrid: View {
    private let cellSize = workspaceSidebarCompactGridCellSize

    let snapshot: TodayFocusSnapshot
    let sectionWidth: CGFloat
    let palette: WinMuxOverlayPalette

    var body: some View {
        Group {
            if snapshot.errorMessage != nil {
                compactCell(fill: palette.color(.red, .color9))
            } else if snapshot.targetHours == 0 {
                compactCell(fill: palette.componentBackground(.normal))
            } else {
                VStack(spacing: todayFocusCompactCellSpacing) {
                    ForEach(0 ..< snapshot.targetHours, id: \.self) { index in
                        TodayFocusCompactHourCell(
                            cellSize: cellSize,
                            progress: progress(at: index),
                            palette: palette,
                        )
                    }
                }
            }
        }
        .frame(width: sectionWidth)
    }

    private func progress(at index: Int) -> Double {
        max(0, min(1, snapshot.focusedHours - Double(index)))
    }

    private func compactCell(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: todayFocusCompactCellCornerRadius, style: .continuous)
            .fill(fill)
            .frame(width: cellSize, height: cellSize)
    }
}

private struct TodayFocusCompactHourCell: View {
    let cellSize: CGFloat
    let progress: Double
    let palette: WinMuxOverlayPalette

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: todayFocusCompactCellCornerRadius, style: .continuous)
                .fill(palette.componentBackground(.normal))

            if progress >= 1 {
                RoundedRectangle(cornerRadius: todayFocusCompactCellCornerRadius, style: .continuous)
                    .fill(palette.highContrastBackground(.normal))
            } else if progress > 0 {
                Rectangle()
                    .fill(palette.color(.amber, .color9))
                    .frame(height: cellSize * progress)
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipShape(RoundedRectangle(cornerRadius: todayFocusCompactCellCornerRadius, style: .continuous))
    }
}

private struct TodayFocusWeekChart: View {
    let snapshot: TodayFocusSnapshot
    let palette: WinMuxOverlayPalette

    var body: some View {
        TodayFocusLineChart(snapshot: snapshot, palette: palette, showsLabels: true)
    }
}

private struct TodayFocusLineChart: View {
    let snapshot: TodayFocusSnapshot
    let palette: WinMuxOverlayPalette
    let showsLabels: Bool

    private var visibleDays: [TodayFocusDay] {
        snapshot.days
    }

    private var completedDays: [TodayFocusDay] {
        visibleDays.filter { !$0.isFuture }
    }

    private var yMaximum: Double {
        max(
            1,
            (visibleDays.map(\.focusedHours).max() ?? 0) * 1.35,
            (todayFocusGuidelines.max() ?? 0) * 1.08,
        )
    }

    private var xDomain: ClosedRange<Date> {
        let fallback = Date()
        return (snapshot.days.first?.date ?? fallback) ... (snapshot.days.last?.date ?? fallback)
    }

    @ViewBuilder
    var body: some View {
        if showsLabels {
            chart
                .chartXAxis {
                    AxisMarks(values: snapshot.days.map(\.date)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self),
                               let day = snapshot.days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) })
                            {
                                Text(date.formatted(.dateTime.weekday(.narrow)))
                                    .font(.system(size: 11, weight: day.isToday ? .semibold : .regular))
                                    .foregroundStyle(palette.content(.secondary))
                                    .offset(y: standardGap * 3)
                            }
                        }
                    }
                }
                .chartYAxis(.hidden)
        } else {
            chart
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
        }
    }

    private var chart: some View {
        Chart {
            RuleMark(y: .value("X axis", 0))
                .foregroundStyle(palette.geistBorder(.normal))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(todayFocusGuidelines, id: \.self) { guideline in
                RuleMark(y: .value("Guideline", guideline))
                    .foregroundStyle(todayFocusGuidelineColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 4]))
                    .annotation(position: .trailing, alignment: .center, spacing: standardGap * 3) {
                        Text(String(format: "%.0fh", guideline))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(palette.content(.secondary).opacity(0.45))
                    }
            }

            if snapshot.averageFocusedSeconds > 0 {
                RuleMark(y: .value("Average", snapshot.averageFocusedSeconds / 3600))
                    .foregroundStyle(palette.content(.secondary).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: standardGap * 3) {
                        Text(String(format: "%.1fh", snapshot.averageFocusedSeconds / 3600))
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(palette.content(.primary))
                    }
            }

            ForEach(completedDays) { day in
                LineMark(
                    x: .value("Day", day.date),
                    y: .value("Focus", day.focusedHours),
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(palette.highContrastBackground(.normal))
                .lineStyle(StrokeStyle(lineWidth: showsLabels ? 2 : 1.5, lineCap: .round, lineJoin: .round))
            }

            ForEach(completedDays) { day in
                PointMark(
                    x: .value("Day", day.date),
                    y: .value("Focus", day.focusedHours),
                )
                .foregroundStyle(todayFocusDotColor)
                .symbolSize(showsLabels ? (day.isToday ? 34 : 20) : 14)
                .annotation(position: .top, alignment: .center, spacing: standardGap * 2) {
                    if showsLabels {
                        Text(String(format: "%.1f", day.focusedHours))
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(palette.content(.primary))
                    }
                }
            }
        }
        .chartXScale(domain: xDomain, range: .plotDimension(startPadding: 0, endPadding: 0))
        .chartYScale(domain: 0 ... yMaximum)
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .padding(.trailing, showsLabels ? 26 : 0)
                .padding(.bottom, showsLabels ? 8 : 2)
        }
    }
}

private struct TodayFocusCardBackground: View {
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
