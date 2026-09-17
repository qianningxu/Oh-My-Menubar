import Common

struct MoveNodeToWorkspaceCommand: Command {
    let args: MoveNodeToWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache: Bool = true

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        guard let target = args.resolveTargetOrReportError(env, io) else { return false }
        guard let window = target.windowOrNil else { return io.err(noWindowIsFocused) }
        let subjectWs = window.nodeWorkspace
        let targetWorkspace: Workspace
        switch args.target.val {
            case .fresh:
                guard let subjectWs else { return io.err("Window \(window.windowId) doesn't belong to any Tab") }
                targetWorkspace = createFreshAdjacentBlankWorkspace(
                    projectId: subjectWs.projectId,
                    monitor: window.nodeMonitor ?? subjectWs.workspaceMonitor,
                    after: subjectWs,
                )
            case .relative(let nextPrev):
                guard let subjectWs else { return io.err("Window \(window.windowId) doesn't belong to any Tab") }
                let ws = getNextPrevWorkspace(
                    current: subjectWs,
                    isNext: nextPrev == .next,
                    wrapAround: args.wrapAround,
                    stdin: args.useStdin ? io.readStdin() : nil,
                )
                    ?? createNextTransientBlankWorkspaceForMoveIfAllowed(
                        from: subjectWs,
                        isNext: nextPrev == .next,
                        wrapAround: args.wrapAround,
                        usesStdin: args.useStdin,
                    )
                guard let ws else { return io.err("Can't resolve next or prev Tab") }
                targetWorkspace = ws
            case .direct(let name):
                guard let ws = resolveMoveTargetWorkspace(
                    named: name.raw,
                    sourceWorkspace: subjectWs ?? target.workspace,
                    sourceMonitor: window.nodeMonitor ?? target.workspace.workspaceMonitor,
                ) else {
                    return io.err("Tab '\(name.raw)' doesn't exist")
                }
                targetWorkspace = ws
        }
        let didMove = moveWindowToWorkspace(
            window,
            targetWorkspace,
            io,
            focusFollowsWindow: args.focusFollowsWindow,
            failIfNoop: args.failIfNoop
        )
        if didMove {
            revealWorkspaceSidebarForWorkspaceActivity(on: targetWorkspace.workspaceMonitor)
        }
        return didMove
    }
}

@MainActor
private func createNextTransientBlankWorkspaceForMoveIfAllowed(
    from current: Workspace,
    isNext: Bool,
    wrapAround: Bool,
    usesStdin: Bool,
) -> Workspace? {
    guard isNext, !wrapAround, !usesStdin else { return nil }
    let nextWorkspaceIndex = monitorScopedAutomaticDisplayWorkspacesInExactProject(
        projectId: current.projectId,
        monitor: current.workspaceMonitor,
        focusedWorkspace: current,
    ).count + 1
    return createAdjacentTransientBlankWorkspaceIfAllowed(
        named: String(nextWorkspaceIndex),
        projectId: current.projectId,
        monitor: current.workspaceMonitor,
        focusedWorkspace: current,
    )
}

@MainActor
private func resolveMoveTargetWorkspace(
    named workspaceName: String,
    sourceWorkspace: Workspace,
    sourceMonitor: Monitor,
) -> Workspace? {
    if let targetIndex = parsePositiveWorkspaceDisplayIndex(workspaceName) {
        let automaticDisplayWorkspaces = monitorScopedAutomaticDisplayWorkspacesInExactProject(
            projectId: sourceWorkspace.projectId,
            monitor: sourceMonitor,
            focusedWorkspace: sourceWorkspace,
        )
        if let workspace = automaticDisplayWorkspaces.getOrNil(atIndex: targetIndex - 1) {
            return workspace
        }
        return createAdjacentTransientBlankWorkspaceIfAllowed(
            named: workspaceName,
            projectId: sourceWorkspace.projectId,
            monitor: sourceMonitor,
            focusedWorkspace: sourceWorkspace,
        )
    }

    let existedBefore = Workspace.existing(byName: workspaceName) != nil
    let workspace = Workspace.get(byName: workspaceName)
    if !existedBefore {
        workspace.assignProject(sourceWorkspace.projectId)
    }
    workspace.seedMonitorIfNeeded(sourceMonitor)
    return workspace
}

@MainActor
func moveWindowToWorkspace(_ window: Window, _ targetWorkspace: Workspace, _ io: CmdIo, focusFollowsWindow: Bool, failIfNoop: Bool, index: Int = INDEX_BIND_LAST) -> Bool {
    if window.nodeWorkspace == targetWorkspace {
        if !failIfNoop {
            io.err("Window '\(window.windowId)' already belongs to Tab '\(workspaceDisplayName(targetWorkspace.name))'. Tip: use --fail-if-noop to exit with non-zero code")
        }
        return !failIfNoop
    }
    if window.isFloating {
        window.bind(to: targetWorkspace, adaptiveWeight: WEIGHT_AUTO, index: index)
    } else {
        let binding = workspaceAppendBindingData(targetWorkspace: targetWorkspace, index: index)
        window.bind(to: binding.parent, adaptiveWeight: binding.adaptiveWeight, index: binding.index)
    }
    return focusFollowsWindow ? window.focusWindow() : true
}
