import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var workspaceBadge: some View {
        Text(workspaceBadgeText)
            .font(.system(size: 18, weight: isVisuallyActiveOnTargetMonitor ? .bold : .semibold))
            .monospacedDigit()
            .foregroundStyle(workspaceBadgeForeground)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(width: workspaceSidebarBadgeWidth, height: workspaceSidebarBadgeWidth)
    }

    var workspaceBadgeText: String {
        if workspace.isGeneratedName, workspace.sidebarLabel.isEmpty {
            return generatedWorkspaceBadgeText
        }
        if workspace.isGeneratedName, let initial = workspace.displayName.first {
            return String(initial).uppercased()
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    var generatedWorkspaceBadgeText: String {
        let prefix = "Tab "
        if workspace.displayName.hasPrefix(prefix) {
            let suffix = String(workspace.displayName.dropFirst(prefix.count))
            if !suffix.isEmpty { return suffix }
        }
        return workspace.displayName.first.map { String($0).uppercased() } ?? "W"
    }

    var workspaceBadgeForeground: Color {
        if isVisuallyActiveOnTargetMonitor {
            return palette.content(.primary)
        }
        return palette.content(.secondary)
    }
}
