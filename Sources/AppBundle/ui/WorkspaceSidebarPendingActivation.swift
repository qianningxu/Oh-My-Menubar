struct WorkspaceSidebarPendingActivation: Equatable {
    let workspaceName: String
    let targetMonitorScopeId: String
}

let workspaceSidebarPendingActivationTimeoutNanoseconds: UInt64 = 900_000_000

func workspaceSidebarPendingActivationMatches(
    _ pendingActivation: WorkspaceSidebarPendingActivation?,
    workspace: WorkspaceSidebarWorkspaceViewModel,
    targetMonitorScopeId: String,
    isActiveOnTargetMonitor: Bool
) -> Bool {
    guard let pendingActivation else { return false }
    return !isActiveOnTargetMonitor &&
        pendingActivation.workspaceName == workspace.name &&
        pendingActivation.targetMonitorScopeId == targetMonitorScopeId
}

func workspaceSidebarPendingActivationHasResolved(
    _ pendingActivation: WorkspaceSidebarPendingActivation,
    workspaces: [WorkspaceSidebarWorkspaceViewModel]
) -> Bool {
    workspaces.contains {
        $0.name == pendingActivation.workspaceName &&
            $0.monitorScopeId == pendingActivation.targetMonitorScopeId &&
            $0.isVisible
    }
}
