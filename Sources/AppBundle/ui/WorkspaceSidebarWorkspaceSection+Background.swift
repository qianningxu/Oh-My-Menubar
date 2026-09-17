import SwiftUI

extension WorkspaceSidebarWorkspaceSection {
    var sectionBackground: some View {
        sectionShape
            .fill(sectionBackgroundFill)
            .overlay {
                sectionShape
                    .strokeBorder(
                        sectionBorderColor,
                        style: sectionBorderStyle
                    )
            }
    }

    var sectionBorderColor: Color {
        if isDropTarget {
            return palette.geistBorder(.active)
        }
        if isSearchSelectedWorkspace {
            return palette.geistBorder(.active)
        }
        if allowsWorkspaceActivation && isInUseOnOtherDisplay {
            return palette.color(.red, isPointerHoverVisible ? .color5 : .color4)
        }
        if isVisuallyActiveOnTargetMonitor && showsWindowRows {
            return WinMuxDesignTokens.transparent
        }
        if (isVisuallyActiveOnTargetMonitor || isPinnedActiveWorkspace) && !showsWindowRows {
            return WinMuxDesignTokens.transparent
        }
        if isVisuallyActiveOnTargetMonitor || isPinnedActiveWorkspace {
            return palette.geistBorder(isPointerHoverVisible ? .hover : .normal)
        }
        if isFromOtherDisplay {
            return palette.color(.pink, isPointerHoverVisible ? .color5 : .color4)
        }
        return WinMuxDesignTokens.transparent
    }

    var sectionBorderStyle: StrokeStyle {
        if isPinnedActiveWorkspace && !isSearchFiltering {
            return StrokeStyle(lineWidth: 1, dash: [5, 4])
        }
        return StrokeStyle(lineWidth: isPointerHoverVisible || isVisuallyActiveOnTargetMonitor || isDropTarget ? 0.75 : 0.6)
    }

    var sectionBackgroundFill: Color {
        if isDropTarget {
            return palette.componentBackground(.active)
        }
        if isSearchSelectedWorkspace {
            return palette.geistBackground(.primary)
        }
        if isSearchFiltering {
            return palette.componentBackground(isPointerHoverVisible ? .hover : .normal)
        }
        if allowsWorkspaceActivation && isInUseOnOtherDisplay {
            if isPointerHoverVisible {
                return palette.color(.red, workspace.isFocused ? .color3 : .color2)
            }
            return palette.color(.red, workspace.isFocused ? .color2 : .color1)
        }
        if isPinnedActiveWorkspace {
            return WinMuxDesignTokens.transparent
        }
        if isVisuallyActiveOnTargetMonitor && showsWindowRows {
            return WinMuxDesignTokens.transparent
        }
        if isVisuallyActiveOnTargetMonitor && nestedContentIndent <= 0 {
            return WinMuxDesignTokens.transparent
        }
        if isFromOtherDisplay {
            return palette.color(.pink, isPointerHoverVisible ? .color2 : .color1)
        }
        return WinMuxDesignTokens.transparent
    }

    var compactFocusOpacity: Double {
        isCompact && !isOnFocusedMonitor ? 0.72 : 1
    }

    var inUseOverrideOverlay: some View {
        WorkspaceSidebarInUseOverrideOverlay(text: inUseOverrideText) {
            activeInUseOverrideWorkspaceName = nil
            actions.send(.overrideWorkspaceInUse(workspace.name))
        }
    }
}
