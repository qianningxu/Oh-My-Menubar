import AppKit
import Common

let resizeGestureCalibrationInterval: TimeInterval = 1.0 / 30.0
let resizePreviewVisibleChangeThreshold = CGFloat(0.5)

@MainActor
final class WindowMouseInteractionDriver {
    static let shared = WindowMouseInteractionDriver()

    struct MoveSession: Equatable {
        let windowId: UInt32
        let subject: WindowDragSubject
        let detachOrigin: TabDetachOrigin
        let startedInSidebar: Bool
    }

    struct ResizeSession: Equatable {
        let windowId: UInt32
        let token = UUID()
    }

    struct PendingResizeCandidate {
        let windowId: UInt32
        let baseRect: Rect
        let observedRect: Rect
        let edges: ResizeGestureEdges
        let mouseSample: MousePointerSample
    }

    struct DragSourcePreviewState {
        let windowId: UInt32
        let subject: WindowDragSubject
        let anchorRect: Rect
        let mouseOffset: CGPoint
    }

    var moveSession: MoveSession?
    var resizeSession: ResizeSession?
    var dragSourcePreviewState: DragSourcePreviewState?
    var pendingResizeCandidate: PendingResizeCandidate?
    var resizeGesture: ResizeGestureSessionState?
    var flushingResizeSession: ResizeSession?
    var isResizeSampleInFlight = false
    var isMouseUpResetScheduled = false
    var lastRenderedResizePreviewRect: Rect?
    var pendingLiveResizeFrames: [UInt32: Rect] = [:]
    var liveResizeFramesInFlight: [UInt32: Rect] = [:]
    var liveResizeFrameWriteGeneration: UInt64 = 0

    private init() {}
}
