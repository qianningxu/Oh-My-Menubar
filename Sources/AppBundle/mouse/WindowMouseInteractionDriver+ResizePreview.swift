import AppKit
import CoreGraphics

struct ResizePointerBounds: Equatable {
    var minX: CGFloat?
    var maxX: CGFloat?
    var minY: CGFloat?
    var maxY: CGFloat?

    static let unconstrained = ResizePointerBounds()
}

func constrainResizePointer(_ point: CGPoint, to bounds: ResizePointerBounds) -> CGPoint {
    var point = point
    if let minX = bounds.minX { point.x = max(point.x, minX) }
    if let maxX = bounds.maxX { point.x = min(point.x, maxX) }
    if let minY = bounds.minY { point.y = max(point.y, minY) }
    if let maxY = bounds.maxY { point.y = min(point.y, maxY) }
    return point
}

struct ResizePointerGateState {
    var session: UInt64?
    var windowId: UInt32?
    var expiresAt: TimeInterval = 0
    var bounds = ResizePointerBounds.unconstrained

    mutating func constrain(_ point: CGPoint, now: TimeInterval) -> CGPoint {
        guard session != nil, windowId != nil, now < expiresAt else {
            self = ResizePointerGateState()
            return point
        }
        return constrainResizePointer(point, to: bounds)
    }
}

final class ResizePointerConstraintGate: @unchecked Sendable {
    static let shared = ResizePointerConstraintGate()
    private let lock = NSLock()
    private var state = ResizePointerGateState()
    private var points: (raw: CGPoint?, constrained: CGPoint?) = (nil, nil)

    var sample: (raw: CGPoint?, constrained: CGPoint?) {
        lock.lock()
        defer { lock.unlock() }
        return points
    }

    func replace(with bounds: ResizePointerBounds, session: UInt64, windowId: UInt32) {
        lock.lock()
        state = ResizePointerGateState(session: session, windowId: windowId,
            expiresAt: ProcessInfo.processInfo.systemUptime + 0.5, bounds: bounds)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        state = ResizePointerGateState()
        lock.unlock()
    }

    func constrain(_ point: CGPoint) -> CGPoint {
        lock.lock()
        defer { lock.unlock() }
        let result = state.constrain(point, now: ProcessInfo.processInfo.systemUptime)
        points = (point, result)
        return result
    }
}

private let resizePointerEventTapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            ResizePointerConstraintGate.shared.clear()
            DispatchQueue.main.async {
                ResizePointerEventTapController.shared.enable()
            }
        case .leftMouseDragged:
            event.location = ResizePointerConstraintGate.shared.constrain(event.location)
        case .leftMouseDown, .leftMouseUp:
            ResizePointerConstraintGate.shared.clear()
        default:
            break
    }
    return Unmanaged.passUnretained(event)
}

@MainActor
final class ResizePointerEventTapController {
    static let shared = ResizePointerEventTapController()

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    private init() {}

    func install() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseDragged.rawValue) |
            CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: resizePointerEventTapCallback,
            userInfo: nil
        ) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func enable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }
}

extension WindowMouseInteractionDriver {
    func beginStableResizePreviewFrame(for window: Window) {
        guard let workspace = window.nodeWorkspace else { return }
        WindowResizePreviewPanel.shared.beginStableFrame(workspace.workspaceMonitor.rect.toAppKitScreenRect)
    }

    func updateResizePreviewIfNeeded(window: Window, rect: Rect, force: Bool = false) {
        guard force || resizePreviewHasVisibleChange(from: lastRenderedResizePreviewRect, to: rect) else { return }
        lastRenderedResizePreviewRect = rect
        updateCompositedResizePreview(window, rect: rect)
    }

    func constrainResizePointerIfNeeded(from proposed: Rect, to bounded: Rect) {
        guard resizePreviewHasVisibleChange(from: proposed, to: bounded),
              let session = resizeSession,
              let gesture = resizeGesture,
              gesture.windowId == session.windowId
        else { return }
        let sample = MousePointerTracker.shared.currentSample
        let point = gesture.pointerPoint(constrainingTo: bounded, current: sample.point)
        guard abs(point.x - sample.point.x) >= resizePreviewVisibleChangeThreshold ||
            abs(point.y - sample.point.y) >= resizePreviewVisibleChangeThreshold
        else { return }
        CGWarpMouseCursorPosition(point)
        MousePointerTracker.shared.note(point: point, timestamp: sample.timestamp)
    }

    func refreshResizePointerConstraints(window: Window) {
        guard let session = resizeSession,
              session.windowId == window.windowId,
              let gesture = resizeGesture,
              gesture.windowId == session.windowId
        else {
            ResizePointerConstraintGate.shared.clear()
            return
        }

        let sample = MousePointerTracker.shared.currentSample
        let extreme = CGFloat(1_000_000)
        var bounds = ResizePointerBounds.unconstrained

        func resolvedPointer(for point: CGPoint) -> CGPoint? {
            let proposed = gesture.predictedRect(mouse: point)
            guard let bounded = resizeProposal(window, rect: proposed)?.rect,
                  resizePreviewHasVisibleChange(from: proposed, to: bounded)
            else { return nil }
            return gesture.pointerPoint(constrainingTo: bounded, current: point)
        }

        if gesture.edges.left || gesture.edges.right {
            bounds.minX = resolvedPointer(for: CGPoint(x: -extreme, y: sample.point.y))?.x
            bounds.maxX = resolvedPointer(for: CGPoint(x: extreme, y: sample.point.y))?.x
        }
        if gesture.edges.up || gesture.edges.down {
            bounds.minY = resolvedPointer(for: CGPoint(x: sample.point.x, y: -extreme))?.y
            bounds.maxY = resolvedPointer(for: CGPoint(x: sample.point.x, y: extreme))?.y
        }

        if let minX = bounds.minX, let maxX = bounds.maxX, minX > maxX {
            let midpoint = (minX + maxX) / 2
            bounds.minX = midpoint
            bounds.maxX = midpoint
        }
        if let minY = bounds.minY, let maxY = bounds.maxY, minY > maxY {
            let midpoint = (minY + maxY) / 2
            bounds.minY = midpoint
            bounds.maxY = midpoint
        }
        ResizePointerConstraintGate.shared.replace(with: bounds, session: liveResizeFrameWriteGeneration, windowId: session.windowId)
    }

    func clearResizePointerConstraints() {
        ResizePointerConstraintGate.shared.clear()
    }
}

func resizePreviewHasVisibleChange(from previous: Rect?, to next: Rect) -> Bool {
    guard let previous else { return true }
    return abs(previous.topLeftX - next.topLeftX) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.topLeftY - next.topLeftY) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.width - next.width) >= resizePreviewVisibleChangeThreshold ||
        abs(previous.height - next.height) >= resizePreviewVisibleChangeThreshold
}
