import Foundation
import SwiftUI

private let periodFallbackStart = "2026-06-15"
private let periodFallbackEnd = "2026-09-12"
private let periodFallbackToday = "2026-06-26"
private let defaultPeriodTogglPath = "/Users/side/Documents/now/my_app/self/self_ob/Toggl"
private let targetSessionCount = 3
private let targetFocusSeconds: TimeInterval = 4 * 60 * 60

struct WorkspaceSidebarPeriodHeatmapWidget: View {
    let id: String
    let sectionWidth: CGFloat
    let isCompact: Bool
    let entriesPath: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = PeriodHeatmapAggregator(
                entriesDirectory: URL(filePath: entriesPath, directoryHint: .isDirectory),
                togglDirectory: URL(filePath: defaultPeriodTogglPath, directoryHint: .isDirectory),
            ).load(now: context.date)

            Group {
                if isCompact {
                    WorkspaceSidebarCompactPeriodProgressCard(
                        snapshot: snapshot,
                        sectionWidth: sectionWidth,
                    )
                } else {
                    WorkspaceSidebarExpandedPeriodProgressCard(
                        snapshot: snapshot,
                        sectionWidth: sectionWidth,
                    )
                }
            }
        }
        .id(id)
    }
}

struct PeriodHeatmapSnapshot: Equatable, Sendable {
    var name: String = "Y3 summer"
    var from: Date
    var to: Date
    var today: Date
    var sessionCount: Int = 0
    var runningSeconds: TimeInterval = 0
    var runningMinute: Int = 0
    var errorMessage: String? = nil

    var totalDays: Int {
        max(0, Self.dayDistance(from: from, to: to) + 1)
    }

    var currentDay: Int {
        min(max(Self.dayDistance(from: from, to: today) + 1, 1), max(totalDays, 1))
    }

    var totalWeeks: Int {
        max(Int(ceil(Double(max(totalDays, 1)) / 7.0)), 1)
    }

    var currentWeek: Int {
        min(max(Int(ceil(Double(currentDay) / 7.0)), 1), totalWeeks)
    }

    var dayOfWeekInPeriod: Int {
        ((max(currentDay, 1) - 1) % 7) + 1
    }

    var runningHoursText: String {
        let hours = runningSeconds / 3600
        if hours >= 10 || abs(hours.rounded() - hours) < 0.05 {
            return String(format: "%.0f", hours)
        }
        return String(format: "%.1f", hours)
    }

    var weekProgress: Double {
        Double(currentWeek) / Double(max(totalWeeks, 1))
    }

    var dayProgress: Double {
        Double(dayOfWeekInPeriod) / 7.0
    }

    var sessionProgress: Double {
        Double(min(max(sessionCount, 0), targetSessionCount)) / Double(targetSessionCount)
    }

    var timeProgress: Double {
        min(max(runningSeconds / targetFocusSeconds, 0), 1)
    }

    var minuteProgress: Double {
        Double(min(max(runningMinute, 0), 60)) / 60.0
    }

    private static func dayDistance(from start: Date, to end: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

struct PeriodHeatmapAggregator: Sendable {
    let entriesDirectory: URL
    let togglDirectory: URL

    func load(now: Date = Date()) -> PeriodHeatmapSnapshot {
        let period = loadPeriod(now: now)
        let togglSummary = PeriodTogglTodaySummary.load(from: togglDirectory, now: now)
        return PeriodHeatmapSnapshot(
            name: period.name,
            from: period.from,
            to: period.to,
            today: Calendar.current.startOfDay(for: now),
            sessionCount: togglSummary.sessionCount,
            runningSeconds: togglSummary.runningSeconds,
            runningMinute: Int(togglSummary.runningSeconds / 60) % 60,
        )
    }

    private func loadPeriod(now: Date) -> (name: String, from: Date, to: Date) {
        if let sqliteURL = SidebarSelfDataStore.sqliteURL(for: entriesDirectory),
           let period = SidebarSelfDataStore.loadCurrentPeriod(from: sqliteURL, now: now)
        {
            return (period.name, period.from, period.to)
        }

        let formatter = Self.localDateFormatter()
        return (
            "Y3 summer",
            formatter.date(from: periodFallbackStart) ?? now,
            formatter.date(from: periodFallbackEnd) ?? now
        )
    }

    static func snapshot(name: String, from: Date, to: Date, now: Date) -> PeriodHeatmapSnapshot {
        PeriodHeatmapSnapshot(
            name: name,
            from: from,
            to: to,
            today: now,
        )
    }

    private static func localDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

private struct PeriodTogglTodaySummary: Equatable, Sendable {
    let sessionCount: Int
    let runningSeconds: TimeInterval

    static func load(from directory: URL, now: Date) -> PeriodTogglTodaySummary {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return PeriodTogglTodaySummary(sessionCount: 0, runningSeconds: 0)
        }

        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        )) ?? []

        let calendar = Calendar.current
        let todayPrefix = Self.localDateFormatter.string(from: now)
        let entries = urls
            .filter { $0.pathExtension == "md" && $0.lastPathComponent.hasPrefix(todayPrefix) }
            .compactMap { PeriodTogglEntry.parse(url: $0) }
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }

        let latestStart = entries.last?.start
        return PeriodTogglTodaySummary(
            sessionCount: entries.count,
            runningSeconds: latestStart.map { max(0, now.timeIntervalSince($0)) } ?? 0,
        )
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct PeriodTogglEntry: Equatable {
    let start: Date

    static func parse(url: URL) -> PeriodTogglEntry? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let startRaw = frontMatterValue("start_at_utc", in: text)
            ?? frontMatterValue("start", in: text)
        guard let startRaw,
              let start = parseDate(startRaw)
        else {
            return nil
        }
        return PeriodTogglEntry(start: start)
    }

    private static func frontMatterValue(_ key: String, in text: String) -> String? {
        let prefix = "\(key):"
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(prefix) else { continue }
            return trimmed
                .dropFirst(prefix.count)
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private static func parseDate(_ raw: String) -> Date? {
        makeUTCFormatter().date(from: raw) ?? makeLocalFormatter().date(from: raw)
    }

    private static func makeUTCFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func makeLocalFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }
}

private struct WorkspaceSidebarCompactPeriodProgressCard: View {
    let snapshot: PeriodHeatmapSnapshot
    let sectionWidth: CGFloat

    var body: some View {
        PeriodRingGaugeGrid(
            metrics: snapshot.periodRingMetrics(compact: true),
            sectionWidth: sectionWidth,
            compact: true,
        )
        .frame(width: sectionWidth, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        "Week \(snapshot.currentWeek) of \(snapshot.totalWeeks)"
    }

}

private struct WorkspaceSidebarExpandedPeriodProgressCard: View {
    let snapshot: PeriodHeatmapSnapshot
    let sectionWidth: CGFloat

    var body: some View {
        PeriodRingGaugeGrid(
            metrics: snapshot.periodRingMetrics(compact: false),
            sectionWidth: sectionWidth,
            compact: false,
        )
        .frame(width: sectionWidth, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Week \(snapshot.currentWeek) of \(snapshot.totalWeeks)"))
    }
}

private struct PeriodRingGaugeGrid: View {
    let metrics: [PeriodRingMetric]
    let sectionWidth: CGFloat
    let compact: Bool

    var body: some View {
        Group {
            if let metric = metrics.first {
                PeriodUnitRingGauge(
                    metric: metric,
                    size: gaugeSize,
                    lineWidth: lineWidth,
                    isCompact: compact,
                )
            }
        }
        .frame(width: sectionWidth, alignment: .center)
    }

    private var availableWidth: CGFloat {
        max(48, sectionWidth - 8)
    }

    private var gaugeSize: CGFloat {
        if compact {
            return min(max(sectionWidth - 8, 30), 38)
        }
        return min(max(availableWidth, 64), 112)
    }

    private var lineWidth: CGFloat {
        compact ? 7 : 15
    }
}

private struct PeriodUnitRingGauge: View {
    let metric: PeriodRingMetric
    let size: CGFloat
    let lineWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        Group {
            if isCompact {
                VStack(spacing: standardGap * 1) {
                    compactCaption
                    ring
                }
            } else {
                ZStack {
                    ring
                    metricCaption
                        .frame(width: max(18, size - (lineWidth * 3.6)), height: max(18, size - (lineWidth * 3.6)))
                }
            }
        }
        .frame(width: isCompact ? compactCaptionWidth : size)
    }

    private var ring: some View {
        ZStack {
            segmentedRing(filledOnly: false)
            segmentedRing(filledOnly: true)
        }
        .frame(width: size, height: size)
    }

    private var metricCaption: some View {
        VStack(spacing: standardGap * 0.5) {
            metricSummary(fontSize: valueFontSize, weight: .bold)
            Text(metric.value)
                .font(.system(size: valueFontSize, weight: .medium, design: .monospaced))
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                .lineLimit(1)
                .minimumScaleFactor(0.45)
        }
        .frame(width: size)
    }

    private var compactCaption: some View {
        metricSummary(fontSize: compactCaptionFontSize, weight: .semibold)
    }

    private func metricSummary(fontSize: CGFloat, weight: Font.Weight) -> some View {
        HStack(spacing: standardGap * 1.5) {
            Text(metric.label)
            Text("•")
                .font(.system(size: max(fontSize * 0.42, 4), weight: .bold))
            Text(metric.percentageText)
        }
        .font(.system(size: fontSize, weight: weight, design: .monospaced))
        .foregroundStyle(workspaceSidebarWidgetContent(isCompact ? .secondary : .primary))
        .lineLimit(1)
        .minimumScaleFactor(isCompact ? 0.82 : 0.45)
        .frame(width: isCompact ? compactCaptionWidth : size)
    }

    private var valueFontSize: CGFloat {
        size < 58 ? 9 : 15
    }

    private var compactCaptionFontSize: CGFloat {
        11
    }

    private var compactCaptionWidth: CGFloat {
        size + 6
    }

    private func segmentedRing(filledOnly: Bool) -> some View {
        let totalUnits = max(metric.totalUnits, 1)
        let filledUnits = min(max(metric.filledUnits, 0), totalUnits)
        let gapFraction = segmentGapFraction(totalUnits: totalUnits)
        return ZStack {
            ForEach(0..<totalUnits, id: \.self) { index in
                if !filledOnly || index < filledUnits {
                    let start = (Double(index) / Double(totalUnits)) + (gapFraction / 2)
                    let end = (Double(index + 1) / Double(totalUnits)) - (gapFraction / 2)
                    Circle()
                        .trim(from: start, to: max(start, end))
                        .stroke(
                            periodRingSegmentColor(
                                index: index,
                                filled: filledUnits,
                                total: totalUnits,
                                filledOnly: filledOnly
                            ),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                        )
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .padding(lineWidth / 2)
    }

    private func segmentGapFraction(totalUnits: Int) -> Double {
        let circumference = Double.pi * Double(max(size - lineWidth, 1))
        let gapPoints = Double(max(2.5, lineWidth * 0.28))
        let maxGap = (1.0 / Double(max(totalUnits, 1))) * 0.25
        return min(gapPoints / circumference, maxGap)
    }
}

private struct PeriodRingMetric {
    let label: String
    let value: String
    let progress: Double
    let filledUnits: Int
    let totalUnits: Int

    var percentageText: String {
        "\(Int((min(max(progress, 0), 1) * 100).rounded()))%"
    }
}

private extension PeriodHeatmapSnapshot {
    func periodRingMetrics(compact _: Bool) -> [PeriodRingMetric] {
        [
            PeriodRingMetric(label: "W", value: "\(currentWeek)/\(totalWeeks)", progress: weekProgress, filledUnits: currentWeek, totalUnits: totalWeeks),
        ]
    }
}

private func periodRingSegmentColor(index: Int, filled: Int, total: Int, filledOnly: Bool) -> AnyShapeStyle {
    if !filledOnly {
        return AnyShapeStyle(workspaceSidebarWidgetComponentBackground(.normal))
    }
    let filledUnits = min(max(filled, 0), max(total, 1))
    guard index < filledUnits else {
        return AnyShapeStyle(WinMuxDesignTokens.transparent)
    }
    return AnyShapeStyle(periodProgressColor(filledUnits: filledUnits, totalUnits: total))
}

private func periodProgressColor(filledUnits: Int, totalUnits: Int) -> WorkspaceSidebarWidgetShapeStyle {
    let clamped = periodProgressColorStep(filledUnits: filledUnits, totalUnits: totalUnits)
    let step = min(1000, max(100, Int((100 + (clamped * 900)).rounded())))
    let geistStep = min(10, max(1, Int((Double(step) / 100).rounded()))) * 100
    return workspaceSidebarWidgetColor(GeistColorStep(rawValue: geistStep) ?? .color7)
}

func periodProgressColorStep(filledUnits: Int, totalUnits: Int) -> Double {
    let clampedTotal = max(totalUnits, 1)
    let clampedFilled = min(max(filledUnits, 0), clampedTotal)
    guard clampedFilled > 0 else { return 0 }
    return clampedTotal == 1 ? 1 : Double(clampedFilled - 1) / Double(clampedTotal - 1)
}
