import Common
import SwiftUI

extension WorkspaceSidebarView {
    func monitorSelectorSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        WorkspaceSidebarMonitorSelector(
            scopes: snapshot.monitorScopes,
            projects: [],
            selectedScopeId: snapshot.selectedMonitorScopeId,
            activeProjectId: snapshot.activeProjectId,
            browsedProjectId: nil,
            expansionProgress: expansionProgress,
            sectionWidth: workspaceSidebarTopSectionWidth(expansionProgress: expansionProgress),
            onSelectScope: { scopeId in
                actions.send(.selectMonitorScope(scopeId))
            },
            onSelectProject: { projectId in
                // Project browsing is available only from the top-left selector.
            },
            onRenameProject: { project in
                beginProjectRename(project)
            },
            renamingProjectId: $renamingProjectId,
            renamingProjectText: $renamingProjectText,
            onCommitRenameProject: {
                finishProjectRename()
            },
            onCancelRenameProject: {
                finishProjectRename(cancelled: true)
            },
            onSetProjectColor: { project, colorHex in
                actions.send(.setProjectColor(project.id, colorHex: colorHex))
            },
            onDeleteProject: { project in
                actions.send(.deleteProject(project.id))
            },
        )
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.top, snapshot.configuration.topPadding)
        .padding(.bottom, workspaceSidebarSectionGap)
        .zIndex(100)
    }

    func workspaceSidebarTopSectionWidth(expansionProgress: CGFloat) -> CGFloat {
        if browsedProjectId != nil {
            return workspaceSidebarSplitSectionWidth(expansionProgress: expansionProgress)
        }
        return workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
    }

    func widgetSection(
        expansionProgress: CGFloat,
        isCompact: Bool,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        let sectionWidth = workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
        return WorkspaceSidebarWidgetStack(
            widgets: snapshot.configuration.widgets,
            sectionWidth: sectionWidth,
            isCompact: isCompact,
            showsNotePad: showsNotePad,
        )
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, workspaceSidebarStatusBottomPadding(isCompact: isCompact))
    }

    func sidebarSearchSection(
        expansionProgress: CGFloat,
        leadingInset: CGFloat,
        trailingInset: CGFloat,
    ) -> some View {
        HStack(spacing: standardGap * 3.5) {
            let palette = sidebarPalette
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: 14)

            Text(searchText)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(palette.content(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                finishSidebarSearch(clearText: true)
                beginSidebarSearchIfNeeded()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.content(.secondary))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Clear search")
        }
        .padding(.horizontal, standardGap * 4)
        .frame(width: workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration), height: workspaceSidebarSearchHeight)
        .background {
            RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                .fill(sidebarPalette.componentBackground(.normal))
        }
        .overlay {
            RoundedRectangle(cornerRadius: workspaceSidebarDropdownCornerRadius, style: .continuous)
                .strokeBorder(sidebarPalette.geistBorder(.normal), lineWidth: 0.6)
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .padding(.bottom, workspaceSidebarSectionGap)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
