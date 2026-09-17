import AppKit
import Common
import SwiftUI

// MARK: - Constants

let windowTabPreviewCornerRadius: CGFloat = 14
let windowTabStripContentPaddingValue: CGFloat = WinMuxSpacing.hairline / 2
let windowTabStripContentHorizontalPadding: CGFloat = windowTabStripContentPaddingValue
let windowTabStripGroupHandleWidth: CGFloat = 26
let windowTabStripReservedHandleWidth: CGFloat = WinMuxSpacing.none
let windowTabStripTrailingGroupDragGutterWidth: CGFloat = 0
let windowTabStripCornerRadius: CGFloat = WinMuxBarStyle.cornerRadius
let windowTabStripInnerCornerRadius: CGFloat = 9
let windowTabStripTabSpacing: CGFloat = WinMuxSpacing.hairline
let windowTabStripPreferredTabWidth: CGFloat = WinMuxBarStyle.maximumTabWidth
let windowTabStripCloseButtonSize: CGFloat = 18
let windowTabStripCloseButtonReservedWidth: CGFloat = 22
let windowTabStripCloseButtonTrailingInset: CGFloat = standardGap * 2.5
let windowTabStripScrollFadeWidth: CGFloat = 22
let windowTabStripAutoScrollEdgeWidth: CGFloat = 28
let windowTabStripAutoScrollDuration: TimeInterval = 0.12
let windowTabStripScrollOriginTolerance: CGFloat = 0.5
let windowTabStripGroupDragMinimumDistance: CGFloat = WinMuxSpacing.regular
let windowTabReorderMinimumDistance: CGFloat = WinMuxSpacing.regular
let windowTabGroupFrameStrokeWidth: CGFloat = 0.5
let windowTabGroupFrameInnerStrokeWidth: CGFloat = 0.5
let windowTabGroupFrameMaxInnerCornerRadius: CGFloat = 22
let windowTabGroupFrameMaxTopInnerCornerRadius: CGFloat = 40
let windowTabGroupCornerShieldOverreach: CGFloat = 7
let windowTabPillAnimation: Animation = .spring(response: 0.28, dampingFraction: 0.72, blendDuration: 0.08)
let windowTabReducedMotionAnimation: Animation = .easeOut(duration: 0.12)

func windowTabStripContentPadding() -> CGFloat {
    windowTabStripContentHorizontalPadding
}

func windowTabStripReservedGroupHandleWidth() -> CGFloat {
    windowTabStripReservedHandleWidth
}

func windowTabStripScrollViewportWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        stripWidth
            - windowTabStripTrailingGroupDragGutterWidth,
    )
}

func windowTabStripTabWidth(stripWidth: CGFloat, count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return max(0, windowTabStripAvailableTabsWidth(stripWidth: stripWidth)
        - CGFloat(count - 1) * windowTabStripTabSpacing) / CGFloat(count)
}

func windowTabStripAvailableTabsWidth(stripWidth: CGFloat) -> CGFloat {
    max(
        0,
        windowTabStripScrollViewportWidth(stripWidth: stripWidth)
            - (windowTabStripContentHorizontalPadding * 2),
    )
}

func windowTabResolvedScrollFadeWidth(stripWidth: CGFloat) -> CGFloat {
    min(windowTabStripScrollFadeWidth, max(stripWidth / 5, 0))
}

func windowTabLeadingScrollFadeWidth(
    isScrollable: Bool,
    contentMinX: CGFloat,
    stripWidth: CGFloat,
) -> CGFloat {
    let firstTabMinX = contentMinX + windowTabStripContentHorizontalPadding
    guard isScrollable, firstTabMinX < -windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

func windowTabTrailingScrollFadeWidth(
    isScrollable: Bool,
    contentMaxX: CGFloat,
    viewportWidth: CGFloat,
    stripWidth: CGFloat,
) -> CGFloat {
    let lastTabMaxX = contentMaxX - windowTabStripContentHorizontalPadding
    guard isScrollable, lastTabMaxX > viewportWidth + windowTabStripScrollOriginTolerance else { return 0 }
    return windowTabResolvedScrollFadeWidth(stripWidth: stripWidth)
}

// MARK: - Tab Strip View (manages reorder drag state for all tabs)

let tabReorderVerticalEscapeThreshold: CGFloat = 18

enum WindowTabAutoScrollDirection: Equatable {
    case leading
    case trailing

    var anchor: UnitPoint {
        switch self {
            case .leading: .leading
            case .trailing: .trailing
        }
    }
}

func windowTabAutoScrollDirection(
    pointerXInViewport: CGFloat,
    viewportWidth: CGFloat,
    isScrollable: Bool,
) -> WindowTabAutoScrollDirection? {
    guard isScrollable, viewportWidth > 0 else { return nil }
    if pointerXInViewport <= windowTabStripAutoScrollEdgeWidth { return .leading }
    if pointerXInViewport >= viewportWidth - windowTabStripAutoScrollEdgeWidth { return .trailing }
    return nil
}
