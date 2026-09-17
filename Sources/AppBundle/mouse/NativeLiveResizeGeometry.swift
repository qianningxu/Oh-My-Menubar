import AppKit

enum NativeLiveResizeFrameWriteOrder: Equatable {
    case positionThenSize
    case sizeThenPosition
}

func nativeLiveResizeFrameWriteOrder(from current: Rect?, to requested: Rect) -> NativeLiveResizeFrameWriteOrder {
    guard let current else { return .positionThenSize }
    return requested.topLeftX < current.topLeftX || requested.topLeftY < current.topLeftY
        ? .positionThenSize
        : .sizeThenPosition
}

func nativeWindowSizeChangedForResize(from before: Rect, to after: Rect) -> Bool {
    abs(before.width - after.width) >= 1 || abs(before.height - after.height) >= 1
}

func learnedMinimumSizeAfterNativeClamp(
    current: CGSize?,
    requested: CGSize,
    observed: CGSize,
    tolerance: CGFloat
) -> CGSize? {
    var minimum = current ?? .zero
    var changed = false
    if observed.width > requested.width + tolerance, observed.width > minimum.width {
        minimum.width = observed.width
        changed = true
    }
    if observed.height > requested.height + tolerance, observed.height > minimum.height {
        minimum.height = observed.height
        changed = true
    }
    return changed ? minimum : nil
}

func nativeLiveResizeFramesMatch(_ lhs: Rect, _ rhs: Rect, tolerance: CGFloat) -> Bool {
    abs(lhs.topLeftX - rhs.topLeftX) < tolerance &&
        abs(lhs.topLeftY - rhs.topLeftY) < tolerance &&
        abs(lhs.width - rhs.width) < tolerance &&
        abs(lhs.height - rhs.height) < tolerance
}

func nativeLiveResizeClampIsConfirmed(
    initial: Rect?,
    requested: Rect,
    previous: Rect?,
    observed: Rect,
    tolerance: CGFloat
) -> Bool {
    guard let initial, let previous else { return false }
    let widthClamp = observed.width > requested.width + tolerance &&
        (abs(requested.minX - observed.minX) < tolerance ||
            abs(requested.maxX - observed.maxX) < tolerance)
    let heightClamp = observed.height > requested.height + tolerance &&
        (abs(requested.minY - observed.minY) < tolerance ||
            abs(requested.maxY - observed.maxY) < tolerance)
    return (widthClamp || heightClamp) &&
        nativeLiveResizeFramesMatch(previous, observed, tolerance: tolerance) &&
        !nativeLiveResizeFramesMatch(initial, observed, tolerance: tolerance)
}

@MainActor
func liveResizeWindowContentRect(groupRect: Rect, isTabGroup: Bool) -> Rect {
    guard isTabGroup else { return groupRect }
    let side = windowTabGroupShellHorizontalInset()
    let top = resolvedWindowTabBarHeight() + windowTabGroupShellTopInset()
    return Rect(
        topLeftX: groupRect.topLeftX + side,
        topLeftY: groupRect.topLeftY + top,
        width: max(groupRect.width - side * 2, 0),
        height: max(groupRect.height - top - windowTabGroupShellBottomInset(), 0))
}
