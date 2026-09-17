import AppKit
import Charts
import Foundation
import SwiftUI

let menuBarWidgetIcon = WinMuxOverlayPalette.adaptiveColor(winMuxBarForegroundNSColor)
let menuBarWidgetText = WinMuxOverlayPalette.adaptiveColor(winMuxBarForegroundNSColor)
private let menuBarWidgetDataPath = defaultWorkspaceSidebarDataPath
let menuBarWidgetSpacing: CGFloat = WinMuxBarStyle.iconSpacing
let menuBarWidgetFontSize: CGFloat = 13
let menuBarWidgetFontWeight: Font.Weight = .regular
let menuBarWidgetIconSize = menuBarWidgetFontSize
let menuBarWidgetIconFrame = menuBarWidgetIconSize + standardGap * 0.5
private let menuBarWidgetGroupSpacing: CGFloat = WinMuxSpacing.comfortable
let menuBarContentTopInset: CGFloat = standardGap * 0.5
private let menuBarFloatingSurfaceVerticalInset: CGFloat = 0
let menuBarSurfaceHorizontalInset: CGFloat = standardGap
let menuBarFloatingSurfaceOutset: CGFloat = menuBarFloatingSurfaceVerticalInset * 2
let menuBarSurfaceCornerRadius: CGFloat = WinMuxBarStyle.cornerRadius
private let menuBarChartSize = CGSize(width: 360, height: 216)
private let menuBarBreakPotSize = CGSize(width: 320, height: 132)

enum MenuBarStatusChartKind: Hashable, CaseIterable {
    case breakPot
    case sleep
    case spending

    var panelSize: CGSize {
        switch self {
            case .breakPot: menuBarBreakPotSize
            case .sleep, .spending: menuBarChartSize
        }
    }
}

@MainActor
public final class MenuBarStatusWidgetsController {
    public static let shared = MenuBarStatusWidgetsController()

    private var panelsByScreenNumber: [NSNumber: MenuBarStatusWidgetPanel] = [:]
    private var notificationObservers: [NSObjectProtocol] = []
    private var eventMonitors: [Any] = []
    private var chartFrames: [MenuBarStatusChartKind: [NSNumber: NSRect]] = [:]
    fileprivate let chartPanel = MenuBarStatusChartPanel()

    public func install() {
        guard notificationObservers.isEmpty else { return }

        let center = NotificationCenter.default
        notificationObservers = [
            center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            center.addObserver(
                forName: NSWindow.didMoveNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object is MenuBarStatusWidgetPanel else { return }
                Task { @MainActor in self?.refresh() }
            },
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard notification.object is MenuBarStatusWidgetPanel else { return }
                Task { @MainActor in self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.screensDidWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            },
        ]
        eventMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                Task { @MainActor in self?.dismissChartForOutsideClick(at: NSEvent.mouseLocation) }
            } as Any,
            NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                if !(event.window is MenuBarStatusWidgetPanel) {
                    self?.dismissChartForOutsideClick(at: NSEvent.mouseLocation)
                }
                return event
            } as Any,
        ]
        refresh()
    }

    public func remove() {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        chartFrames.removeAll()
        chartPanel.closeChart()
        for panel in panelsByScreenNumber.values {
            panel.orderOut(nil)
            panel.close()
        }
        panelsByScreenNumber.removeAll()
    }

    func refreshIfInstalled() {
        guard !notificationObservers.isEmpty else { return }
        refresh()
    }

    fileprivate func registerChartFrame(_ frame: NSRect, kind: MenuBarStatusChartKind, screenNumber: NSNumber) {
        if kind == .sleep { chartFrames[.spending]?[screenNumber] = nil }
        if kind == .spending { chartFrames[.sleep]?[screenNumber] = nil }
        chartFrames[kind, default: [:]][screenNumber] = frame
    }

    fileprivate func activateChart(
        kind: MenuBarStatusChartKind,
        anchorFrame: NSRect,
        screenNumber: NSNumber
    ) {
        chartPanel.toggle(
            kind: kind,
            anchorFrame: anchorFrame,
            projectThemeFamily: panelsByScreenNumber[screenNumber]?.projectThemeFamily
        )
    }

    private func dismissChartForOutsideClick(at point: NSPoint) {
        if chartPanel.isVisible, chartPanel.frame.contains(point) { return }
        chartPanel.closeChart()
    }

    fileprivate func handleChartClick(at point: NSPoint) {
        for kind in MenuBarStatusChartKind.allCases {
            guard let match = chartFrames[kind]?.first(where: { $0.value.contains(point) }) else { continue }
            activateChart(
                kind: kind,
                anchorFrame: match.value,
                screenNumber: match.key
            )
            return
        }
        chartPanel.closeChart()
    }

    private func refresh() {
        var activeScreenNumbers = Set<NSNumber>()
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            activeScreenNumbers.insert(screenNumber)
            let panel = panelsByScreenNumber[screenNumber] ?? MenuBarStatusWidgetPanel()
            panelsByScreenNumber[screenNumber] = panel
            let panelFrame = menuBarFrame(for: screen)
            panel.show(
                in: panelFrame,
                projectThemeFamily: nil,
                cameraSafeEdges: menuBarCameraSafeEdges(for: screen, panelFrame: panelFrame)
            )
        }

        for screenNumber in panelsByScreenNumber.keys where !activeScreenNumbers.contains(screenNumber) {
            panelsByScreenNumber.removeValue(forKey: screenNumber)?.close()
            for kind in MenuBarStatusChartKind.allCases {
                chartFrames[kind]?.removeValue(forKey: screenNumber)
            }
        }
    }
}

private func menuBarCameraSafeEdges(for screen: NSScreen, panelFrame: NSRect) -> ClosedRange<CGFloat>? {
    guard let left = screen.auxiliaryTopLeftArea,
          let right = screen.auxiliaryTopRightArea,
          left.maxX < right.minX
    else { return nil }
    return (left.maxX - panelFrame.minX) ... (right.minX - panelFrame.minX)
}

private final class MenuBarStatusWidgetPanel: NSPanelHud {
    private let hostingView = NSHostingView(
        rootView: MenuBarStatusWidgetGroup(projectThemeFamily: nil, cameraSafeEdges: nil)
    )
    private(set) var projectThemeFamily: WorkspaceSidebarProjectThemeFamily?

    override init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("winmux.workspace-menu-bar")
        hasShadow = false
        ignoresMouseEvents = false
        isOpaque = false
        backgroundColor = WinMuxDesignTokens.transparentNSColor
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Keep the surface beneath the native menu bar and above workspace backgrounds.
        applyWinMuxLayer(.menuBarSurface)
        contentView = hostingView
        hostingView.autoresizingMask = [.width, .height]
        hostingView.setAccessibilityLabel("Widget bar")
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // Own the entire click sequence so the system status item underneath
        // cannot also open. Route once here, independently of SwiftUI hit testing.
        switch event.type {
            case .leftMouseDown:
                MenuBarStatusWidgetsController.shared.handleChartClick(
                    at: convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
                )
            case .leftMouseUp, .leftMouseDragged:
                break
            default:
                super.sendEvent(event)
        }
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    func show(
        in frame: NSRect,
        projectThemeFamily: WorkspaceSidebarProjectThemeFamily?,
        cameraSafeEdges: ClosedRange<CGFloat>?
    ) {
        if self.projectThemeFamily != projectThemeFamily || hostingView.rootView.cameraSafeEdges != cameraSafeEdges {
            self.projectThemeFamily = projectThemeFamily
            hostingView.rootView = MenuBarStatusWidgetGroup(
                projectThemeFamily: projectThemeFamily,
                cameraSafeEdges: cameraSafeEdges
            )
        }
        if self.frame != frame {
            setFrame(frame, display: true, animate: false)
        }
        orderFrontRegardless()
    }
}

@MainActor
private func menuBarFrame(for screen: NSScreen) -> NSRect {
    let barHeight = workspaceSidebarTopBarHeight(for: screen)
    let panelHeight = barHeight + menuBarFloatingSurfaceOutset
    let horizontalFrame = menuBarStatusWidgetRegion(for: screen, barHeight: barHeight)

    return NSRect(
        x: horizontalFrame.minX,
        y: screen.frame.maxY - panelHeight,
        width: horizontalFrame.width,
        height: panelHeight
    )
}

private struct MenuBarStatusWidgetGroup: View {
    @Environment(\.colorScheme) private var colorScheme
    let projectThemeFamily: WorkspaceSidebarProjectThemeFamily?
    let cameraSafeEdges: ClosedRange<CGFloat>?

    var body: some View {
        let palette = menuBarStatusWidgetPalette(
            colorScheme: colorScheme,
            projectThemeFamily: projectThemeFamily
        )
        GeometryReader { geometry in
            let surfaceHeight = max(1, geometry.size.height - menuBarContentTopInset)
            let widgetHeight = max(1, surfaceHeight - WinMuxBarStyle.topBarContentInset * 2)
            VStack(spacing: standardGap * 0) {
                TimelineView(.periodic(from: .now, by: menuBarProjectProgressRefreshInterval)) { context in
                    let projects = menuBarVisibleProjectProgress(
                        MenuBarProjectProgressLoader(
                            baseURL: URL(filePath: menuBarProjectsBasePath)
                        ).load(now: context.date)
                    )
                    MenuBarProjectLeadingWidgetLayout(
                        separation: menuBarWidgetGroupSpacing,
                        projectSeparation: standardGap * 0.75,
                        projectCount: projects.count,
                        cameraSafeEdges: cameraSafeEdges.map {
                            ($0.lowerBound - menuBarSurfaceHorizontalInset - WinMuxBarStyle.topBarContentInset)
                                ...
                            ($0.upperBound - menuBarSurfaceHorizontalInset - WinMuxBarStyle.topBarContentInset)
                        }
                    ) {
                        MenuBarPeriodCapsule(height: widgetHeight)

                        ForEach(projects) { project in
                            MenuBarProjectProgressCapsule(
                                project: project,
                                height: widgetHeight
                            )
                        }

                        MenuBarDailyFocusCapsule(height: widgetHeight)

                        MenuBarBreakPotWidget(height: widgetHeight)

                        MenuBarSleepSpendingCapsule(height: widgetHeight)
                    }
                }
                .frame(
                    width: max(
                        1,
                        geometry.size.width
                            - menuBarSurfaceHorizontalInset * 2
                            - WinMuxBarStyle.topBarContentInset * 2
                    ),
                    height: widgetHeight
                )
                .padding(WinMuxBarStyle.topBarContentInset)
                .padding(.horizontal, menuBarSurfaceHorizontalInset)
                .padding(.top, menuBarContentTopInset)

            Spacer(minLength: standardGap * 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .winMuxCustomGlassBarSurface(
            palette,
            cornerRadius: WinMuxSpacing.none,
            material: .underWindowBackground,
            blurOpacity: 0.50,
            strokeOpacity: WinMuxBarStyle.topBarStrokeOpacity
        )
        .environment(\.colorScheme, palette.colorScheme)
        .environment(\.workspaceSidebarProjectThemeFamily, projectThemeFamily)
    }
}

func menuBarStatusWidgetPalette(
    colorScheme: ColorScheme,
    projectThemeFamily: WorkspaceSidebarProjectThemeFamily?
) -> WinMuxOverlayPalette {
    WinMuxOverlayPalette(
        colorScheme: colorScheme,
        projectThemeFamily: projectThemeFamily
    )
}

struct MenuBarPeriodCapsule: View {
    let height: CGFloat

    init(height: CGFloat = 24) {
        self.height = height
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let period = MenuBarAcademicPeriod(now: context.date)

            HStack(spacing: menuBarWidgetSpacing) {
                Image(systemName: "calendar")
                    .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                    .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                    .foregroundStyle(menuBarWidgetIcon)
                Text(period.title)
                    .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                    .monospacedDigit()

            }
            .menuBarWidgetItem(height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(period.accessibilityLabel))
        }
    }
}

struct MenuBarDailyFocusCapsule: View {
    let height: CGFloat
    @StateObject private var loader = WorkspaceSidebarTodayFocusLoader()

    private var focusText: String {
        guard let snapshot = loader.snapshot, snapshot.errorMessage == nil else { return "—" }
        let minutes = max(0, Int(snapshot.focusedSeconds / 60))
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    var body: some View {
        HStack(spacing: menuBarWidgetSpacing) {
            Image(systemName: "timer")
                .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                .foregroundStyle(menuBarWidgetIcon)
            Text(focusText)
                .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                .monospacedDigit()
        }
        .menuBarWidgetItem(height: height)
        .help("Daily focus: \(focusText)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily focus, \(focusText)"))
        .task {
            await loader.refreshContinuously(
                dataSource: URL(filePath: menuBarWidgetDataPath, directoryHint: .isDirectory)
            )
        }
    }
}

struct MenuBarSleepCapsule: View {
    let height: CGFloat

    init(height: CGFloat = 24) {
        self.height = height
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let average = menuBarSleepAverage(now: context.date)
            HStack(spacing: menuBarWidgetSpacing) {
                Image(systemName: "bed.double.fill")
                    .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                    .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                    .foregroundStyle(menuBarWidgetIcon)
                Text(menuBarSleepText(average))
                    .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                    .monospacedDigit()
            }
            .menuBarWidgetItem(height: height, chartKind: .sleep)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Average sleep over the past 7 days: \(menuBarSleepText(average))"))
            .background(MenuBarChartHitRegion(kind: .sleep))
        }
    }
}

struct MenuBarSpendingCapsule: View {
    let height: CGFloat

    init(height: CGFloat = 24) {
        self.height = height
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let total = menuBarSpendingTotal(now: context.date)
            HStack(spacing: menuBarWidgetSpacing) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: menuBarWidgetIconSize, weight: menuBarWidgetFontWeight))
                    .frame(width: menuBarWidgetIconFrame, height: menuBarWidgetIconFrame)
                    .foregroundStyle(menuBarWidgetIcon)
                Text(menuBarCurrencyText(total))
                    .font(.system(size: menuBarWidgetFontSize, weight: menuBarWidgetFontWeight))
                    .monospacedDigit()
            }
            .menuBarWidgetItem(height: height, chartKind: .spending)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(menuBarCurrencyText(total)) spent in the last 30 days"))
            .background(MenuBarChartHitRegion(kind: .spending))
        }
    }
}

struct MenuBarChartHitRegion: NSViewRepresentable {
    let kind: MenuBarStatusChartKind

    func makeNSView(context: Context) -> MenuBarChartHitRegionView {
        MenuBarChartHitRegionView(kind: kind)
    }

    func updateNSView(_ nsView: MenuBarChartHitRegionView, context: Context) {
        nsView.kind = kind
        nsView.reportFrame()
    }
}

final class MenuBarChartHitRegionView: NSView {
    var kind: MenuBarStatusChartKind

    init(kind: MenuBarStatusChartKind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibilityLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        reportFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportFrame()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let frameDetails = frameDetails() else { return false }
        MenuBarStatusWidgetsController.shared.activateChart(
            kind: kind,
            anchorFrame: frameDetails.frame,
            screenNumber: frameDetails.screenNumber
        )
        return true
    }

    func reportFrame() {
        updateAccessibilityLabel()
        guard let frameDetails = frameDetails() else { return }
        Task { @MainActor in
            MenuBarStatusWidgetsController.shared.registerChartFrame(
                frameDetails.frame,
                kind: kind,
                screenNumber: frameDetails.screenNumber
            )
        }
    }

    private func frameDetails() -> (frame: NSRect, screenNumber: NSNumber)? {
        guard bounds.width > 0,
              bounds.height > 0,
              let window,
              let screenNumber = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else { return nil }
        return (window.convertToScreen(convert(bounds, to: nil)), screenNumber)
    }

    private func updateAccessibilityLabel() {
        switch kind {
            case .breakPot: setAccessibilityLabel("Show Break Pot options")
            case .sleep: setAccessibilityLabel("Show sleep chart")
            case .spending: setAccessibilityLabel("Show spending chart")
        }
    }
}

@MainActor
fileprivate final class MenuBarStatusChartPanel: NSPanelHud, ObservableObject {
    private let hostingView = NSHostingView(
        rootView: MenuBarStatusChartView(kind: .sleep, projectThemeFamily: nil)
    )
    @Published private(set) var presentedKind: MenuBarStatusChartKind?

    override init() {
        super.init()
        identifier = NSUserInterfaceItemIdentifier("winmux.workspace-menu-bar.chart")
        hasShadow = true
        level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func toggle(
        kind: MenuBarStatusChartKind,
        anchorFrame: NSRect,
        projectThemeFamily: WorkspaceSidebarProjectThemeFamily?
    ) {
        if isVisible, presentedKind == kind {
            closeChart()
            return
        }

        presentedKind = kind
        hostingView.rootView = MenuBarStatusChartView(
            kind: kind,
            projectThemeFamily: projectThemeFamily
        )

        let panelSize = kind.panelSize
        let visibleFrame = NSScreen.screens.first(where: { $0.frame.contains(anchorFrame.center) })?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        let x = min(
            max(anchorFrame.midX - panelSize.width / 2, visibleFrame.minX + workspaceSidebarStandardGap),
            visibleFrame.maxX - panelSize.width - workspaceSidebarStandardGap
        )
        let y = anchorFrame.minY - panelSize.height - workspaceSidebarStandardGap
        setFrame(
            NSRect(origin: NSPoint(x: x, y: y), size: panelSize),
            display: true,
            animate: false
        )
        orderFrontRegardless()
    }

    func closeChart() {
        presentedKind = nil
        orderOut(nil)
    }
}

private struct MenuBarStatusChartView: View {
    let kind: MenuBarStatusChartKind
    let projectThemeFamily: WorkspaceSidebarProjectThemeFamily?

    var body: some View {
        Group {
            switch kind {
                case .breakPot:
                    MenuBarBreakPotActionsView()
                case .sleep:
                    MenuBarSleepChart()
                case .spending:
                    MenuBarSpendingChart()
            }
        }
        .padding(standardGap * 7)
        .frame(width: kind.panelSize.width, height: kind.panelSize.height)
        .background {
            WorkspaceSidebarStatusCardBackground()
        }
        .environment(\.workspaceSidebarProjectThemeFamily, projectThemeFamily)
    }
}

private struct MenuBarSleepChart: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let days = menuBarSleepDays(now: context.date)
            let values = days.map(\.hours).filter { $0 > 0 }
            let lowerBound = max(0, (values.min() ?? 1) - 1)
            let upperBound = max(lowerBound + 2, (values.max() ?? 11) + 1)

            VStack(alignment: .leading, spacing: standardGap * 4) {
                MenuBarChartHeader(
                    title: "Sleep",
                    value: menuBarSleepText(menuBarSleepAverage(now: context.date))
                )

                Chart(days) { day in
                    if day.hours > 0 {
                        LineMark(
                            x: .value("Day", day.date),
                            y: .value("Hours", day.hours)
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(workspaceSidebarWidgetColor(.color7))

                        PointMark(
                            x: .value("Day", day.date),
                            y: .value("Hours", day.hours)
                        )
                        .symbolSize(24)
                        .foregroundStyle(workspaceSidebarWidgetColor(.color7))
                        .annotation(position: .top, spacing: standardGap * 2.5) {
                            Text(String(format: "%.1fh", day.hours))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                        }
                    }
                }
                .chartYScale(domain: lowerBound ... upperBound)
                .chartXAxis {
                    AxisMarks(values: days.map(\.date)) { value in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                            .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                            .foregroundStyle(workspaceSidebarWidgetBorder(.normal))
                    }
                }
            }
        }
    }
}

private struct MenuBarSpendingChart: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 300)) { context in
            let snapshot = SpendingCategoryAggregator(
                entriesDirectory: URL(filePath: menuBarWidgetDataPath, directoryHint: .isDirectory),
                days: 28
            ).load(now: context.date)
            let weeks = Array(snapshot.weeks.reversed())

            VStack(alignment: .leading, spacing: standardGap * 4) {
                MenuBarChartHeader(
                    title: "Spending",
                    value: menuBarCurrencyText(snapshot.totalAmount)
                )

                Chart(weeks) { week in
                    BarMark(
                        x: .value("Week", menuBarSpendingWeekText(week.startDate)),
                        y: .value("Spent", max(0, week.amount)),
                        width: .fixed(32)
                    )
                    .cornerRadius(5)
                    .foregroundStyle(workspaceSidebarWidgetColor(.color7))
                    .annotation(position: .top, spacing: standardGap * 2.5) {
                        Text(menuBarCompactCurrencyText(week.amount))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(workspaceSidebarWidgetContent(.primary))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: weeks.map { menuBarSpendingWeekText($0.startDate) }) { _ in
                        AxisValueLabel()
                            .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine()
                            .foregroundStyle(workspaceSidebarWidgetBorder(.normal))
                    }
                }
            }
        }
    }
}

private struct MenuBarChartHeader: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: standardGap * 4) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(workspaceSidebarWidgetContent(.secondary))
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(workspaceSidebarWidgetContent(.primary))
        }
    }
}

private struct MenuBarSleepDay: Identifiable {
    let date: Date
    let hours: Double

    var id: Date { date }
}

extension View {
    func menuBarWidgetItem(height: CGFloat, chartKind: MenuBarStatusChartKind? = nil) -> some View {
        modifier(MenuBarWidgetItemModifier(height: height, chartKind: chartKind))
    }
}

private struct MenuBarWidgetItemModifier: ViewModifier {
    let height: CGFloat
    let chartKind: MenuBarStatusChartKind?
    @ObservedObject private var chartPanel = MenuBarStatusWidgetsController.shared.chartPanel
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    func body(content: Content) -> some View {
        let palette = WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
        let isSelected = chartKind != nil && chartPanel.presentedKind == chartKind
        return content
            .foregroundStyle(menuBarWidgetText)
            .padding(.horizontal, WinMuxBarStyle.contentInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .winMuxBarSegment(palette, isSelected: isSelected, isHovered: isHovered)
            .clipShape(RoundedRectangle(cornerRadius: WinMuxBarStyle.topBarCornerRadius, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: WinMuxBarStyle.topBarCornerRadius, style: .continuous)
                        .strokeBorder(winMuxBarSurfaceStroke(palette), lineWidth: WinMuxBarStyle.strokeWidth)
                        .allowsHitTesting(false)
                }
            }
            .onHover { isHovered = $0 }
    }
}

private func menuBarSpendingTotal(now: Date) -> Double {
    guard let sqliteURL = SidebarSelfDataStore.sqliteURL(for: URL(filePath: menuBarWidgetDataPath, directoryHint: .isDirectory)),
          let transactions = SidebarSelfDataStore.loadSpendingTransactions(from: sqliteURL)
    else { return 0 }

    let start = now.addingTimeInterval(-30 * 24 * 60 * 60)
    return transactions
        .filter { $0.created >= start && $0.created <= now }
        .reduce(0) { $0 + $1.amount }
}

private func menuBarSleepAverage(now: Date) -> TimeInterval? {
    guard let sqliteURL = SidebarSelfDataStore.sqliteURL(for: URL(filePath: menuBarWidgetDataPath, directoryHint: .isDirectory)),
          let nights = SidebarSelfDataStore.loadSleepNights(from: sqliteURL)
    else { return nil }

    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    guard let start = calendar.date(byAdding: .day, value: -6, to: today) else { return nil }

    var latestByDate: [Date: TimeInterval] = [:]
    for night in nights where night.localDate >= start && night.localDate <= today {
        latestByDate[night.localDate] = max(latestByDate[night.localDate] ?? 0, night.sleepSeconds)
    }
    guard !latestByDate.isEmpty else { return nil }
    return latestByDate.values.reduce(0, +) / Double(latestByDate.count)
}

private func menuBarSleepDays(now: Date) -> [MenuBarSleepDay] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    guard let start = calendar.date(byAdding: .day, value: -6, to: today),
          let sqliteURL = SidebarSelfDataStore.sqliteURL(
              for: URL(filePath: menuBarWidgetDataPath, directoryHint: .isDirectory)
          ),
          let nights = SidebarSelfDataStore.loadSleepNights(from: sqliteURL)
    else { return [] }

    var latestByDate: [Date: TimeInterval] = [:]
    for night in nights where night.localDate >= start && night.localDate <= today {
        latestByDate[night.localDate] = max(latestByDate[night.localDate] ?? 0, night.sleepSeconds)
    }

    return (0 ..< 7).compactMap { offset in
        guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
        return MenuBarSleepDay(
            date: date,
            hours: (latestByDate[date] ?? 0) / 3600
        )
    }
}

private func menuBarSleepText(_ seconds: TimeInterval?) -> String {
    guard let seconds else { return "--" }
    let minutes = max(0, Int((seconds / 60).rounded()))
    return "\(minutes / 60)h \(minutes % 60)m"
}

private func menuBarCurrencyText(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "GBP"
    formatter.currencySymbol = "\u{00A3}"
    formatter.locale = Locale(identifier: "en_GB")
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: amount)) ?? "\u{00A3}\(Int(amount.rounded()))"
}

private func menuBarCompactCurrencyText(_ amount: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "GBP"
    formatter.currencySymbol = "\u{00A3}"
    formatter.locale = Locale(identifier: "en_GB")
    formatter.maximumFractionDigits = 0
    if abs(amount) >= 1000 {
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        return "\u{00A3}\(formatter.string(from: NSNumber(value: amount / 1000)) ?? "0")k"
    }
    return formatter.string(from: NSNumber(value: amount)) ?? "\u{00A3}\(Int(amount.rounded()))"
}

private func menuBarSpendingWeekText(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated))
}

private extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}
