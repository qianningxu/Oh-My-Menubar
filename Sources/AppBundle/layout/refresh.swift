import AppKit
import Common

@MainActor private(set) var isRestoringStartupLayout = false
@MainActor private var refreshDeferredDuringStartup = false

@MainActor
func beginStartupLayoutRestoration() {
    isRestoringStartupLayout = true
}

@MainActor
func finishStartupLayoutRestoration() {
    isRestoringStartupLayout = false
    WorkspaceSidebarPanel.refreshAll()
    if refreshDeferredDuringStartup {
        refreshDeferredDuringStartup = false
        scheduleRefreshSession(.windowInventoryReconciliation)
    }
}

@MainActor
private var activeRefreshTask: Task<(), any Error>? = nil

@MainActor
private var activeRefreshSessionDepth = 0

@MainActor
private var activeScheduledRefreshEvent: RefreshSessionEvent? = nil

@MainActor
private var activeScheduledRefreshGeneration: UInt64 = 0

@MainActor
private var scheduledRefreshOverrideForTests: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)? = nil

@MainActor
private var refreshOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil

@MainActor
private var normalizeLayoutReasonOverrideForTests: (@MainActor @Sendable () async throws -> Void)? = nil

@MainActor
func refreshSessionsAreIdle() -> Bool {
    activeRefreshTask == nil && activeRefreshSessionDepth == 0
}

@MainActor
private func beginRefreshSessionActivity() {
    activeRefreshSessionDepth += 1
}

@MainActor
private func endRefreshSessionActivity() {
    precondition(activeRefreshSessionDepth > 0)
    activeRefreshSessionDepth -= 1
    if refreshSessionsAreIdle() {
        GlobalObserver.refreshSessionsDidBecomeIdle()
    }
}

private func isAxGeometryRefreshEvent(_ event: RefreshSessionEvent) -> Bool {
    guard case .ax(let notif) = event else { return false }
    return notif == kAXMovedNotification as String || notif == kAXResizedNotification as String
}

func shouldNoteWindowInventoryActivity(forAxNotification notification: String) -> Bool {
    notification == kAXWindowCreatedNotification as String ||
        notification == kAXUIElementDestroyedNotification as String ||
        notification == kAXFocusedWindowChangedNotification as String
}

private func shouldDropScheduledRefresh(_ newEvent: RefreshSessionEvent, activeEvent: RefreshSessionEvent?) -> Bool {
    if case .workspaceSidebarWidthChanged = newEvent,
       let activeEvent,
       !activeEvent.isWorkspaceSidebarWidthChange
    {
        return true
    }
    guard isAxGeometryRefreshEvent(newEvent), let activeEvent else { return false }
    if isAxGeometryRefreshEvent(activeEvent) {
        return true
    }
    if case .resetManipulatedWithMouse = activeEvent {
        return true
    }
    return false
}

@MainActor
func shouldSyncFocusBackToMacOs(
    nativeFocused: Window?,
    frontmostActivationPolicy: NSApplication.ActivationPolicy?,
) -> Bool {
    if nativeFocused?.participatesInWorkspaceFocus == false {
        return false
    }
    // A newly activated regular app can have no AX focused window while
    // its first window is being created. Do not reactivate the previous app
    // during that gap (System Settings is a common example).
    if nativeFocused == nil && frontmostActivationPolicy != nil {
        return false
    }
    return true
}

@MainActor
func scheduleRefreshSession(
    _ event: RefreshSessionEvent,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    if isRestoringStartupLayout {
        refreshDeferredDuringStartup = true
        return
    }
    if shouldDropScheduledRefresh(event, activeEvent: activeScheduledRefreshEvent) {
        debugFocusLog("scheduleRefreshSession dropped event=\(event) active=\(activeScheduledRefreshEvent?.description ?? "nil")")
        return
    }
    activeRefreshTask?.cancel()
    activeScheduledRefreshGeneration += 1
    let generation = activeScheduledRefreshGeneration
    activeScheduledRefreshEvent = event
    let override = scheduledRefreshOverrideForTests
    activeRefreshTask = Task { @MainActor in
        beginRefreshSessionActivity()
        defer {
            if activeScheduledRefreshGeneration == generation {
                activeRefreshTask = nil
                activeScheduledRefreshEvent = nil
            }
            endRefreshSessionActivity()
        }
        do {
            try checkCancellation()
            if let override {
                try await override(event, optimisticallyPreLayoutWorkspaces)
            } else {
                try await runRefreshSessionBlocking(event, optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces)
            }
        } catch is CancellationError {
            return
        }
    }
}

@MainActor
@discardableResult
func scheduleWindowInventoryReconciliationIfIdle() -> Bool {
    guard refreshSessionsAreIdle() else { return false }
    scheduleRefreshSession(.windowInventoryReconciliation)
    return true
}

@MainActor
func runRefreshSessionBlocking(
    _ event: RefreshSessionEvent,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async throws {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    if !TrayMenuModel.shared.isEnabled { return }
    if case .workspaceSidebarWidthChanged = event {
        beginRefreshSessionActivity()
        defer { endRefreshSessionActivity() }
        if shouldLayoutWorkspaces {
            try await $refreshSessionEvent.withValue(event) {
                for monitor in monitors {
                    try checkCancellation()
                    try await monitor.activeWorkspace.layoutWorkspace()
                }
            }
        }
        // Sidebar expansion changes the active window rects without taking the
        // normal refresh path. Rebuild the tab chrome from those new rects so
        // its frame cannot retain the pre-sidebar geometry.
        await updateWindowTabModel()
        return
    }
    beginRefreshSessionActivity()
    defer { endRefreshSessionActivity() }
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    debugFocusLog("runRefreshSessionBlocking begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let frontmostActivationPolicy = NSWorkspace.shared.frontmostApplication?.activationPolicy
                let nativeFocused = try await getNativeFocusedWindow()
                try checkCancellation()
                if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
                await updateNativeFullscreenChromeSuppression(nativeFocused: nativeFocused)
                updateFocusCache(nativeFocused)
                try checkCancellation()

                if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }
                try checkCancellation()

                refreshModel()
                let targetedWindowCreationApp = event.axWindowCreatedSourcePid
                    .flatMap { MacApp.allAppsMap[$0] }
                if let targetedWindowCreationApp {
                    let refreshedWindows = try await refresh(windowCreatedBy: targetedWindowCreationApp)
                    try checkCancellation()
                    try await normalizeLayoutReason(for: refreshedWindows)
                    try checkCancellation()
                    // The new window is in the tree now. Layout before the
                    // sidebar/model update so its first resize does not wait
                    // for unrelated UI bookkeeping.
                    refreshModel()
                    if shouldLayoutWorkspaces {
                        try await layoutWorkspaces()
                        try checkCancellation()
                    }
                } else if event.requiresWindowRefreshBarrier {
                    if let refreshOverrideForTests {
                        try await refreshOverrideForTests()
                    } else {
                        try await refresh()
                    }
                    try checkCancellation()
                    gcMonitors()
                }

                if event.requiresLayoutReasonNormalization, targetedWindowCreationApp == nil {
                    if let normalizeLayoutReasonOverrideForTests {
                        try await normalizeLayoutReasonOverrideForTests()
                    } else {
                        try await normalizeLayoutReason()
                    }
                    try checkCancellation()
                    refreshModel()
                }
                updateTrayText()
                await updateWorkspaceSidebarModel()
                SecureInputPanel.shared.refresh()
                if shouldLayoutWorkspaces {
                    if targetedWindowCreationApp == nil {
                        try await layoutWorkspaces()
                        try checkCancellation()
                    }
                    if shouldSyncFocusBackToMacOs(
                        nativeFocused: nativeFocused,
                        frontmostActivationPolicy: frontmostActivationPolicy,
                    ) {
                        let logicalFocused = focus.windowOrNil
                        if logicalFocused?.windowId != nativeFocused?.windowId {
                            debugFocusLog(
                                "runRefreshSessionBlocking syncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                            logicalFocused?.nativeFocus()
                        } else {
                            debugFocusLog(
                                "runRefreshSessionBlocking skipSyncFocus event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") logicalFocused=\(logicalFocused?.windowId.description ?? "nil")"
                            )
                        }
                    }
                }
                // New dialogs must be raised after logical focus is synced back
                // to macOS. Otherwise focusing the previous window here can put
                // it back above a settings/dialog window detected by refresh().
                raiseNewlyDetectedDialogsAfterFocusSync()
                await updateWindowTabModel()
                debugFocusLog("runRefreshSessionBlocking end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focus=\(debugDescribe(focus))")
            }
        }
    }
}

@MainActor
func runLightSession<T>(
    _ event: RefreshSessionEvent,
    _: RunSessionGuard,
    shouldSchedulePostRefresh: Bool = true,
    prioritizeFocusSync: Bool = false,
    body: @MainActor () async throws -> T,
) async throws -> T {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    beginRefreshSessionActivity()
    defer { endRefreshSessionActivity() }
    let focusSnapshot = captureRefreshSessionFocusSnapshot()
    debugFocusLog("runLightSession begin event=\(event) snapshot=\(debugDescribe(focusSnapshot))")
    return try await $refreshSessionEvent.withValue(event) {
        try await $_isStartup.withValue(event.isStartup) {
            try await $_refreshSessionFocusSnapshot.withValue(focusSnapshot) {
                let nativeFocused = try await getNativeFocusedWindow()
                try checkCancellation()
                if let nativeFocused { try await debugWindowsIfRecording(nativeFocused) }
                await updateNativeFullscreenChromeSuppression(nativeFocused: nativeFocused)
                updateFocusCache(nativeFocused)
                try checkCancellation()
                let focusBefore = focus.windowOrNil

                refreshModel()
                do {
                    let result = try await body()
                    try checkCancellation()
                    refreshModel()

                    let focusAfter = focus.windowOrNil

                    updateTrayText()
                    SecureInputPanel.shared.refresh()
                    if prioritizeFocusSync {
                        try await layoutWorkspaces()
                        try checkCancellation()
                        if focusBefore != focusAfter {
                            focusAfter?.nativeFocus()
                        }
                        await updateWorkspaceSidebarModel()
                        await updateWindowTabModel()
                    } else {
                        await updateWorkspaceSidebarModel()
                        try await layoutWorkspaces()
                        try checkCancellation()
                        await updateWindowTabModel()
                        if focusBefore != focusAfter {
                            focusAfter?.nativeFocus() // syncFocusToMacOs
                        }
                    }
                    if shouldSchedulePostRefresh {
                        scheduleRefreshSession(event)
                    }
                    debugFocusLog("runLightSession end event=\(event) nativeFocused=\(nativeFocused?.windowId.description ?? "nil") focusBefore=\(focusBefore?.windowId.description ?? "nil") focusAfter=\(focusAfter?.windowId.description ?? "nil") logicalFocus=\(debugDescribe(focus))")
                    return result
                } catch {
                    if shouldSchedulePostRefresh {
                        scheduleRefreshSession(event)
                    }
                    throw error
                }
            }
        }
    }
}

@MainActor
func setScheduledRefreshOverrideForTests(
    _ override: (@MainActor @Sendable (RefreshSessionEvent, Bool) async throws -> Void)?
) {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    activeScheduledRefreshEvent = nil
    scheduledRefreshOverrideForTests = override
}

@MainActor
func setBlockingRefreshOverridesForTests(
    refresh: (@MainActor @Sendable () async throws -> Void)? = nil,
    normalizeLayoutReason: (@MainActor @Sendable () async throws -> Void)? = nil,
) {
    activeRefreshTask?.cancel()
    activeRefreshTask = nil
    activeScheduledRefreshEvent = nil
    refreshOverrideForTests = refresh
    normalizeLayoutReasonOverrideForTests = normalizeLayoutReason
}

@MainActor
func waitForScheduledRefreshForTests() async throws {
    defer { activeRefreshTask = nil }
    try await activeRefreshTask?.value
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    @MainActor
    static func checkServerIsEnabledOrDie(
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> RunSessionGuard {
        .isServerEnabled ?? dieT("server is disabled", file: file, line: line, column: column, function: function)
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel() {
    detachWorkspaceFloatingWindows()
    Workspace.reconcileWorkspaceState()
    checkOnFocusChangedCallbacks()
    normalizeContainers()
}

@MainActor
private func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    try await reconcileRefreshedWindows(mapping, isFullInventory: true)
}

@MainActor
private func refresh(windowCreatedBy app: MacApp) async throws -> [Window] {
    let windowIds = try await app.refreshAndGetAliveWindowIdsForWindowCreation(
        frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    )
    try await reconcileRefreshedWindows([app: windowIds], isFullInventory: false)
    return windowIds.compactMap { MacWindow.allWindowsMap[$0] }
}

@MainActor
private func reconcileRefreshedWindows(
    _ mapping: [MacApp: [UInt32]],
    isFullInventory: Bool
) async throws {
    let refreshedApps = Set(mapping.keys.map(ObjectIdentifier.init))
    let aliveWindowIds = mapping.values.flatMap { $0 }.toSet()

    for window in MacWindow.allWindows {
        guard shouldReconcileWindowInventory(
            isFullInventory: isFullInventory,
            appWasRefreshed: refreshedApps.contains(ObjectIdentifier(window.macApp))
        ) else { continue }
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
        }
    }
    // A targeted creation refresh has no inventory data for other apps.
    // Only a complete scan can reconcile persisted windows globally.
    if isFullInventory {
        finalizePersistedFrozenWorldAfterRefresh(aliveWindowIds: aliveWindowIds)
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    detachWorkspaceFloatingWindows()
    Workspace.reconcileWorkspaceState()
}

func refreshObs(_: AXObserver, element: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    let sourcePid = notif == kAXWindowCreatedNotification as String ? axProcessId(element) : nil
    if notif == kAXFocusedWindowChangedNotification as String || notif == kAXUIElementDestroyedNotification as String {
        debugFocusLog("refreshObs notif=\(notif)")
    }
    Task { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        if shouldNoteWindowInventoryActivity(forAxNotification: notif) {
            GlobalObserver.noteWindowInventoryActivity()
        }
        if let sourcePid {
            scheduleRefreshSession(.axWindowCreated(pid: sourcePid))
        } else {
            scheduleRefreshSession(.ax(notif))
        }
    }
}

private func axProcessId(_ element: AXUIElement) -> pid_t? {
    var pid: pid_t = 0
    return AXUIElementGetPid(element, &pid) == .success ? pid : nil
}

enum OptimalHideCorner {
    case bottomLeftCorner, bottomRightCorner
}

@MainActor
private func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.forEach { window in
                guard let macWindow = window as? MacWindow else { return }
                if shouldKeepWindowHiddenForVisibleWorkspaceLayout(window) {
                    return
                }
                macWindow.unhideFromCorner()
            }
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitors
    var monitorToOptimalHideCorner: [CGPoint: OptimalHideCorner] = [:]
    for monitor in monitors {
        let xOff = monitor.width * 0.1
        let yOff = monitor.height * 0.1
        // brc = bottomRightCorner
        let brc1 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: -yOff)
        let brc2 = monitor.rect.bottomRightCorner + CGPoint(x: -xOff, y: 2)
        let brc3 = monitor.rect.bottomRightCorner + CGPoint(x: 2, y: 2)

        // blc = bottomLeftCorner
        let blc1 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: -yOff)
        let blc2 = monitor.rect.bottomLeftCorner + CGPoint(x: xOff, y: 2)
        let blc3 = monitor.rect.bottomLeftCorner + CGPoint(x: -2, y: 2)

        func contains(_ monitor: Monitor, _ point: CGPoint) -> Int { monitor.rect.contains(point) ? 1 : 0 }
        let important = 10

        let corner: OptimalHideCorner =
            monitors.sumOfInt { contains($0, blc1) + contains($0, blc2) + important * contains($0, blc3) } <
            monitors.sumOfInt { contains($0, brc1) + contains($0, brc2) + important * contains($0, brc3) }
            ? .bottomLeftCorner
            : .bottomRightCorner
        monitorToOptimalHideCorner[monitor.rect.topLeftCorner] = corner
    }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.forEach { window in
            guard let macWindow = window as? MacWindow else { return }
            if shouldKeepWindowHiddenForVisibleWorkspaceLayout(window) {
                return
            }
            macWindow.unhideFromCorner()
        }
        try await workspace.layoutWorkspace()
    }
    for workspace in Workspace.all where !workspace.isVisible {
        let corner = monitorToOptimalHideCorner[workspace.workspaceMonitor.rect.topLeftCorner] ?? .bottomRightCorner
        let shouldReassertHiddenWindows = refreshSessionEvent?.canReuseLastAppliedWindowFrames != true
        for window in workspace.allLeafWindowsRecursive {
            try checkCancellation()
            guard !workspace.isVisible else { break }
            guard let macWindow = window as? MacWindow else { continue }
            macWindow.lastAppliedLayoutPhysicalRect = nil
            macWindow.lastAppliedLayoutVirtualRect = nil
            if !macWindow.isHiddenInCorner {
                refreshExposeThumbnailCache(macWindow.windowId)
            }
            try await macWindow.hideInCorner(corner, force: shouldReassertHiddenWindows)
        }
    }
}

@MainActor
private func shouldKeepWindowHiddenForVisibleWorkspaceLayout(_ window: Window) -> Bool {
    guard let tabGroup = window.nearestWindowTabGroup, tabGroup.usesWindowTabBehavior else { return false }
    return tabGroup.tabActiveWindow != window
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}

func shouldReconcileWindowInventory(isFullInventory: Bool, appWasRefreshed: Bool) -> Bool {
    isFullInventory || appWasRefreshed
}
