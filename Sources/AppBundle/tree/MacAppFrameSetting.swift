import AppKit

func setFrame(_ window: AXUIElement, _ topLeft: CGPoint?, _ size: CGSize?, _ job: RunLoopJob) throws {
    let currentTopLeft: CGPoint? = topLeft == nil ? nil : window.get(Ax.topLeftCornerAttr)
    let currentSize: CGSize? = size == nil ? nil : window.get(Ax.sizeAttr)
    let positionMatches = topLeft == nil || currentTopLeft == topLeft
    let sizeMatches = size == nil || currentSize == size
    if positionMatches && sizeMatches {
        return
    }
    if let size { window.set(Ax.sizeAttr, size) }
    try job.checkCancellation()
    if let topLeft { window.set(Ax.topLeftCornerAttr, topLeft) } else { return }
    try job.checkCancellation()
    if let size { window.set(Ax.sizeAttr, size) }
}

/// Live resizing favors continuous coverage at the moving leading edge and
/// completes both AX writes once started. A newer frame may replace a queued
/// job, but it must not cancel an already half-applied position/size pair.
func setLiveResizeFrame(_ window: AXUIElement, from current: Rect?, to requested: Rect) -> Rect? {
    switch nativeLiveResizeFrameWriteOrder(from: current, to: requested) {
        case .positionThenSize:
            window.set(Ax.topLeftCornerAttr, requested.topLeftCorner)
            window.set(Ax.sizeAttr, requested.size)
        case .sizeThenPosition:
            window.set(Ax.sizeAttr, requested.size)
            window.set(Ax.topLeftCornerAttr, requested.topLeftCorner)
    }
    guard let topLeft: CGPoint = window.get(Ax.topLeftCornerAttr),
          let size: CGSize = window.get(Ax.sizeAttr)
    else { return nil }
    return Rect(topLeftX: topLeft.x, topLeftY: topLeft.y, width: size.width, height: size.height)
}

func disableAnimations<T>(app: AXUIElement, _ job: RunLoopJob, _ body: () throws -> T) throws -> T {
    let wasEnabled = app.get(Ax.enhancedUserInterfaceAttr) == true
    if wasEnabled {
        app.set(Ax.enhancedUserInterfaceAttr, false)
    }
    defer {
        if wasEnabled {
            app.set(Ax.enhancedUserInterfaceAttr, true)
        }
    }
    try job.checkCancellation()
    return try body()
}
