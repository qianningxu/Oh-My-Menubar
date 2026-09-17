import SwiftUI

enum WorkspaceSidebarDropTargetKind: Equatable {
    case workspace(String)
    case folder(WorkspaceProjectId, monitorScopeId: String)
    case newWorkspace(projectId: WorkspaceProjectId, monitorScopeId: String)
    case monitor(String)
}

struct WorkspaceSidebarDropTarget {
    let kind: WorkspaceSidebarDropTargetKind
    let rect: Rect
}

struct WorkspaceSidebarDropTargetFrame: Equatable {
    let kind: WorkspaceSidebarDropTargetKind
    let frame: CGRect
}

struct WorkspaceSidebarDropTargetPreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceSidebarDropTargetFrame] = []

    static func reduce(value: inout [WorkspaceSidebarDropTargetFrame], nextValue: () -> [WorkspaceSidebarDropTargetFrame]) {
        value.append(contentsOf: nextValue())
    }
}

@MainActor
func workspaceSidebarDropTarget(at mouseLocation: CGPoint, hitSlop: NSEdgeInsets = NSEdgeInsets()) -> WorkspaceSidebarDropTarget? {
    WorkspaceSidebarPanel.panel(containing: mouseLocation)
        .flatMap { panel in
            panel.visibleScreenRectNormalized().flatMap { visibleRect in
                workspaceSidebarDropTarget(
                    in: workspaceSidebarDropTargets,
                    panelVisibleRect: visibleRect,
                    at: mouseLocation,
                    hitSlop: hitSlop,
                )
            }
        }
}

func workspaceSidebarDropTarget(
    in targets: [WorkspaceSidebarDropTarget],
    panelVisibleRect: Rect,
    at mouseLocation: CGPoint,
    hitSlop: NSEdgeInsets = NSEdgeInsets()
) -> WorkspaceSidebarDropTarget? {
    let candidates = targets.filter { target in
        panelVisibleRect.contains(target.rect.center) &&
            target.rect.expanded(
                left: hitSlop.left,
                right: hitSlop.right,
                top: hitSlop.top,
                bottom: hitSlop.bottom
            ).contains(mouseLocation)
    }
    return candidates.last(where: { !$0.kind.isFolder }) ?? candidates.last
}

private extension WorkspaceSidebarDropTargetKind {
    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}
