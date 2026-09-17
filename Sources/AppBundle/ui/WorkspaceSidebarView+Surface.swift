import SwiftUI

extension WorkspaceSidebarView {
    func sidebarSwipeCaptureOverlay(expansionProgress: CGFloat) -> some View {
        WorkspaceSidebarProjectSwipeScrollCapture(
            isEnabled: workspaceSidebarProjectSwipeCaptureIsEnabled(
                projectsEnabled: projectsAreEnabled(),
                projectCount: snapshot.projects.count,
                isCompact: workspaceSidebarIsCompact(expansionProgress: expansionProgress)
            ),
            onChanged: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeChanged(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
            onEnded: { horizontalTranslation, verticalTranslation in
                handleProjectSwipeEnded(
                    horizontalTranslation: horizontalTranslation,
                    verticalTranslation: verticalTranslation,
                    expansionProgress: expansionProgress,
                )
            },
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }
}

func workspaceSidebarProjectSwipeCaptureIsEnabled(
    projectsEnabled: Bool,
    projectCount: Int,
    isCompact: Bool
) -> Bool {
    false
}
