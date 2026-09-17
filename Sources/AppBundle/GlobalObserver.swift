import AppKit
import Common
import HotKey

private struct PointerActivityBatch: @unchecked Sendable {
    let latestSample: MousePointerSample
    let leftMouseDownSample: MousePointerSample?
    let hasGlobalLeftMouseDrag: Bool
}

private final class PointerActivityCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private var latestSample: MousePointerSample?
    private var leftMouseDownSample: MousePointerSample?
    private var hasGlobalLeftMouseDrag = false
    private var isConsumerScheduled = false

    func submit(
        sample: MousePointerSample,
        isLeftMouseDown: Bool,
        isGlobalLeftMouseDrag: Bool
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        latestSample = sample
        if isLeftMouseDown {
            leftMouseDownSample = sample
        }
        hasGlobalLeftMouseDrag = hasGlobalLeftMouseDrag || isGlobalLeftMouseDrag
        guard !isConsumerScheduled else { return false }
        isConsumerScheduled = true
        return true
    }

    func nextBatchOrFinish() -> PointerActivityBatch? {
        lock.lock()
        defer { lock.unlock() }
        guard let latestSample else {
            isConsumerScheduled = false
            return nil
        }
        let batch = PointerActivityBatch(
            latestSample: latestSample,
            leftMouseDownSample: leftMouseDownSample,
            hasGlobalLeftMouseDrag: hasGlobalLeftMouseDrag
        )
        self.latestSample = nil
        leftMouseDownSample = nil
        hasGlobalLeftMouseDrag = false
        return batch
    }

    func discardPending() {
        lock.lock()
        defer { lock.unlock() }
        latestSample = nil
        leftMouseDownSample = nil
        hasGlobalLeftMouseDrag = false
    }
}

enum GlobalObserver {
    @MainActor private static var isInitialized = false
    @MainActor private static var notificationObserverTokens: [NSObjectProtocol] = []
    @MainActor private static var eventMonitorTokens: [Any] = []
    @MainActor private static var windowInventoryPollController: WindowInventoryPollController?
    @MainActor private static var didCompleteStartupRefresh = false
    @MainActor private static var isWindowInventoryPollingRequested = false
    @MainActor private static var isWindowInventoryPollingStarted = false
    @MainActor private static var isWindowInventoryPollingSuspendedForSleep = false
    @MainActor private static var resizeCandidateCaptureGeneration: UInt64 = 0
    @MainActor private static var isOptionRevealPressed = false
    @MainActor private static var optionRevealGeneration: UInt64 = 0
    private static let pointerActivityCoalescer = PointerActivityCoalescer()

    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        let notifName = notification.name.rawValue
        Task { @MainActor in
            if notifName == NSWorkspace.didWakeNotification.rawValue ||
                notifName == NSWorkspace.screensDidWakeNotification.rawValue
            {
                isWindowInventoryPollingSuspendedForSleep = false
            } else {
                windowInventoryPollController?.noteActivity()
            }
            if !TrayMenuModel.shared.isEnabled { return }
            if notifName == NSWorkspace.didActivateApplicationNotification.rawValue {
                scheduleRefreshSession(.globalObserver(notifName), optimisticallyPreLayoutWorkspaces: true)
            } else {
                scheduleRefreshSession(.globalObserver(notifName))
            }
            startWindowInventoryPollingIfReady()
        }
    }

    private static func onHideApp(_ notification: Notification) {
        let notifName = notification.name.rawValue
        Task { @MainActor in
            windowInventoryPollController?.noteActivity()
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver(notifName), token) {
                if config.automaticallyUnhideMacosHiddenApps {
                    if let w = prevFocus?.windowOrNil,
                       w.macAppUnsafe.nsApp.isHidden,
                       // "Hide others" (cmd-alt-h) -> don't force focus
                       // "Hide app" (cmd-h) -> force focus
                       MacApp.allAppsMap.values.count(where: { $0.nsApp.isHidden }) == 1
                    {
                        // Force focus
                        _ = w.focusWindow()
                        w.nativeFocus()
                    }
                    for app in MacApp.allAppsMap.values {
                        app.nsApp.unhide()
                    }
                }
            }
        }
    }

    private static func onKeyDown(_ event: NSEvent) {
        let modifierFlags = event.modifierFlags
        let keyCode = event.keyCode
        Task { @MainActor in
            noteTapBindingKeyDown()
            if modifierFlags.contains(.control), keyCode == 34 { // 'i' key
                ExposePanel.shared.toggle()
            }
        }
    }

    private static func onFlagsChanged(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        Task { @MainActor in
            noteTapBindingFlagsChanged(keyCode: keyCode, modifierFlags: modifierFlags)
            updateOptionKeyWorkspaceBarReveal(isPressed: modifierFlags.contains(.option))
        }
    }

    @MainActor
    private static func updateOptionKeyWorkspaceBarReveal(isPressed: Bool) {
        guard isOptionRevealPressed != isPressed else { return }
        isOptionRevealPressed = isPressed
        optionRevealGeneration &+= 1
        let generation = optionRevealGeneration
        if isPressed {
            DispatchQueue.main.asyncAfter(deadline: .now() + workspaceSidebarOptionKeyRevealDelay) {
                guard isOptionRevealPressed, optionRevealGeneration == generation else { return }
                revealWorkspaceSidebarFromOptionKey()
            }
        } else {
            releaseWorkspaceSidebarOptionKeyReveal()
        }
    }

    private static func onPointerActivity(_ event: NSEvent, handlesGlobalWindowDrag: Bool) {
        let isLeftMouseDownEvent = event.type == .leftMouseDown
        let sample = MousePointerSample(
            point: normalizeAppKitScreenPoint(NSEvent.mouseLocation),
            timestamp: event.timestamp
        )
        let shouldScheduleConsumer = pointerActivityCoalescer.submit(
            sample: sample,
            isLeftMouseDown: isLeftMouseDownEvent,
            isGlobalLeftMouseDrag: handlesGlobalWindowDrag && event.type == .leftMouseDragged
        )
        guard shouldScheduleConsumer else { return }
        Task { @MainActor in
            while let batch = pointerActivityCoalescer.nextBatchOrFinish() {
                if let downSample = batch.leftMouseDownSample {
                    WindowMouseInteractionOpacityController.shared.prepareWindowInventory()
                    processPointerSample(downSample)
                    schedulePendingResizeCandidateCapture(for: downSample)
                }
                if batch.latestSample != batch.leftMouseDownSample {
                    processPointerSample(batch.latestSample)
                }
                if batch.hasGlobalLeftMouseDrag {
                    refreshPendingWindowDragIntentFromGlobalMouseDrag()
                }
                noteTapBindingKeyDown()
            }
        }
    }

    @MainActor
    private static func processPointerSample(_ sample: MousePointerSample) {
        MousePointerTracker.shared.note(point: sample.point, timestamp: sample.timestamp)
        WorkspaceSidebarPanel.trapCursorForVisiblePanelsIfNeeded()
        WorkspaceSidebarPanel.updateHoverStateForVisiblePanels()
    }

    @MainActor
    private static func schedulePendingResizeCandidateCapture(for sample: MousePointerSample) {
        resizeCandidateCaptureGeneration &+= 1
        let generation = resizeCandidateCaptureGeneration
        Task { @MainActor in
            let driver = WindowMouseInteractionDriver.shared
            let candidate = await driver.makePendingResizeCandidate(sample: sample)
            guard generation == resizeCandidateCaptureGeneration,
                  isLeftMouseButtonDown,
                  getCurrentMouseManipulationKind() == .none
            else { return }
            driver.pendingResizeCandidate = candidate
        }
    }

    private static func onLeftMouseUp(_ event: NSEvent, handlesWorkspaceFocusFallback: Bool) {
        pointerActivityCoalescer.discardPending()
        let timestamp = event.timestamp
        let point = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
        Task { @MainActor in
            resizeCandidateCaptureGeneration &+= 1
            MousePointerTracker.shared.note(point: point, timestamp: timestamp)
            await WindowMouseInteractionDriver.shared.flushBeforeMouseUp()
            finishWorkspaceSidebarDragAfterGlobalMouseUp()
            guard let token: RunSessionGuard = .isServerEnabled else {
                WorkspaceSidebarPanel.updateHoverStateForVisiblePanels()
                return
            }
            do {
                defer { WorkspaceSidebarPanel.updateHoverStateForVisiblePanels() }
                try await resetManipulatedWithMouseIfPossible()
            }
            guard handlesWorkspaceFocusFallback else { return }
            let mouseLocation = mouseLocation
            let clickedMonitor = mouseLocation.monitorApproximation
            switch true {
                // Detect clicks on desktop of different monitors
                case clickedMonitor.activeWorkspace != focus.workspace:
                    _ = try await runLightSession(.globalObserverLeftMouseUp, token) {
                        clickedMonitor.activeWorkspace.focusWorkspace()
                    }
                // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                //  And trigger new window detection that could be delayed due to mouseDown event
                default:
                    windowInventoryPollController?.noteActivity()
            }
        }
    }

    private static func onSystemSleep(_: Notification) {
        Task { @MainActor in
            cancelManipulatedWithMouseState()
            isWindowInventoryPollingSuspendedForSleep = true
            isWindowInventoryPollingStarted = false
            windowInventoryPollController?.stop()
        }
    }

    @MainActor
    static func initObserver() {
        guard !isInitialized else { return }
        isInitialized = true

        let nc = NSWorkspace.shared.notificationCenter
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: onSystemSleep))
        notificationObserverTokens.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main, using: onSystemSleep))

        let pollController = WindowInventoryPollController(
            scheduler: { delay, tolerance, operation in
                let timer = Timer(timeInterval: delay, repeats: false) { _ in
                    Task { @MainActor in
                        await operation()
                    }
                }
                timer.tolerance = tolerance
                RunLoop.main.add(timer, forMode: .common)
                return { timer.invalidate() }
            },
            checkInventory: {
                await MacApp.hasWindowInventoryChanged()
            },
            reconcileIfIdle: {
                scheduleWindowInventoryReconciliationIfIdle()
            }
        )
        windowInventoryPollController = pollController
        startWindowInventoryPollingIfReady()
        ResizePointerEventTapController.shared.install()

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { event in
            // todo reduce number of refreshSession in the callback
            //  resetManipulatedWithMouseIfPossible might call its own refreshSession
            //  The end of the callback calls refreshSession
            onLeftMouseUp(event, handlesWorkspaceFocusFallback: true)
        })
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { event in
            onLeftMouseUp(event, handlesWorkspaceFocusFallback: false)
            return event
        })

        let pointerActivityMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]
        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: pointerActivityMask) { event in
            onPointerActivity(event, handlesGlobalWindowDrag: true)
        })
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: pointerActivityMask) { event in
            onPointerActivity(event, handlesGlobalWindowDrag: false)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: onFlagsChanged))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            onFlagsChanged(event)
            return event
        })

        retainEventMonitor(NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: onKeyDown))
        retainEventMonitor(NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            onKeyDown(event)
            // Check if this key matches a recently-pressed prefix (sequence binding)
            if handleSequenceKeyDown(event: event) {
                return nil // consume the event
            }
            // If this is a sequence prefix key (e.g. Escape), arm the sequence detector
            if let prefix = Key(carbonKeyCode: UInt32(event.keyCode)),
               sequenceBindingsPrefixKeys.contains(prefix) {
                noteSequencePrefixKeyPressed(prefix)
            }
            if event.modifierFlags.contains(.control), event.keyCode == 34 {
                return nil // consume the event
            }
            return event
        })
    }

    @MainActor private static func retainEventMonitor(_ monitor: Any?) {
        guard let monitor else { return }
        eventMonitorTokens.append(monitor)
    }

    @MainActor
    static func noteWindowInventoryActivity() {
        windowInventoryPollController?.noteActivity()
    }

    @MainActor
    static func setWindowInventoryPollingEnabled(_ isEnabled: Bool) {
        isWindowInventoryPollingRequested = isEnabled
        if isEnabled {
            startWindowInventoryPollingIfReady()
        } else {
            isWindowInventoryPollingStarted = false
            windowInventoryPollController?.stop()
        }
    }

    @MainActor
    static func completeStartupRefreshAndSetWindowInventoryPollingEnabled(_ isEnabled: Bool) {
        didCompleteStartupRefresh = true
        setWindowInventoryPollingEnabled(isEnabled)
    }

    @MainActor
    static func refreshSessionsDidBecomeIdle() {
        startWindowInventoryPollingIfReady()
    }

    @MainActor
    private static func startWindowInventoryPollingIfReady() {
        guard isWindowInventoryPollingRequested,
              didCompleteStartupRefresh,
              !isWindowInventoryPollingStarted,
              !isWindowInventoryPollingSuspendedForSleep,
              TrayMenuModel.shared.isEnabled,
              refreshSessionsAreIdle(),
              let windowInventoryPollController
        else { return }
        isWindowInventoryPollingStarted = true
        windowInventoryPollController.start()
    }
}
