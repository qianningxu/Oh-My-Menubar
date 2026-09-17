import Common

struct ReorderWorkspaceCommand: Command {
    let args: ReorderWorkspaceCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        materializePersistedWorkspaceProjects()
        let sourceName = args.source.val.raw
        guard let source = Workspace.existing(byName: sourceName),
              !source.isArchived
        else {
            return io.err("Tab '\(sourceName)' doesn't exist")
        }

        let placement: WorkspaceReorderPlacement
        if let beforeTarget = args.beforeTarget {
            placement = .before(beforeTarget.raw)
        } else if let afterTarget = args.afterTarget {
            placement = .after(afterTarget.raw)
        } else {
            return io.err("Either --before or --after is required")
        }

        guard let target = Workspace.existing(byName: placement.targetWorkspaceName),
              !target.isArchived
        else {
            return io.err("Tab '\(placement.targetWorkspaceName)' doesn't exist")
        }
        guard !projectsAreEnabled() || source.projectId == target.projectId else {
            return io.err("Tabs '\(workspaceDisplayName(source.name))' and '\(workspaceDisplayName(target.name))' cannot be reordered together")
        }
        guard reorderWorkspaceForSidebar(
            sourceWorkspaceName: source.name,
            folderId: target.folderId,
            placement: placement
        ) else {
            return io.err("Tab '\(workspaceDisplayName(source.name))' is already in the requested position")
        }
        return true
    }
}
