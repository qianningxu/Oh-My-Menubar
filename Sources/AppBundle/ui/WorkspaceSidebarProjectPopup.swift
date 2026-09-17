import AppKit
import SwiftUI

func workspaceSidebarProjectPopupProjects(
    _ projects: [WorkspaceSidebarProjectViewModel],
    excluding projectId: WorkspaceProjectId
) -> [WorkspaceSidebarProjectViewModel] {
    projects.filter { $0.id != projectId }
}

func workspaceSidebarProjectPopupWidth(
    projects: [WorkspaceSidebarProjectViewModel],
    showsCreateAction: Bool = true
) -> CGFloat {
    var names = projects.map(\.displayName)
    if showsCreateAction {
        names.append("New project")
    }
    let maximumTextWidth = names.map {
        ($0 as NSString).size(
            withAttributes: [.font: NSFont.systemFont(ofSize: workspaceSidebarProjectLabelFontSize, weight: .medium)]
        ).width
    }.max() ?? 0
    return min(
        max(ceil(maximumTextWidth) + 48, workspaceSidebarProjectPopupMinimumWidth),
        workspaceSidebarProjectPopupMaximumWidth
    )
}

func workspaceSidebarNewProjectName(_ rawName: String) -> String? {
    let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

struct WorkspaceSidebarProjectPopup: View {
    let projects: [WorkspaceSidebarProjectViewModel]
    let selectedProjectId: WorkspaceProjectId
    let onSelect: (WorkspaceProjectId) -> Void
    let onCreate: (String) -> Void
    let onRename: (WorkspaceSidebarProjectViewModel) -> Void
    let onSetColor: (WorkspaceSidebarProjectViewModel, String?) -> Void
    let onDelete: (WorkspaceSidebarProjectViewModel) -> Void
    var showsCreateAction = true
    var allowsContextMenu = true
    var menuWidth: CGFloat? = nil
    var rowHeight: CGFloat = workspaceSidebarProjectPopupRowHeight
    var disabledProjectIds: Set<WorkspaceProjectId> = []
    var showsSelectionIndicator = true
    var onActionMenuVisibilityChanged: (Bool) -> Void = { _ in }
    @State private var isCreatingProject = false
    @State private var newProjectName = ""
    @State private var projectActionsProjectId: WorkspaceProjectId? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var rowCount: Int {
        projects.count + (showsCreateAction ? 1 : 0)
    }
    private var resolvedMenuWidth: CGFloat {
        menuWidth ?? workspaceSidebarProjectPopupWidth(
            projects: projects,
            showsCreateAction: showsCreateAction
        )
    }
    private var contentHeight: CGFloat {
        if isCreatingProject {
            let rowsHeight = CGFloat(projects.count + 1) * rowHeight
            let rowSpacing = CGFloat(projects.count) * standardGap * 0.5
            let verticalPadding: CGFloat = standardGap * 4
            return rowsHeight + rowSpacing + verticalPadding
        }
        let rowsHeight = CGFloat(rowCount) * rowHeight
        let dividerGaps = showsCreateAction ? 1 : 0
        let rowSpacing = CGFloat(max(rowCount - 1, 0) + dividerGaps) * standardGap * 0.5
        let dividerHeight = showsCreateAction ? 0.5 + standardGap : 0
        let verticalPadding = standardGap * 4
        return rowsHeight + rowSpacing + dividerHeight + CGFloat(verticalPadding)
    }

    var body: some View {
        projectPicker
    }

    private var projectPicker: some View {
        VStack(alignment: .leading, spacing: standardGap * 0.5) {
            ForEach(projects) { project in
                projectRow(project)
            }
            if showsCreateAction {
                if isCreatingProject {
                    newProjectNameField
                } else {
                    divider
                    newProjectButton
                }
            }
        }
        .padding(standardGap * 2)
        .frame(minWidth: resolvedMenuWidth, idealWidth: resolvedMenuWidth, maxWidth: resolvedMenuWidth, alignment: .leading)
        .frame(height: contentHeight, alignment: .top)
        .fixedSize(horizontal: menuWidth != nil, vertical: false)
        .background {
            projectPopupSurface
        }
        .onDisappear {
            onActionMenuVisibilityChanged(false)
        }
    }

    private var projectPopupSurface: some View {
        let shape = RoundedRectangle(cornerRadius: workspaceSidebarProjectPopupCornerRadius, style: .continuous)
        return ZStack {
            shape.fill(palette.geistBackground(.primary))
            shape.strokeBorder(
                palette.geistBorder(.normal),
                lineWidth: 0.75
            )
        }
        .compositingGroup()
    }

    private func projectRow(_ project: WorkspaceSidebarProjectViewModel) -> some View {
        HStack(spacing: standardGap * 3.5) {
            Button {
                onSelect(project.id)
            } label: {
                HStack(spacing: standardGap * 3.5) {
                    Text(project.displayName)
                        .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: project.id == selectedProjectId ? .semibold : .medium))
                        .foregroundStyle(palette.content(project.id == selectedProjectId ? .primary : .secondary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if showsSelectionIndicator {
                        checkmark(isVisible: project.id == selectedProjectId)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            if allowsContextMenu {
                Button {
                    projectActionsProjectId = projectActionsProjectId == project.id ? nil : project.id
                    onActionMenuVisibilityChanged(projectActionsProjectId != nil)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.content(.secondary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Project actions")
                .accessibilityLabel("Actions for \(project.displayName)")
            }
        }
        .modifier(WorkspaceSidebarProjectPopupRowStyle(isSelected: project.id == selectedProjectId, rowHeight: rowHeight))
        .disabled(disabledProjectIds.contains(project.id))
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if projectActionsProjectId == project.id {
                WorkspaceSidebarProjectActionMenu(
                    project: project,
                    menuWidth: resolvedMenuWidth,
                    onRename: {
                        projectActionsProjectId = nil
                        onActionMenuVisibilityChanged(false)
                        onRename(project)
                    },
                    onSetColor: { colorHex in
                        projectActionsProjectId = nil
                        onActionMenuVisibilityChanged(false)
                        onSetColor(project, colorHex)
                    },
                    onDelete: {
                        projectActionsProjectId = nil
                        onActionMenuVisibilityChanged(false)
                        onDelete(project)
                    },
                    onDismiss: {
                        projectActionsProjectId = nil
                        onActionMenuVisibilityChanged(false)
                    }
                )
                .offset(x: resolvedMenuWidth + standardGap * 2, y: -standardGap * 2)
                .zIndex(1_000)
            }
        }
        .zIndex(projectActionsProjectId == project.id ? 1_000 : 0)
    }

    private var divider: some View {
        Rectangle()
            .fill(palette.geistBorder(.normal))
            .frame(height: 0.5)
            .padding(.horizontal, workspaceSidebarDropdownPadding)
            .padding(.vertical, standardGap * 0.5)
    }

    private var newProjectButton: some View {
        Button {
            isCreatingProject = true
            newProjectName = ""
        } label: {
            HStack(spacing: standardGap * 3.5) {
                Image(systemName: "plus")
                    .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: .semibold))
                    .frame(width: workspaceSidebarProjectLabelFontSize)
                Text("New project")
                    .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: .medium))
                Spacer(minLength: 0)
                if showsSelectionIndicator {
                    checkmark(isVisible: false)
                }
            }
            .foregroundStyle(palette.content(.secondary))
            .modifier(WorkspaceSidebarProjectPopupRowStyle(isSelected: false, rowHeight: rowHeight))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newProjectNameField: some View {
        HStack(spacing: standardGap * 3.5) {
            Image(systemName: "plus")
                .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: .semibold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarProjectLabelFontSize)
            WorkspaceSidebarProjectRenameTextField(
                text: $newProjectName,
                onCommit: commitNewProject,
                onCancel: cancelNewProject,
                onPanelReady: beginNewProjectTextEditing,
                font: .systemFont(ofSize: workspaceSidebarProjectLabelFontSize, weight: .medium),
                textColor: palette.contentNSColor(.primary),
                placeholder: "Project name"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, standardGap * 3.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Project name")
        .accessibilityValue(newProjectName)
        .onDisappear {
            WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        }
    }

    private func commitNewProject() {
        guard let name = workspaceSidebarNewProjectName(newProjectName) else { return }
        newProjectName = ""
        isCreatingProject = false
        WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        onCreate(name)
    }

    private func cancelNewProject() {
        newProjectName = ""
        isCreatingProject = false
        WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
    }

    @MainActor
    private func beginNewProjectTextEditing(_ panel: WorkspaceSidebarPanel, _ field: NSTextField) {
        WorkspaceSidebarPanel.activeInlineTextEditingPanel?.endInlineTextEditing()
        panel.beginInlineTextEditing(
            locksExpansion: true,
            cancelsOnPointerExit: false,
            editingView: field,
            onCancel: cancelNewProject,
            onKeyDown: handleNewProjectTextKey
        )
    }

    @MainActor
    private func handleNewProjectTextKey(_ key: WorkspaceSidebarInlineTextKey) {
        switch key {
            case .text(let inserted):
                newProjectName += inserted
            case .deleteBackward, .deleteWordBackward:
                if case .deleteWordBackward = key {
                    newProjectName.deleteLastWord()
                } else if !newProjectName.isEmpty {
                    newProjectName.removeLast()
                }
            case .deleteToBeginningOfLine:
                newProjectName = ""
            case .commit:
                commitNewProject()
            case .cancel:
                cancelNewProject()
            case .deleteForward, .moveUp, .moveDown, .ignored:
                break
        }
    }
}

private struct WorkspaceSidebarProjectPopupRowStyle: ViewModifier {
    let isSelected: Bool
    let rowHeight: CGFloat

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, standardGap * 3.5)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(rowFill)
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var rowFill: Color {
        if isSelected {
            return palette.componentBackground(.active)
        }
        return isHovered ? palette.componentBackground(.hover) : WinMuxDesignTokens.transparent
    }
}
