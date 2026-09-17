import AppKit
import Common
import SwiftUI

@MainActor
final class WorkspaceSidebarPanel: NSPanelHud {
    static let shared = WorkspaceSidebarPanel(monitor: mainMonitor)
    private static var panelsByMonitorScopeId: [String: WorkspaceSidebarPanel] = [:]
    static weak var activeInlineTextEditingPanel: WorkspaceSidebarPanel?

    let viewModel: TrayMenuModel
    let hostingView: WorkspaceSidebarHostingView
    let monitorScopeId: String
    var isHoverMonitoring = false
    var menuTrackingDepth = 0
    var menuTrackingGraceUntil: Date = .distantPast
    var inlineTextEditingActive = false
    var inlineTextEditingLocksExpansion = true
    var inlineTextEditingCancelsOnPointerExit = true
    var inlineTextEditingCancel: (@MainActor () -> Void)?
    var inlineTextEditingKeyDown: (@MainActor (WorkspaceSidebarInlineTextKey) -> Void)?
    weak var inlineTextEditingView: NSView?
    var inlineTextEditingUsesNativeEditor = false
    var inlineTextEditingEventMonitors: [Any] = []
    var inlineTextEditingKeyEventTap: CFMachPort?
    var inlineTextEditingKeyEventTapRunLoopSource: CFRunLoopSource?
    var inlineTextEditingStartedAt: Date = .distantPast
    var inlineTextEditingPointerEnteredVisibleRegion = false
    var commandExpansionLocksCollapse = false
    var optionKeyExpansionLocksCollapse = false
    var shouldLockNextSidebarSearchExpansion = false
    var bufferedCommandSidebarSearchKeys: [WorkspaceSidebarInlineTextKey] = []
    var commandMouseUnlockPoint: CGPoint?
    var commandMouseUnlockMonitors: [Any] = []
    var projectActionMenuPresentationExtraWidth: CGFloat = 0
    var projectMenuPresentationExtraHeight: CGFloat = 0
    var projectBarContentSize: CGSize = .zero
    var autoHideGeneration: UInt64 = 0
    var workspaceActivityRevealUntil: Date = .distantPast
    var menuTrackingObservers: [NSObjectProtocol] = []
    var lastEdgeTrapSample: MousePointerSample?
    var edgeTrapStartedAt: TimeInterval?
    var edgeTrapSuppressedUntil: TimeInterval = 0
    var splitBrowseCollapseSuppressedUntil: Date = .distantPast
    let hoverExitTolerance: CGFloat = 20
    let hoverOpenDelay: TimeInterval = 0.05
    let hoverCueAnimationResponse: TimeInterval = 0.18
    let animationDuration: TimeInterval = 0.11
    let menuTrackingEndGrace: TimeInterval = 0.75
    let edgeTrapBandWidth: CGFloat = 18
    let edgeTrapReleaseVelocityThreshold: CGFloat = 4
    let edgeTrapReleaseDelay: TimeInterval = 0.2
    let edgeTrapCrossingGrace: TimeInterval = 0.25

    private init(monitor: Monitor) {
        monitorScopeId = workspaceSidebarMonitorScopeId(for: monitor)
        viewModel = TrayMenuModel()
        hostingView = WorkspaceSidebarHostingView(rootView: WorkspaceSidebarContainerView(
            viewModel: viewModel,
            actions: makeWorkspaceSidebarActionsAdapter(viewModel: viewModel, targetMonitorScopeId: monitorScopeId)
        ))
        super.init()
        identifier = NSUserInterfaceItemIdentifier("\(workspaceSidebarPanelId).\(monitorScopeId)")
        styleMask.remove(.nonactivatingPanel)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        // The workspace bar renders its own configurable rounded shadow.
        hasShadow = false
        isFloatingPanel = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        applyWinMuxLayer(.menuBarSurface)
        contentView = hostingView
        hostingView.frame = contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        installMenuTrackingObservers()
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        // This panel intentionally floats above the display's bottom work area.
        frameRect
    }

    static var visiblePanels: [WorkspaceSidebarPanel] {
        panelsByMonitorScopeId.values.filter(\.isVisible)
    }

    static var allPanels: [WorkspaceSidebarPanel] {
        Array(panelsByMonitorScopeId.values)
    }

    static func panel(containing point: CGPoint) -> WorkspaceSidebarPanel? {
        visiblePanels.first { $0.visibleScreenRectNormalized()?.contains(point) == true }
    }

    static func panel(for monitorScopeId: String) -> WorkspaceSidebarPanel? {
        panelsByMonitorScopeId[monitorScopeId]
    }

    static func updateVisibleDropTargets(_ targets: [WorkspaceSidebarDropTargetFrame]) {
        workspaceSidebarDropTargets = visiblePanels.flatMap { $0.convertDropTargets(targets) }
    }

    static func refreshAll() {
        guard !isRestoringStartupLayout else { return }
        MenuBarStatusWidgetsController.shared.refreshIfInstalled()
        guard TrayMenuModel.shared.isEnabled, config.workspaceSidebar.enabled else {
            removeCachedPanels()
            return
        }
        let monitors = workspaceSidebarResolvedPanelMonitors()
        let activeMonitorScopeIds = Set(monitors.map { workspaceSidebarMonitorScopeId(for: $0) })
        for monitor in monitors {
            let scopeId = workspaceSidebarMonitorScopeId(for: monitor)
            let panel = panelsByMonitorScopeId[scopeId] ?? WorkspaceSidebarPanel(monitor: monitor)
            panelsByMonitorScopeId[scopeId] = panel
            panel.syncModelFromShared()
            panel.refresh(on: monitor)
        }
        let inactiveScopeIds = panelsByMonitorScopeId.keys.filter { !activeMonitorScopeIds.contains($0) }
        for scopeId in inactiveScopeIds {
            panelsByMonitorScopeId.removeValue(forKey: scopeId)?.prepareForRemoval()
        }
    }

    static func syncVisiblePanelModelsFromShared() {
        for panel in visiblePanels {
            panel.syncModelFromShared()
        }
    }

    static func resetPanelStateForTests() {
        workspaceSidebarDropTargets = []
        activeInlineTextEditingPanel = nil
        shared.resetForTests()
        removeCachedPanels()
    }

    private static func removeCachedPanels() {
        let retainedPanels = Array(panelsByMonitorScopeId.values)
        panelsByMonitorScopeId = [:]
        for panel in retainedPanels {
            panel.prepareForRemoval()
        }
    }

    func syncModelFromShared() {
        let workspacesChanged = viewModel.setIfChanged(
            \.workspaceSidebarWorkspaces,
            to: TrayMenuModel.shared.workspaceSidebarWorkspaces
        )
        let projectsChanged = viewModel.setIfChanged(
            \.workspaceSidebarProjects,
            to: TrayMenuModel.shared.workspaceSidebarProjects
        )
        viewModel.setIfChanged(\.workspaceSidebarFolders, to: TrayMenuModel.shared.workspaceSidebarFolders)
        let activeProjectChanged = viewModel.setIfChanged(
            \.workspaceSidebarActiveProjectId,
            to: resolvedLocalActiveProjectId()
        )
        viewModel.setIfChanged(\.workspaceSidebarMonitorScopes, to: TrayMenuModel.shared.workspaceSidebarMonitorScopes)
        viewModel.setIfChanged(\.workspaceSidebarSelectedMonitorScopeId, to: resolvedLocalSelectedMonitorScopeId())
        viewModel.setIfChanged(\.workspaceSidebarTargetMonitorScopeId, to: monitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarFocusedMonitorScopeId, to: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId)
        viewModel.setIfChanged(\.workspaceSidebarShowsMonitorSelector, to: TrayMenuModel.shared.workspaceSidebarShowsMonitorSelector)
        viewModel.setIfChanged(\.workspaceSidebarDropPreview, to: TrayMenuModel.shared.workspaceSidebarDropPreview)
        viewModel.setIfChanged(\.workspaceSidebarTopPadding, to: TrayMenuModel.shared.workspaceSidebarTopPadding)
        viewModel.setIfChanged(\.isWorkspaceSidebarAutoHideEnabled, to: TrayMenuModel.shared.isWorkspaceSidebarAutoHideEnabled)
        viewModel.setIfChanged(\.isWorkspaceSidebarPinnedExpanded, to: TrayMenuModel.shared.isWorkspaceSidebarPinnedExpanded)
        viewModel.setIfChanged(\.workspaceSidebarHoveredWorkspaceName, to: resolvedLocalHoveredWorkspaceName())
        if workspacesChanged || projectsChanged || activeProjectChanged {
            projectBarContentSize = .zero
        }
    }

    func setProjectBarContentSize(_ size: CGSize) {
        let normalized = CGSize(width: ceil(max(size.width, 1)), height: ceil(max(size.height, 1)))
        guard projectBarContentSize != normalized else { return }
        projectBarContentSize = normalized
        guard let layout = currentSidebarPanelLayout(), frame != layout.frame else { return }
        setFrame(layout.frame, display: true, animate: false)
        viewModel.workspaceSidebarVisibleWidth = isVisible ? layout.frame.width : 0
    }

    private func resolvedLocalActiveProjectId() -> WorkspaceProjectId {
        let monitor = workspaceSidebarMonitor(forScopeId: monitorScopeId)
        return monitor.map { activeWorkspaceProjectId(for: $0) } ?? workspaceProjectDefaultId
    }

    private func resolvedLocalSelectedMonitorScopeId() -> String {
        let validScopeIds = Set(TrayMenuModel.shared.workspaceSidebarMonitorScopes.map(\.id))
        if validScopeIds.contains(viewModel.workspaceSidebarSelectedMonitorScopeId) {
            return viewModel.workspaceSidebarSelectedMonitorScopeId
        }
        return workspaceSidebarDefaultScopeId
    }

    private func resolvedLocalHoveredWorkspaceName() -> String? {
        let visibleWorkspaceNames = visibleWorkspaceNamesForSidebar(
            workspaces: TrayMenuModel.shared.workspaceSidebarWorkspaces,
            selectedMonitorScopeId: viewModel.workspaceSidebarSelectedMonitorScopeId,
            focusedMonitorScopeId: TrayMenuModel.shared.workspaceSidebarFocusedMonitorScopeId,
            targetMonitorScopeId: monitorScopeId,
        )
        return sanitizedWorkspaceSidebarHoveredWorkspaceName(
            visibleWorkspaceNames: visibleWorkspaceNames,
            hoveredWorkspaceName: TrayMenuModel.shared.workspaceSidebarHoveredWorkspaceName,
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func resetForTests() {
        stopHoverMonitoring()
        endInlineTextEditing()
        menuTrackingDepth = 0
        menuTrackingGraceUntil = .distantPast
        commandExpansionLocksCollapse = false
        optionKeyExpansionLocksCollapse = false
        shouldLockNextSidebarSearchExpansion = false
        bufferedCommandSidebarSearchKeys = []
        removeCommandMouseUnlockMonitors()
        lastEdgeTrapSample = nil
        edgeTrapStartedAt = nil
        edgeTrapSuppressedUntil = 0
        splitBrowseCollapseSuppressedUntil = .distantPast
        projectActionMenuPresentationExtraWidth = 0
        projectMenuPresentationExtraHeight = 0
        projectBarContentSize = .zero
        autoHideGeneration = 0
        workspaceActivityRevealUntil = .distantPast
        resetHiddenSidebarState()
        ignoresMouseEvents = false
    }

    private func prepareForRemoval() {
        endInlineTextEditing()
        removeInlineTextEditingEventMonitors()
        removeInlineTextEditingKeyEventTap()
        removeCommandMouseUnlockMonitors()
        removeMenuTrackingObservers()
        resetHiddenSidebarState()
        close()
    }

    func removeCommandMouseUnlockMonitors() {
        for monitor in commandMouseUnlockMonitors {
            NSEvent.removeMonitor(monitor)
        }
        commandMouseUnlockMonitors = []
        commandMouseUnlockPoint = nil
    }

    override func becomeKey() {
        super.becomeKey()
        debugWorkspaceSidebarRenameLog("panel becomeKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
    }

    override func resignKey() {
        debugWorkspaceSidebarRenameLog("panel resignKey isKey=\(isKeyWindow) firstResponder=\(String(describing: firstResponder))")
        super.resignKey()
    }

    override func keyDown(with event: NSEvent) {
        debugWorkspaceSidebarRenameLog("panel keyDown keyCode=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "nil") firstResponder=\(String(describing: firstResponder)) inline=\(inlineTextEditingActive)")
        // A real NSTextField has already processed an event by the time it
        // reaches the panel's responder-chain fallback. Keep an explicit mode
        // flag because SwiftUI can briefly replace the weak hosting view while
        // its field editor is still the first responder.
        let hasNativeFieldEditor = (firstResponder as? NSTextView)?.isFieldEditor == true
        if !inlineTextEditingUsesNativeEditor,
           !hasNativeFieldEditor,
           handleInlineTextEditingKey(inlineTextKey(from: event))
        {
            return
        }
        super.keyDown(with: event)
    }
}

final class WorkspaceSidebarHostingView: NSHostingView<WorkspaceSidebarContainerView> {
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let panel = window as? WorkspaceSidebarPanel else {
            return super.hitTest(point)
        }
        let pointInWindow = convert(point, to: nil)
        let pointOnScreen = panel.convertPoint(toScreen: pointInWindow)
        guard panel.isPointInsideInteractiveRegion(pointOnScreen) else {
            return nil
        }
        return super.hitTest(point)
    }
}
