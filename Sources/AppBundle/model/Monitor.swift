import AppKit
import Common
import CoreGraphics
import Foundation

private struct MonitorImpl {
    let monitorAppKitNsScreenScreensId: Int
    let name: String
    let rect: Rect
    let visibleRect: Rect
    let isMain: Bool
}

extension MonitorImpl: Monitor {
    var height: CGFloat { rect.height }
    var width: CGFloat { rect.width }
}

/// Use it instead of NSScreen because it can be mocked in tests
protocol Monitor: WinMuxAny {
    /// The index in NSScreen.screens array. 1-based index
    var monitorAppKitNsScreenScreensId: Int { get }
    var name: String { get }
    var rect: Rect { get }
    var visibleRect: Rect { get }
    var width: CGFloat { get }
    var height: CGFloat { get }
    var isMain: Bool { get }
}

final class InvalidatableSnapshotCache<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var storedValue: Value?

    func valueIfPresent() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func value(orCreate create: () -> Value) -> Value {
        while true {
            lock.lock()
            if let storedValue {
                lock.unlock()
                return storedValue
            }
            let expectedGeneration = generation
            lock.unlock()

            let candidate = create()

            lock.lock()
            // Never publish a capture that began before an invalidation.
            if generation == expectedGeneration {
                let result = storedValue ?? candidate
                storedValue = result
                lock.unlock()
                return result
            }
            if let storedValue {
                lock.unlock()
                return storedValue
            }
            lock.unlock()
        }
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        storedValue = nil
        lock.unlock()
    }
}

// Production snapshots contain only immutable MonitorImpl values.
private final class ScreenSnapshot: @unchecked Sendable {
    let mainMonitor: Monitor
    let mainMonitorHeight: CGFloat
    let monitors: [Monitor]

    init(mainMonitor: Monitor, mainMonitorHeight: CGFloat, monitors: [Monitor]) {
        self.mainMonitor = mainMonitor
        self.mainMonitorHeight = mainMonitorHeight
        self.monitors = monitors
    }
}

// Note to myself: Don't use NSScreen.main, it's garbage
// 1. The name is misleading, it's supposed to be called "focusedScreen"
// 2. It's inaccurate because NSScreen.main doesn't work correctly from NSWorkspace.didActivateApplicationNotification &
//    kAXFocusedWindowChangedNotification callbacks.
extension NSScreen {
    var displayId: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID(truncating: $0) }
    }

    fileprivate func toMonitor(monitorAppKitNsScreenScreensId: Int, mainMonitorHeight: CGFloat) -> MonitorImpl {
        MonitorImpl(
            monitorAppKitNsScreenScreensId: monitorAppKitNsScreenScreensId,
            name: localizedName,
            rect: frame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            visibleRect: visibleFrame.monitorFrameNormalized(mainMonitorHeight: mainMonitorHeight),
            isMain: isMainScreen,
        )
    }

    fileprivate var isMainScreen: Bool {
        displayId == CGMainDisplayID()
    }
}

private extension CGRect {
    func monitorFrameNormalized(mainMonitorHeight: CGFloat) -> Rect {
        Rect(
            topLeftX: minX,
            topLeftY: mainMonitorHeight - maxY,
            width: width,
            height: height,
        )
    }
}

private let testMonitorRect = Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080)
private let testMonitor = MonitorImpl(
    monitorAppKitNsScreenScreensId: 1,
    name: "Test Monitor",
    rect: testMonitorRect,
    visibleRect: testMonitorRect,
    isMain: true,
)
private let monitorSnapshotCache = InvalidatableSnapshotCache<ScreenSnapshot>()
private let monitorsOverrideForTestsLock = NSLock()
nonisolated(unsafe) private var monitorsOverrideForTests: [Monitor]? = nil

private func captureCurrentScreenSnapshot() -> ScreenSnapshot {
    precondition(Thread.isMainThread, "NSScreen geometry must be captured on the main thread")
    let screens = NSScreen.screens
    let indexedScreens = screens.withIndex
    guard let selectedMainScreen = indexedScreens.singleOrNil(where: \.value.isMainScreen) ?? indexedScreens.first else {
        return ScreenSnapshot(mainMonitor: testMonitor, mainMonitorHeight: testMonitor.height, monitors: [testMonitor])
    }

    let mainMonitorHeight = selectedMainScreen.value.frame.height
    let monitorValues = indexedScreens.map { index, screen in
        screen.toMonitor(
            monitorAppKitNsScreenScreensId: index + 1,
            mainMonitorHeight: mainMonitorHeight,
        )
    }
    let selectedMainMonitor = monitorValues[selectedMainScreen.index]
    let mainMonitor = selectedMainMonitor.isMain
        ? selectedMainMonitor
        : MonitorImpl(
            monitorAppKitNsScreenScreensId: selectedMainMonitor.monitorAppKitNsScreenScreensId,
            name: selectedMainMonitor.name,
            rect: selectedMainMonitor.rect,
            visibleRect: selectedMainMonitor.visibleRect,
            isMain: true,
        )
    return ScreenSnapshot(
        mainMonitor: mainMonitor,
        mainMonitorHeight: mainMonitorHeight,
        monitors: monitorValues.map { $0 },
    )
}

private func loadCurrentScreenSnapshotOnMainThread() -> ScreenSnapshot {
    if Thread.isMainThread {
        return monitorSnapshotCache.valueIfPresent() ?? captureCurrentScreenSnapshot()
    }
    return DispatchQueue.main.sync {
        monitorSnapshotCache.valueIfPresent() ?? captureCurrentScreenSnapshot()
    }
}

private var currentScreenSnapshot: ScreenSnapshot {
    monitorSnapshotCache.value(orCreate: loadCurrentScreenSnapshotOnMainThread)
}

func invalidateMonitorSnapshotCache() {
    monitorSnapshotCache.invalidate()
}

@MainActor
func refreshMonitorSnapshotCache() {
    invalidateMonitorSnapshotCache()
    guard !isUnitTest else { return }
    _ = currentScreenSnapshot
}

@MainActor
func setMonitorsForTests(_ monitors: [Monitor]?) {
    monitorsOverrideForTestsLock.lock()
    monitorsOverrideForTests = monitors
    monitorsOverrideForTestsLock.unlock()
}

private func currentMonitorsOverrideForTests() -> [Monitor]? {
    monitorsOverrideForTestsLock.lock()
    defer { monitorsOverrideForTestsLock.unlock() }
    return monitorsOverrideForTests
}

var mainMonitor: Monitor {
    if isUnitTest {
        let override = currentMonitorsOverrideForTests()
        return override?.first(where: \.isMain) ?? override?.first ?? testMonitor
    }
    return currentScreenSnapshot.mainMonitor
}

var mainMonitorHeight: CGFloat {
    if isUnitTest { return mainMonitor.height }
    return currentScreenSnapshot.mainMonitorHeight
}

var monitors: [Monitor] {
    if isUnitTest { return currentMonitorsOverrideForTests() ?? [testMonitor] }
    return currentScreenSnapshot.monitors
}

var sortedMonitors: [Monitor] {
    monitors.sorted {
        if $0.rect.minX != $1.rect.minX {
            return $0.rect.minX < $1.rect.minX
        }
        if $0.rect.minY != $1.rect.minY {
            return $0.rect.minY < $1.rect.minY
        }
        return $0.monitorAppKitNsScreenScreensId < $1.monitorAppKitNsScreenScreensId
    }
}
