import AppKit
import Common
import SwiftUI

func workspaceSidebarIsCompact(expansionProgress: CGFloat) -> Bool {
    expansionProgress < workspaceSidebarRowsRevealProgress
}

func workspaceSidebarShouldShowProjectPager(projectsEnabled: Bool, isCompact: Bool) -> Bool {
    false
}

extension WorkspaceSidebarView {
    var shouldShowTopFilterBar: Bool {
        let hasFocusFilter = snapshot.monitorScopes.contains { $0.id == workspaceSidebarFocusedScopeId }
        return hasFocusFilter
    }

    func workspaceSidebarSplitSectionWidth(expansionProgress: CGFloat) -> CGFloat {
        let sectionWidth = workspaceSidebarSectionWidth(expansionProgress, layout: snapshot.configuration)
        return (sectionWidth * 2) + workspaceSidebarSplitPaneGap
    }

    func workspaceSidebarContentFrameWidth(expansionProgress: CGFloat) -> CGFloat {
        workspaceSidebarNormalContentFrameWidth(
            expansionProgress: expansionProgress,
            layout: snapshot.configuration
        )
    }
}

let workspaceSidebarSplitPaneGap: CGFloat = workspaceSidebarStandardGap

@MainActor
func workspaceSidebarNormalContentFrameWidth(
    expansionProgress: CGFloat,
    layout: WorkspaceSidebarConfiguration
) -> CGFloat {
    let isCompact = expansionProgress < workspaceSidebarRowsRevealProgress
    return workspaceSidebarSectionWidth(expansionProgress, layout: layout) +
        workspaceSidebarOuterLeadingPadding(isCompact: isCompact) +
        workspaceSidebarOuterTrailingPadding(isCompact: isCompact)
}

@MainActor
func workspaceSidebarExpandedContentFrameWidth(layout: WorkspaceSidebarConfiguration) -> CGFloat {
    let expandedSectionWidth = workspaceSidebarExpandedSectionWidth(layout: layout)
    return (expandedSectionWidth * 2) +
        workspaceSidebarSplitPaneGap +
        workspaceSidebarContentLeadingInset +
        workspaceSidebarContentTrailingInset
}
