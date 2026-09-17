import AppKit
import Common
import SwiftUI

let workspaceSidebarPanelId = "WinMux.workspaceSidebar"
let workspaceSidebarFrameContentInset = WinMuxSpacing.regular
let workspaceSidebarContentLeadingInset = workspaceSidebarFrameContentInset
let workspaceSidebarContentTrailingInset = workspaceSidebarFrameContentInset
let workspaceSidebarMinimumTopPadding = WinMuxSpacing.regular
let workspaceSidebarCompactRailHorizontalInset = WinMuxSpacing.none
let workspaceSidebarUnifiedGap = WinMuxSpacing.compact
let workspaceSidebarWidgetStackGap = WinMuxSpacing.regular
let workspaceSidebarWidgetContentPadding = WinMuxSpacing.panel
let workspaceSidebarContentToWidgetGap = WinMuxSpacing.section
let workspaceSidebarWorkspaceListMaximumHeight = WinMuxSpacing.page * 8
let workspaceSidebarSectionInnerHorizontalInset = WinMuxSpacing.none
let workspaceSidebarSectionGap = WinMuxSpacing.regular
let workspaceSidebarListItemSpacing = WinMuxSpacing.hairline
let workspaceSidebarNestedRowSpacing = WinMuxSpacing.hairline
let workspaceSidebarFolderOuterVerticalMargin = WinMuxSpacing.hairline
let workspaceSidebarBadgeWidth: CGFloat = 22
let workspaceSidebarHeaderSpacing = WinMuxSpacing.regular
let workspaceSidebarHeaderRowLeadingPadding = WinMuxSpacing.regular
let workspaceSidebarRowsRevealProgress: CGFloat = 0.58
let workspaceSidebarPanelRightCornerRadius: CGFloat = WorkspaceSidebarSideAreaMetrics.standard.plateCornerRadius
let workspaceSidebarPlateCornerRadius: CGFloat = 12
let workspaceSidebarSectionCornerRadius: CGFloat = workspaceSidebarPlateCornerRadius
let workspaceSidebarRowCornerRadius: CGFloat = 10
let workspaceSidebarRowHorizontalPadding: CGFloat = workspaceSidebarUnifiedGap
let workspaceSidebarTabRowHeight: CGFloat = 32
let workspaceSidebarWindowRowsLeadingIndent: CGFloat = 0
let workspaceSidebarAppIconSize: CGFloat = 14
let workspaceSidebarCompactAppIconSize: CGFloat = 20
let workspaceSidebarCompactAppIconOpticalScale: CGFloat = 1.2
let workspaceSidebarCompactSymbolSize: CGFloat = 15
let workspaceSidebarAppIconTextSpacing = WinMuxSpacing.comfortable
let workspaceSidebarWindowCloseButtonSize: CGFloat = 18
let workspaceSidebarWindowCloseButtonTrailingInset = WinMuxSpacing.comfortable
let workspaceSidebarWindowCloseButtonReservedWidth: CGFloat = 22
let workspaceSidebarTabGroupChildLeadingIndent: CGFloat = 12
let workspaceSidebarNestedTabRowHeight: CGFloat = workspaceSidebarTabRowHeight
let workspaceSidebarControlHeight: CGFloat = 32
let workspaceSidebarDropdownHeight: CGFloat = 32
let workspaceSidebarSearchHeight: CGFloat = 32
let workspaceSidebarDropdownCornerRadius: CGFloat = 9
let workspaceSidebarDropdownPadding = WinMuxSpacing.comfortable
let workspaceSidebarDropdownLabelSize: CGFloat = 11.5
let workspaceSidebarDropdownSymbolSize: CGFloat = 10.5
let workspaceSidebarPagerHeight: CGFloat = 32
let workspaceSidebarWorkspaceSectionHeaderHeight: CGFloat = workspaceSidebarTabRowHeight
let workspaceSidebarWorkspaceRowHeight: CGFloat = 26
let workspaceSidebarWorkspaceSectionHeightCompact: CGFloat = workspaceSidebarTabRowHeight
let workspaceSidebarWorkspaceSectionHeightExpanded: CGFloat = workspaceSidebarTabRowHeight
let workspaceSidebarInUseOverrideEmptySectionMinHeight: CGFloat = 76
let workspaceSidebarProjectDotFrameHeight: CGFloat = 32
let workspaceSidebarMenuRowHeight: CGFloat = 28
let workspaceSidebarMenuRowSpacing = WinMuxSpacing.comfortable
let workspaceSidebarMenuRowHorizontalPadding = WinMuxSpacing.section
let workspaceSidebarProjectPopupRowHeight: CGFloat = 26
let workspaceSidebarProjectPopupCornerRadius: CGFloat = 8
let workspaceSidebarProjectPopupMinimumWidth: CGFloat = 124
let workspaceSidebarProjectPopupMaximumWidth: CGFloat = 184
let workspaceSidebarProjectLabelFontSize: CGFloat = 14
let workspaceSidebarHoverAnimation: Animation = .interactiveSpring(response: 0.34, dampingFraction: 0.86, blendDuration: 0.06)
let workspaceSidebarReducedMotionHoverAnimation: Animation = .easeOut(duration: 0.14)
let workspaceSidebarDragStartDistance: CGFloat = 8
let workspaceSidebarProjectSwipeIntentThreshold: CGFloat = 5
let workspaceSidebarProjectSwipeNavigateThreshold: CGFloat = 44
let workspaceSidebarProjectSwipeCreateThreshold: CGFloat = 104
let workspaceSidebarProjectSwipeFormationStart: CGFloat = 22
let workspaceSidebarHoverOpenThresholdFraction: CGFloat = 0.75
let workspaceSidebarDisplayEdgeCompactionMargin = WinMuxSpacing.regular
@MainActor
var workspaceSidebarDropTargets: [WorkspaceSidebarDropTarget] = []

struct WorkspaceSidebarProjectColorPreset: Hashable, Identifiable {
    let name: String
    let hex: String

    var id: String { hex }
}

let workspaceSidebarDefaultProjectColorHex = "#8F8F8F"

let workspaceSidebarProjectColorPresets: [WorkspaceSidebarProjectColorPreset] = [
    WorkspaceSidebarProjectColorPreset(name: "Gray", hex: workspaceSidebarDefaultProjectColorHex),
    WorkspaceSidebarProjectColorPreset(name: "Blue", hex: "#006BFF"),
    WorkspaceSidebarProjectColorPreset(name: "Red", hex: "#E5484D"),
    WorkspaceSidebarProjectColorPreset(name: "Amber", hex: "#FFAE00"),
    WorkspaceSidebarProjectColorPreset(name: "Green", hex: "#28A948"),
    WorkspaceSidebarProjectColorPreset(name: "Teal", hex: "#00AC96"),
    WorkspaceSidebarProjectColorPreset(name: "Purple", hex: "#A000F8"),
    WorkspaceSidebarProjectColorPreset(name: "Pink", hex: "#F22782"),
]
