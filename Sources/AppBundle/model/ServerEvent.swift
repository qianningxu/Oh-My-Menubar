import Common

public struct ServerEvent: Codable, Sendable {
    private let _event: ServerEventType

    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var windowId: UInt32?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var tab: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var workspace: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var prevTab: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var prevWorkspace: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var monitorId: Int? // 1-based
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var appBundleId: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var appName: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var mode: String?
    // periphery:ignore - false positive unused warning. The var properties are serialized to JSON
    private var binding: String?

    public var eventType: ServerEventType { _event.canonical }

    @MainActor
    public static func focusChanged(windowId: UInt32?, workspace: String) -> ServerEvent {
        ServerEvent(_event: .focusChanged, windowId: windowId, tab: workspaceDisplayName(workspace), workspace: workspace)
    }

    @MainActor
    public static func focusedMonitorChanged(workspace: String, monitorId_oneBased: Int) -> ServerEvent {
        ServerEvent(
            _event: .focusedMonitorChanged,
            tab: workspaceDisplayName(workspace),
            workspace: workspace,
            monitorId: monitorId_oneBased,
        )
    }

    @MainActor
    public static func tabChanged(workspace: String, prevWorkspace: String) -> ServerEvent {
        ServerEvent(
            _event: .tabChanged,
            tab: workspaceDisplayName(workspace),
            workspace: workspace,
            prevTab: workspaceDisplayName(prevWorkspace),
            prevWorkspace: prevWorkspace,
        )
    }

    @MainActor
    public static func workspaceChanged(workspace: String, prevWorkspace: String) -> ServerEvent {
        tabChanged(workspace: workspace, prevWorkspace: prevWorkspace)
    }

    public static func modeChanged(mode: String?) -> ServerEvent {
        ServerEvent(_event: .modeChanged, mode: mode)
    }

    @MainActor
    public static func windowDetected(windowId: UInt32, workspace: String?, appBundleId: String?, appName: String?) -> ServerEvent {
        ServerEvent(
            _event: .windowDetected,
            windowId: windowId,
            tab: workspace.map { workspaceDisplayName($0) },
            workspace: workspace,
            appBundleId: appBundleId,
            appName: appName,
        )
    }

    public static func bindingTriggered(mode: String, binding: String) -> ServerEvent {
        ServerEvent(_event: .bindingTriggered, mode: mode, binding: binding)
    }
}
