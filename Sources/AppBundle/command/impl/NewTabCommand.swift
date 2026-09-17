import AppKit
import Common

struct NewTabCommand: Command {
    let args: NewTabCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = true

    @MainActor
    func run(_ env: CmdEnv, _ io: CmdIo) async throws -> Bool {
        let current = focus.workspace
        let workspace = createFreshAdjacentBlankWorkspace(
            folderId: current.folderId,
            monitor: current.workspaceMonitor,
            after: current
        )
        return workspace.focusWorkspace()
    }
}
