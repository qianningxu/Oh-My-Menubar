import AppKit
import SwiftUI

/// Complete one sibling's layout transition before the presentation clock can
/// advance to the next insertion slot. A short deterministic curve avoids the
/// overlapping springs that made two rows appear to move as one jump.
let workspaceSidebarWorkspacePreviewTransitionDuration: TimeInterval = 0.040
let workspaceSidebarWorkspaceReorderAnimation = Animation.easeInOut(
    duration: workspaceSidebarWorkspacePreviewTransitionDuration
)

/// Keep each insertion slot on screen long enough for SwiftUI to render a
/// the full row transition plus a small rendered hold before the next sibling
/// is released. The first step remains immediate, and 50 ms keeps queued
/// catch-up perceptibly closer to the mouse than the previous 60 ms spring.
let workspaceSidebarWorkspacePreviewStepInterval: TimeInterval = 0.050

struct WorkspaceSidebarWorkspaceReorderFrame: Equatable {
    let workspaceName: String
    let projectId: WorkspaceProjectId
    let frame: CGRect
    let isReorderable: Bool
}

struct WorkspaceSidebarFolderReorderFrame: Equatable {
    let projectId: WorkspaceProjectId
    let frame: CGRect
    let isDropTarget: Bool
}

struct WorkspaceSidebarFolderReorderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceSidebarFolderReorderFrame] = []

    static func reduce(
        value: inout [WorkspaceSidebarFolderReorderFrame],
        nextValue: () -> [WorkspaceSidebarFolderReorderFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct WorkspaceSidebarWorkspaceReorderFramePreferenceKey: PreferenceKey {
    static let defaultValue: [WorkspaceSidebarWorkspaceReorderFrame] = []

    static func reduce(
        value: inout [WorkspaceSidebarWorkspaceReorderFrame],
        nextValue: () -> [WorkspaceSidebarWorkspaceReorderFrame]
    ) {
        value.append(contentsOf: nextValue())
    }
}

struct WorkspaceSidebarWorkspaceReorderTarget: Equatable {
    let projectId: WorkspaceProjectId
    let targetWorkspaceName: String
    let placement: WorkspaceReorderPlacement
}

struct WorkspaceSidebarWorkspaceFolderTarget: Equatable {
    let projectId: WorkspaceProjectId
    let sourceWorkspaceName: String
}

enum WorkspaceSidebarWorkspaceDragTarget: Equatable {
    case reorder(WorkspaceSidebarWorkspaceReorderTarget)
    case moveToFolder(WorkspaceSidebarWorkspaceFolderTarget)
}

enum WorkspaceSidebarFolderReorderPlacement: Equatable {
    case before(WorkspaceProjectId)
    case after(WorkspaceProjectId)

    var targetProjectId: WorkspaceProjectId {
        switch self {
            case .before(let projectId), .after(let projectId):
                projectId
        }
    }
}

struct WorkspaceSidebarFolderReorderTarget: Equatable {
    let targetProjectId: WorkspaceProjectId
    let placement: WorkspaceSidebarFolderReorderPlacement
}

func workspaceSidebarWorkspaceDragFinishAction(
    sourceWorkspaceName: String,
    target: WorkspaceSidebarWorkspaceDragTarget
) -> WorkspaceSidebarAction? {
    switch target {
        case .reorder(let reorderTarget):
            return .reorderWorkspace(
                sourceWorkspaceName,
                folderId: WorkspaceFolderId(reorderTarget.projectId),
                placement: reorderTarget.placement
            )
        case .moveToFolder(let folderTarget):
            guard folderTarget.sourceWorkspaceName == sourceWorkspaceName else { return nil }
            return .moveWorkspaceToFolder(
                folderTarget.sourceWorkspaceName,
                folderId: WorkspaceFolderId(folderTarget.projectId)
            )
    }
}

struct WorkspaceSidebarWorkspaceReorderDragState: Equatable {
    let sourceWorkspaceName: String
    let projectId: WorkspaceProjectId
    var target: WorkspaceSidebarWorkspaceDragTarget?
    /// Unlike `target`, this is never cleared by a single missed geometry
    /// sample. It is the slot we commit if mouse-up happens inside the sidebar.
    var lastValidTarget: WorkspaceSidebarWorkspaceDragTarget? = nil
    /// Native drag events can cross several rows between rendered frames. The
    /// exact pointer target above remains immediate, while this deadline gates
    /// only the next visual insertion-slot step.
    var nextPreviewStepAt: TimeInterval? = nil
    /// Both the global mouse observer and SwiftUI's DragGesture can report the
    /// same mouse-up. Commit exactly once so the final model refresh cannot
    /// briefly replay the reorder.
    var isCommitting: Bool = false
}

func workspaceSidebarWorkspaceDragTargetProjectId(
    _ target: WorkspaceSidebarWorkspaceDragTarget?
) -> WorkspaceProjectId? {
    switch target {
        case .reorder(let reorderTarget): reorderTarget.projectId
        case .moveToFolder(let folderTarget): folderTarget.projectId
        case nil: nil
    }
}

func workspaceSidebarWorkspaceInteractionProjectId(
    _ drag: WorkspaceSidebarWorkspaceReorderDragState?
) -> WorkspaceProjectId? {
    workspaceSidebarWorkspaceDragTargetProjectId(drag?.lastValidTarget ?? drag?.target)
}

/// A reorder target is deliberately sticky while the pointer remains in the
/// sidebar. SwiftUI is animating the preview rows while the pointer is moving,
/// so a single transient frame miss must not erase the last concrete slot.
/// Leaving the sidebar is the one explicit way to clear the sidebar target and
/// enable a canvas drop instead.
func workspaceSidebarStableWorkspaceDragTarget(
    currentTarget: WorkspaceSidebarWorkspaceDragTarget?,
    candidateTarget: WorkspaceSidebarWorkspaceDragTarget?,
    isPointerInsideSidebar: Bool
) -> WorkspaceSidebarWorkspaceDragTarget? {
    guard isPointerInsideSidebar else { return candidateTarget }
    return candidateTarget ?? currentTarget
}

private struct WorkspaceSidebarWorkspaceInsertionSlot: Equatable {
    let projectId: WorkspaceProjectId
    let insertionIndex: Int
    let previewTarget: WorkspaceSidebarWorkspaceDragTarget?
}

/// Build every visible insertion slot in vertical order. The source's original
/// position is represented by a nil preview target, while the terminal slot of
/// one folder and the first slot of the next remain distinct. This gives the
/// preview a deterministic ladder that cannot omit a sibling when pointer
/// events arrive faster than SwiftUI can render them.
private func workspaceSidebarWorkspaceInsertionSlots(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarWorkspaceReorderFrame],
    folderFrames: [WorkspaceSidebarFolderReorderFrame]
) -> [WorkspaceSidebarWorkspaceInsertionSlot] {
    let reorderableFrames = frames.filter(\.isReorderable)
    let visibleDestinationProjectIds = Set(
        folderFrames.lazy.filter(\.isDropTarget).map(\.projectId)
    )
    let includesEveryFramedProject = folderFrames.isEmpty
    let projectIds = Set(reorderableFrames.map(\.projectId))
        .union(visibleDestinationProjectIds)
        .filter {
            $0 == sourceProjectId ||
                includesEveryFramedProject ||
                visibleDestinationProjectIds.contains($0)
        }

    func projectMinimumY(_ projectId: WorkspaceProjectId) -> CGFloat {
        let folderMinimumY = folderFrames
            .filter { $0.projectId == projectId }
            .map(\.frame.minY)
            .min()
        let workspaceMinimumY = reorderableFrames
            .filter { $0.projectId == projectId }
            .map(\.frame.minY)
            .min()
        return folderMinimumY ?? workspaceMinimumY ?? .greatestFiniteMagnitude
    }

    let orderedProjectIds = projectIds.sorted {
        let leftY = projectMinimumY($0)
        let rightY = projectMinimumY($1)
        if leftY != rightY { return leftY < rightY }
        return $0.rawValue < $1.rawValue
    }

    return orderedProjectIds.flatMap { projectId -> [WorkspaceSidebarWorkspaceInsertionSlot] in
        let projectFrames = reorderableFrames
            .filter { $0.projectId == projectId }
            .sorted { $0.frame.midY < $1.frame.midY }
        let sourceIndex = projectId == sourceProjectId
            ? projectFrames.firstIndex(where: { $0.workspaceName == sourceWorkspaceName })
            : nil
        let remainingFrames = projectFrames.filter {
            projectId != sourceProjectId || $0.workspaceName != sourceWorkspaceName
        }

        return (0 ... remainingFrames.count).map { insertionIndex in
            let previewTarget: WorkspaceSidebarWorkspaceDragTarget?
            if projectId == sourceProjectId, insertionIndex == sourceIndex {
                previewTarget = nil
            } else if remainingFrames.isEmpty {
                previewTarget = projectId == sourceProjectId
                    ? nil
                    : .moveToFolder(WorkspaceSidebarWorkspaceFolderTarget(
                        projectId: projectId,
                        sourceWorkspaceName: sourceWorkspaceName
                    ))
            } else {
                let targetFrame = insertionIndex == 0
                    ? remainingFrames[0]
                    : remainingFrames[insertionIndex - 1]
                previewTarget = .reorder(WorkspaceSidebarWorkspaceReorderTarget(
                    projectId: projectId,
                    targetWorkspaceName: targetFrame.workspaceName,
                    placement: insertionIndex == 0
                        ? .before(targetFrame.workspaceName)
                        : .after(targetFrame.workspaceName)
                ))
            }
            return WorkspaceSidebarWorkspaceInsertionSlot(
                projectId: projectId,
                insertionIndex: insertionIndex,
                previewTarget: previewTarget
            )
        }
    }
}

private func workspaceSidebarWorkspaceInsertionSlotIndex(
    target: WorkspaceSidebarWorkspaceDragTarget?,
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarWorkspaceReorderFrame],
    slots: [WorkspaceSidebarWorkspaceInsertionSlot]
) -> Int? {
    guard let target else {
        return slots.firstIndex {
            $0.projectId == sourceProjectId && $0.previewTarget == nil
        }
    }

    let projectId: WorkspaceProjectId
    let insertionIndex: Int
    switch target {
        case .moveToFolder(let folderTarget):
            projectId = folderTarget.projectId
            insertionIndex = frames.filter {
                $0.isReorderable &&
                    $0.projectId == projectId &&
                    $0.workspaceName != sourceWorkspaceName
            }.count
        case .reorder(let reorderTarget):
            projectId = reorderTarget.projectId
            let remainingFrames = frames
                .filter {
                    $0.isReorderable &&
                        $0.projectId == projectId &&
                        (projectId != sourceProjectId || $0.workspaceName != sourceWorkspaceName)
                }
                .sorted { $0.frame.midY < $1.frame.midY }
            guard let targetIndex = remainingFrames.firstIndex(where: {
                $0.workspaceName == reorderTarget.targetWorkspaceName
            }) else { return nil }
            insertionIndex = switch reorderTarget.placement {
                case .before: targetIndex
                case .after: targetIndex + 1
            }
    }

    return slots.firstIndex {
        $0.projectId == projectId && $0.insertionIndex == insertionIndex
    }
}

/// Advance the visual placeholder by exactly one adjacent insertion slot.
/// The exact pointer target is kept separately and is still used for mouse-up,
/// so a fast release remains precise even while the preview is catching up.
func workspaceSidebarWorkspaceAdjacentPreviewTarget(
    currentTarget: WorkspaceSidebarWorkspaceDragTarget?,
    desiredTarget: WorkspaceSidebarWorkspaceDragTarget?,
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarWorkspaceReorderFrame],
    folderFrames: [WorkspaceSidebarFolderReorderFrame] = []
) -> WorkspaceSidebarWorkspaceDragTarget? {
    let slots = workspaceSidebarWorkspaceInsertionSlots(
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        folderFrames: folderFrames
    )
    guard let currentIndex = workspaceSidebarWorkspaceInsertionSlotIndex(
        target: currentTarget,
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        slots: slots
    ), let desiredIndex = workspaceSidebarWorkspaceInsertionSlotIndex(
        target: desiredTarget,
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        slots: slots
    ) else { return desiredTarget }
    guard currentIndex != desiredIndex else { return slots[currentIndex].previewTarget }
    let nextIndex = currentIndex + (desiredIndex > currentIndex ? 1 : -1)
    return slots[nextIndex].previewTarget
}

struct WorkspaceSidebarWorkspacePacedPreviewResolution: Equatable {
    let target: WorkspaceSidebarWorkspaceDragTarget?
    let nextPreviewStepAt: TimeInterval?
}

/// Advance at most one slot and hold that slot for a short render window. This
/// prevents multiple correct state transitions from being visually coalesced
/// into one jump while keeping the exact mouse-up target completely unpaced.
func workspaceSidebarWorkspacePacedPreviewResolution(
    currentTarget: WorkspaceSidebarWorkspaceDragTarget?,
    desiredTarget: WorkspaceSidebarWorkspaceDragTarget?,
    nextPreviewStepAt: TimeInterval?,
    now: TimeInterval,
    stepInterval: TimeInterval = workspaceSidebarWorkspacePreviewStepInterval,
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarWorkspaceReorderFrame],
    folderFrames: [WorkspaceSidebarFolderReorderFrame] = []
) -> WorkspaceSidebarWorkspacePacedPreviewResolution {
    let slots = workspaceSidebarWorkspaceInsertionSlots(
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        folderFrames: folderFrames
    )
    guard let currentIndex = workspaceSidebarWorkspaceInsertionSlotIndex(
        target: currentTarget,
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        slots: slots
    ), let desiredIndex = workspaceSidebarWorkspaceInsertionSlotIndex(
        target: desiredTarget,
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        frames: frames,
        slots: slots
    ) else {
        return WorkspaceSidebarWorkspacePacedPreviewResolution(
            target: desiredTarget,
            nextPreviewStepAt: now + stepInterval
        )
    }

    if currentIndex == desiredIndex {
        let retainedDeadline = nextPreviewStepAt.flatMap { now < $0 ? $0 : nil }
        return WorkspaceSidebarWorkspacePacedPreviewResolution(
            target: slots[currentIndex].previewTarget,
            nextPreviewStepAt: retainedDeadline
        )
    }
    if let nextPreviewStepAt, now < nextPreviewStepAt {
        return WorkspaceSidebarWorkspacePacedPreviewResolution(
            target: slots[currentIndex].previewTarget,
            nextPreviewStepAt: nextPreviewStepAt
        )
    }

    let nextIndex = currentIndex + (desiredIndex > currentIndex ? 1 : -1)
    return WorkspaceSidebarWorkspacePacedPreviewResolution(
        target: slots[nextIndex].previewTarget,
        nextPreviewStepAt: now + stepInterval
    )
}

/// Nil hit-test targets are intentional while the pointer is over the source's
/// original insertion band, but can also be transient misses elsewhere. Keep
/// those cases separate so returning to the source closes the preview while a
/// brief gap between folders does not snap it back.
func workspaceSidebarWorkspacePointerIsInSourceOriginalSlot(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarWorkspaceReorderFrame]
) -> Bool {
    let sourceFrames = frames
        .filter {
            $0.isReorderable &&
                $0.projectId == sourceProjectId &&
                workspaceSidebarPointerIsInsideWorkspaceReorderXBand(pointer, frame: $0.frame)
        }
        .sorted { $0.frame.midY < $1.frame.midY }
    guard let sourceIndex = sourceFrames.firstIndex(where: {
        $0.workspaceName == sourceWorkspaceName
    }) else { return false }

    let sourceFrame = sourceFrames[sourceIndex].frame
    let lowerBound = sourceIndex > 0
        ? (sourceFrames[sourceIndex - 1].frame.midY + sourceFrame.midY) / 2
        : sourceFrame.minY - sourceFrame.height / 2
    let upperBound = sourceIndex + 1 < sourceFrames.count
        ? (sourceFrame.midY + sourceFrames[sourceIndex + 1].frame.midY) / 2
        : sourceFrame.maxY + sourceFrame.height / 2
    return lowerBound <= pointer.y && pointer.y <= upperBound
}

/// Resolve mouse-up from the final frozen-frame hit first. This covers a very
/// fast drag where the display-link has not sampled the final pointer yet;
/// the last stable target remains the fallback for a transient frame miss.
func workspaceSidebarWorkspaceDragFinishTarget(
    finalCandidate: WorkspaceSidebarWorkspaceDragTarget?,
    lastValidTarget: WorkspaceSidebarWorkspaceDragTarget?,
    currentTarget: WorkspaceSidebarWorkspaceDragTarget?,
    hasCanvasDropIntent: Bool
) -> WorkspaceSidebarWorkspaceDragTarget? {
    guard !hasCanvasDropIntent else { return nil }
    return finalCandidate ?? lastValidTarget ?? currentTarget
}

struct WorkspaceSidebarFolderReorderDragState: Equatable {
    let sourceProjectId: WorkspaceProjectId
    var target: WorkspaceSidebarFolderReorderTarget?
}

@MainActor
final class WorkspaceSidebarWorkspaceReorderDriver: ObservableObject {
    private var session: WorkspaceSidebarWorkspaceReorderSession?
    private var onTick: (@MainActor () -> Void)?
    private var onPointer: (@MainActor (CGPoint) -> Void)?
    private var onFinish: (@MainActor () -> Void)?
    private var pointerEventMonitors: [Any] = []
    private(set) var latestPointer: CGPoint?

    var isTracking: Bool { session != nil }

    func isTracking(sourceWorkspaceName: String, projectId: WorkspaceProjectId) -> Bool {
        session == WorkspaceSidebarWorkspaceReorderSession(
            sourceWorkspaceName: sourceWorkspaceName,
            projectId: projectId
        )
    }

    func start(
        sourceWorkspaceName: String,
        projectId: WorkspaceProjectId,
        onTick: @escaping @MainActor () -> Void,
        onPointer: @escaping @MainActor (CGPoint) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.onTick = onTick
        self.onPointer = onPointer
        self.onFinish = onFinish
        let nextSession = WorkspaceSidebarWorkspaceReorderSession(
            sourceWorkspaceName: sourceWorkspaceName,
            projectId: projectId
        )
        guard session != nextSession else { return }
        latestPointer = nil
        session = nextSession
        startPointerEventMonitoring()
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.tick()
        }
    }

    func note(pointer: CGPoint) {
        latestPointer = pointer
    }

    func stop() {
        guard session != nil else { return }
        DisplayRefreshDriver.shared.remove(owner: self)
        stopPointerEventMonitoring()
        session = nil
        onTick = nil
        onPointer = nil
        onFinish = nil
    }

    /// SwiftUI can unmount the source row as soon as the first placeholder is
    /// projected. Continue consuming native drag events after that point so a
    /// compact sidebar row cannot be crossed between two display-link ticks.
    private func startPointerEventMonitoring() {
        stopPointerEventMonitoring()
        let handlePointerEvent: (NSEvent) -> Void = { [weak self] event in
            let timestamp = event.timestamp
            let point = normalizeAppKitScreenPoint(NSEvent.mouseLocation)
            Task { @MainActor [weak self] in
                guard let self, self.session != nil, isLeftMouseButtonDown else { return }
                MousePointerTracker.shared.note(point: point, timestamp: timestamp)
                self.onPointer?(point)
            }
        }
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseDragged,
            handler: handlePointerEvent
        ) {
            pointerEventMonitors.append(globalMonitor)
        }
        if let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseDragged,
            handler: { event in
                handlePointerEvent(event)
                return event
            }
        ) {
            pointerEventMonitors.append(localMonitor)
        }
    }

    private func stopPointerEventMonitoring() {
        for monitor in pointerEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        pointerEventMonitors.removeAll()
    }

    private func tick() {
        guard isLeftMouseButtonDown else {
            let finish = onFinish
            stop()
            finish?()
            return
        }
        onTick?()
    }
}

@MainActor
final class WorkspaceSidebarFolderReorderDriver: ObservableObject {
    private var sourceProjectId: WorkspaceProjectId?
    private var onTick: (@MainActor () -> Void)?
    private var onFinish: (@MainActor () -> Void)?
    private(set) var latestPointer: CGPoint?

    var isTracking: Bool { sourceProjectId != nil }

    func isTracking(sourceProjectId: WorkspaceProjectId) -> Bool {
        self.sourceProjectId == sourceProjectId
    }

    func start(
        sourceProjectId: WorkspaceProjectId,
        onTick: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.onTick = onTick
        self.onFinish = onFinish
        guard self.sourceProjectId != sourceProjectId else { return }
        latestPointer = nil
        self.sourceProjectId = sourceProjectId
        DisplayRefreshDriver.shared.add(owner: self) { [weak self] _ in
            self?.tick()
        }
    }

    func note(pointer: CGPoint) {
        latestPointer = pointer
    }

    func stop() {
        guard sourceProjectId != nil else { return }
        DisplayRefreshDriver.shared.remove(owner: self)
        sourceProjectId = nil
        onTick = nil
        onFinish = nil
    }

    private func tick() {
        guard isLeftMouseButtonDown else {
            let finish = onFinish
            stop()
            finish?()
            return
        }
        onTick?()
    }
}

private struct WorkspaceSidebarWorkspaceReorderSession: Equatable {
    let sourceWorkspaceName: String
    let projectId: WorkspaceProjectId
}

enum WorkspaceSidebarWorkspaceReorderPreviewPlacement: Equatable {
    case before(String)
    case after(String)
    case intoFolder(WorkspaceProjectId)
}

enum WorkspaceSidebarWorkspaceListEntry: Identifiable, Equatable {
    case workspace(WorkspaceSidebarWorkspaceViewModel, isDragAnchor: Bool)
    case placeholder(WorkspaceSidebarWorkspaceViewModel, projectId: WorkspaceProjectId)

    var id: String {
        switch self {
            case .workspace(let workspace, _):
                return "workspace:\(workspace.name)"
            case .placeholder(let workspace, let projectId):
                return "placeholder:\(projectId.rawValue):\(workspace.name)"
        }
    }
}

enum WorkspaceSidebarFolderListEntry: Identifiable, Equatable {
    case folder(WorkspaceSidebarFolderSection, isDragAnchor: Bool)
    case placeholder(WorkspaceSidebarFolderSection)

    var id: String {
        switch self {
            case .folder(let section, _):
                return "folder:\(section.id.rawValue)"
            case .placeholder(let section):
                return "folder-placeholder:\(section.id.rawValue)"
        }
    }
}

func workspaceSidebarWorkspaceReorderIsEnabled(
    isCompact _: Bool,
    isSearchFiltering: Bool,
    isRenamingWorkspace: Bool,
    isPinnedActiveWorkspace: Bool,
    isInteractive: Bool
) -> Bool {
    !isSearchFiltering &&
        !isRenamingWorkspace &&
        !isPinnedActiveWorkspace &&
        isInteractive
}

func workspaceSidebarFolderReorderIsEnabled(
    projectId: WorkspaceProjectId,
    isCompact: Bool,
    isSearchFiltering: Bool,
    isRenamingWorkspace: Bool,
    isInteractive: Bool
) -> Bool {
    projectId != workspaceProjectDefaultId &&
        !isCompact &&
        !isSearchFiltering &&
        !isRenamingWorkspace &&
        isInteractive
}

func workspaceSidebarHeaderRowIsHighlighted(
    isSelected: Bool,
    isReorderSource: Bool
) -> Bool {
    isSelected || isReorderSource
}

func workspaceSidebarWorkspaceSourceIsProjectedDragAnchor(
    isSource: Bool,
    target: WorkspaceSidebarWorkspaceDragTarget?
) -> Bool {
    isSource && target != nil
}

func workspaceSidebarWorkspaceReorderTarget(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarWorkspaceReorderFrame],
    folderFrames: [WorkspaceSidebarFolderReorderFrame] = []
) -> WorkspaceSidebarWorkspaceReorderTarget? {
    let candidates = frames
        .filter {
            $0.isReorderable &&
                $0.workspaceName != sourceWorkspaceName &&
                workspaceSidebarWorkspaceReorderCandidateHasVisibleProjectFrame(
                    $0,
                    sourceProjectId: sourceProjectId,
                    folderFrames: folderFrames
                ) &&
                workspaceSidebarPointerIsInsideWorkspaceReorderXBand(pointer, frame: $0.frame)
        }
        .sorted { $0.frame.midY < $1.frame.midY }

    guard !candidates.isEmpty else { return nil }

    let sourceProjectFrames = frames
        .filter {
            $0.isReorderable &&
                $0.projectId == sourceProjectId &&
                workspaceSidebarPointerIsInsideWorkspaceReorderXBand(pointer, frame: $0.frame)
        }
        .sorted { $0.frame.midY < $1.frame.midY }
    guard let sourceIndex = sourceProjectFrames.firstIndex(where: {
        $0.workspaceName == sourceWorkspaceName
    }) else { return nil }
    let sourceFrame = sourceProjectFrames[sourceIndex]

    // A drag begins inside the source row. Treating that point as a nearby
    // target projects the source into the first/last slot before it has moved
    // over another row, which is especially visible when dragging the last
    // tab upward. Keep the original order until the pointer reaches a real
    // target row or a different insertion slot.
    guard !workspaceSidebarWorkspaceReorderFrameContains(sourceFrame.frame, pointer: pointer) else {
        return nil
    }

    if let containingCandidate = candidates.last(where: { workspaceSidebarWorkspaceReorderFrameContains($0.frame, pointer: pointer) }) {
        if containingCandidate.projectId != sourceProjectId {
            let placement: WorkspaceReorderPlacement = workspaceSidebarWorkspacePointerIsBeforeMidline(pointer, frame: containingCandidate.frame)
                ? .before(containingCandidate.workspaceName)
                : .after(containingCandidate.workspaceName)
            return WorkspaceSidebarWorkspaceReorderTarget(
                projectId: containingCandidate.projectId,
                targetWorkspaceName: containingCandidate.workspaceName,
                placement: placement
            )
        }
        guard let placement = workspaceSidebarWorkspaceReorderPlacement(
            sourceWorkspaceName: sourceWorkspaceName,
            sourceProjectId: sourceProjectId,
            targetWorkspaceName: containingCandidate.workspaceName,
            frames: frames
        ) else {
            return nil
        }
        return WorkspaceSidebarWorkspaceReorderTarget(
            projectId: containingCandidate.projectId,
            targetWorkspaceName: containingCandidate.workspaceName,
            placement: placement
        )
    }

    // Gaps next to the source are still its original position. Do not replace
    // the source with a placeholder there: that is a no-op that causes a
    // flash. Every other gap maps to the adjacent stable row.
    let insertionIndex = sourceProjectFrames.firstIndex(where: {
        pointer.y < $0.frame.midY
    }) ?? sourceProjectFrames.count
    let destinationIndex = insertionIndex > sourceIndex
        ? insertionIndex - 1
        : insertionIndex
    guard destinationIndex != sourceIndex else { return nil }

    let target = sourceProjectFrames[destinationIndex]
    return WorkspaceSidebarWorkspaceReorderTarget(
        projectId: sourceProjectId,
        targetWorkspaceName: target.workspaceName,
        placement: destinationIndex < sourceIndex
            ? .before(target.workspaceName)
            : .after(target.workspaceName)
    )
}

func workspaceSidebarWorkspaceReorderFramesForHitTesting(
    liveFrames: [WorkspaceSidebarWorkspaceReorderFrame],
    frozenFrames: [WorkspaceSidebarWorkspaceReorderFrame]
) -> [WorkspaceSidebarWorkspaceReorderFrame] {
    frozenFrames.isEmpty ? liveFrames : frozenFrames
}

func workspaceSidebarFolderReorderFramesForHitTesting(
    liveFrames: [WorkspaceSidebarFolderReorderFrame],
    frozenFrames: [WorkspaceSidebarFolderReorderFrame]
) -> [WorkspaceSidebarFolderReorderFrame] {
    frozenFrames.isEmpty ? liveFrames : frozenFrames
}

func workspaceSidebarFolderReorderFramesForInteraction(
    liveFrames: [WorkspaceSidebarFolderReorderFrame],
    frozenFrames: [WorkspaceSidebarFolderReorderFrame]
) -> [WorkspaceSidebarFolderReorderFrame] {
    liveFrames.isEmpty ? frozenFrames : liveFrames
}

func workspaceSidebarWorkspaceReorderFramesForInteraction(
    liveFrames: [WorkspaceSidebarWorkspaceReorderFrame],
    frozenFrames: [WorkspaceSidebarWorkspaceReorderFrame],
    destinationProjectId: WorkspaceProjectId?
) -> [WorkspaceSidebarWorkspaceReorderFrame] {
    guard !frozenFrames.isEmpty, let destinationProjectId else {
        return frozenFrames.isEmpty ? liveFrames : frozenFrames
    }
    let liveDestinationFrames = liveFrames.filter { $0.projectId == destinationProjectId }
    guard !liveDestinationFrames.isEmpty else { return frozenFrames }
    return frozenFrames.filter { $0.projectId != destinationProjectId } + liveDestinationFrames
}

func workspaceSidebarWorkspaceDragTarget(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    workspaceFrames: [WorkspaceSidebarWorkspaceReorderFrame],
    folderFrames: [WorkspaceSidebarFolderReorderFrame] = []
) -> WorkspaceSidebarWorkspaceDragTarget? {
    let isOverWorkspaceRow = workspaceSidebarPointerIsOverWorkspaceRow(
        sourceWorkspaceName: sourceWorkspaceName,
        pointer: pointer,
        frames: workspaceFrames
    )
    let folderTarget = workspaceSidebarWorkspaceFolderTarget(
        sourceWorkspaceName: sourceWorkspaceName,
        sourceProjectId: sourceProjectId,
        pointer: pointer,
        frames: folderFrames
    )
    if let folderTarget,
       let insertionTarget = workspaceSidebarWorkspaceInsertionTarget(
            sourceWorkspaceName: sourceWorkspaceName,
            sourceProjectId: sourceProjectId,
            targetProjectId: folderTarget.projectId,
            pointer: pointer,
            frames: workspaceFrames
       )
    {
        return .reorder(insertionTarget)
    }
    if let folderTarget, !isOverWorkspaceRow {
        return .moveToFolder(folderTarget)
    }
    let sourceProjectFrameExists = workspaceSidebarProjectFrameExists(projectId: sourceProjectId, frames: folderFrames)
    let isInsideSourceProjectFrame = workspaceSidebarProjectFrameContains(
        projectId: sourceProjectId,
        pointer: pointer,
        frames: folderFrames
    )
    if isOverWorkspaceRow || !sourceProjectFrameExists || isInsideSourceProjectFrame {
        if let reorderTarget = workspaceSidebarWorkspaceReorderTarget(
            sourceWorkspaceName: sourceWorkspaceName,
            sourceProjectId: sourceProjectId,
            pointer: pointer,
            frames: workspaceFrames,
            folderFrames: folderFrames
        ) {
            return .reorder(reorderTarget)
        }
    }
    if let folderTarget {
        return .moveToFolder(folderTarget)
    }
    return nil
}

private func workspaceSidebarWorkspaceInsertionTarget(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    targetProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarWorkspaceReorderFrame]
) -> WorkspaceSidebarWorkspaceReorderTarget? {
    let candidates = frames
        .filter {
            $0.isReorderable &&
                $0.projectId == targetProjectId &&
                $0.workspaceName != sourceWorkspaceName &&
                workspaceSidebarPointerIsInsideWorkspaceReorderXBand(pointer, frame: $0.frame)
        }
        .sorted { $0.frame.midY < $1.frame.midY }
    guard let last = candidates.last else { return nil }

    let target = candidates.first(where: { pointer.y < $0.frame.midY }) ?? last
    let placement: WorkspaceReorderPlacement
    if targetProjectId == sourceProjectId {
        guard let sameProjectPlacement = workspaceSidebarWorkspaceReorderPlacement(
            sourceWorkspaceName: sourceWorkspaceName,
            sourceProjectId: sourceProjectId,
            targetWorkspaceName: target.workspaceName,
            frames: frames
        ) else { return nil }
        placement = sameProjectPlacement
    } else if pointer.y < target.frame.midY {
        placement = .before(target.workspaceName)
    } else {
        placement = .after(target.workspaceName)
    }
    return WorkspaceSidebarWorkspaceReorderTarget(
        projectId: targetProjectId,
        targetWorkspaceName: target.workspaceName,
        placement: placement
    )
}

private func workspaceSidebarPointerIsOverWorkspaceRow(
    sourceWorkspaceName: String,
    pointer: CGPoint,
    frames: [WorkspaceSidebarWorkspaceReorderFrame]
) -> Bool {
    frames.contains {
        $0.isReorderable &&
            $0.workspaceName != sourceWorkspaceName &&
            workspaceSidebarWorkspaceReorderFrameContains($0.frame, pointer: pointer)
    }
}

func workspaceSidebarWorkspaceFolderTarget(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarFolderReorderFrame]
) -> WorkspaceSidebarWorkspaceFolderTarget? {
    guard let candidate = frames.last(where: {
        $0.isDropTarget &&
            $0.projectId != sourceProjectId &&
            $0.frame.contains(pointer)
    }) else { return nil }
    return WorkspaceSidebarWorkspaceFolderTarget(
        projectId: candidate.projectId,
        sourceWorkspaceName: sourceWorkspaceName
    )
}

func workspaceSidebarFolderReorderTarget(
    sourceProjectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarFolderReorderFrame]
) -> WorkspaceSidebarFolderReorderTarget? {
    let candidates = frames
        .filter {
            $0.isDropTarget &&
                $0.projectId != workspaceProjectDefaultId &&
                $0.projectId != sourceProjectId &&
                $0.frame.minX <= pointer.x &&
                pointer.x <= $0.frame.maxX
        }
        .sorted { $0.frame.midY < $1.frame.midY }

    guard !candidates.isEmpty else { return nil }

    if let containingCandidate = candidates.last(where: { $0.frame.contains(pointer) }) {
        let placement: WorkspaceSidebarFolderReorderPlacement =
            workspaceSidebarWorkspacePointerIsBeforeMidline(pointer, frame: containingCandidate.frame)
                ? .before(containingCandidate.projectId)
                : .after(containingCandidate.projectId)
        return WorkspaceSidebarFolderReorderTarget(
            targetProjectId: containingCandidate.projectId,
            placement: placement
        )
    }

    for candidate in candidates where pointer.y < candidate.frame.midY {
        return WorkspaceSidebarFolderReorderTarget(
            targetProjectId: candidate.projectId,
            placement: .before(candidate.projectId)
        )
    }

    guard let last = candidates.last else { return nil }
    return WorkspaceSidebarFolderReorderTarget(
        targetProjectId: last.projectId,
        placement: .after(last.projectId)
    )
}

func workspaceSidebarWorkspaceReorderPreviewPlacement(
    sourceWorkspaceName: String,
    target: WorkspaceSidebarWorkspaceDragTarget?
) -> WorkspaceSidebarWorkspaceReorderPreviewPlacement? {
    guard let target else { return nil }
    switch target {
        case .reorder(let reorderTarget):
            switch reorderTarget.placement {
                case .before(let workspaceName):
                    guard workspaceName != sourceWorkspaceName else { return nil }
                    return .before(workspaceName)
                case .after(let workspaceName):
                    guard workspaceName != sourceWorkspaceName else { return nil }
                    return .after(workspaceName)
            }
        case .moveToFolder(let folderTarget):
            guard folderTarget.sourceWorkspaceName == sourceWorkspaceName else { return nil }
            return .intoFolder(folderTarget.projectId)
    }
}

func workspaceSidebarWorkspaceListEntries(
    workspaces: [WorkspaceSidebarWorkspaceViewModel],
    projectId: WorkspaceProjectId,
    sourceWorkspaceName: String?,
    sourceWorkspace: WorkspaceSidebarWorkspaceViewModel?,
    target: WorkspaceSidebarWorkspaceDragTarget?
) -> [WorkspaceSidebarWorkspaceListEntry] {
    let isPreviewingTarget = sourceWorkspaceName != nil && target != nil
    let visibleWorkspaces = workspaces.filter {
        // Once there is a concrete landing slot, remove the source from the
        // layout. This is what lets every intervening row animate into its
        // new position instead of merely adding a duplicate preview at the
        // destination. The global reorder driver owns mouse-up, so this does
        // not sacrifice the gesture when SwiftUI unmounts the source row.
        !isPreviewingTarget || $0.name != sourceWorkspaceName
    }
    func workspaceEntry(_ workspace: WorkspaceSidebarWorkspaceViewModel) -> WorkspaceSidebarWorkspaceListEntry {
        .workspace(workspace, isDragAnchor: false)
    }
    guard let sourceWorkspace,
          let placement = workspaceSidebarWorkspaceReorderPreviewPlacement(
            sourceWorkspaceName: sourceWorkspace.name,
            target: target
          )
    else {
        return visibleWorkspaces.map { workspaceEntry($0) }
    }

    switch placement {
        case .before(let targetWorkspaceName):
            guard case .reorder(let reorderTarget)? = target,
                  reorderTarget.projectId == projectId
            else {
                return visibleWorkspaces.map { workspaceEntry($0) }
            }
            return workspaceSidebarWorkspaceListEntries(
                visibleWorkspaces: visibleWorkspaces,
                sourceWorkspace: sourceWorkspace,
                projectId: projectId,
                targetWorkspaceName: targetWorkspaceName,
                insertBefore: true,
                retainsSourceGestureAnchor: false
            )
        case .after(let targetWorkspaceName):
            guard case .reorder(let reorderTarget)? = target,
                  reorderTarget.projectId == projectId
            else {
                return visibleWorkspaces.map { workspaceEntry($0) }
            }
            return workspaceSidebarWorkspaceListEntries(
                visibleWorkspaces: visibleWorkspaces,
                sourceWorkspace: sourceWorkspace,
                projectId: projectId,
                targetWorkspaceName: targetWorkspaceName,
                insertBefore: false,
                retainsSourceGestureAnchor: false
            )
        case .intoFolder(let folderProjectId):
            guard folderProjectId == projectId else {
                return visibleWorkspaces.map { workspaceEntry($0) }
            }
            return visibleWorkspaces.map { workspaceEntry($0) } +
                [.placeholder(sourceWorkspace, projectId: projectId)]
    }
}

func workspaceSidebarFolderListEntries(
    sections: [WorkspaceSidebarFolderSection],
    sourceProjectId: WorkspaceProjectId?,
    target: WorkspaceSidebarFolderReorderTarget?
) -> [WorkspaceSidebarFolderListEntry] {
    let sourceSection = sourceProjectId.flatMap { projectId in
        sections.first { $0.id.backingProjectId == projectId }
    }
    guard let sourceSection, let target else {
        return sections.map { .folder($0, isDragAnchor: false) }
    }
    let retainsSourceGestureAnchor = true
    let visibleSections = sections.filter {
        retainsSourceGestureAnchor || $0.id.backingProjectId != sourceProjectId
    }
    func sectionEntry(_ section: WorkspaceSidebarFolderSection) -> WorkspaceSidebarFolderListEntry {
        .folder(
            section,
            isDragAnchor: retainsSourceGestureAnchor && section.id.backingProjectId == sourceProjectId
        )
    }
    var entries: [WorkspaceSidebarFolderListEntry] = []
    var didInsertPlaceholder = false
    let targetProjectId = target.placement.targetProjectId
    let insertsBefore = switch target.placement {
        case .before: true
        case .after: false
    }
    for section in visibleSections {
        if insertsBefore && section.id.backingProjectId == targetProjectId {
            entries.append(.placeholder(sourceSection))
            didInsertPlaceholder = true
        }
        entries.append(sectionEntry(section))
        if !insertsBefore && section.id.backingProjectId == targetProjectId {
            entries.append(.placeholder(sourceSection))
            didInsertPlaceholder = true
        }
    }
    if !didInsertPlaceholder {
        entries.append(.placeholder(sourceSection))
    }
    return entries
}

func workspaceSidebarFolderSourcePreview(
    _ section: WorkspaceSidebarFolderSection
) -> WorkspaceSidebarDropPreviewViewModel {
    let tabItems = section.workspaces.flatMap(workspaceSidebarWorkspaceSourcePreviewTabItems)
    let primaryItem = tabItems.first
    let windowCount = max(
        tabItems.count,
        section.workspaces.reduce(0) { $0 + $1.tabSummary.windowCount },
        section.workspaces.count,
        1
    )
    return WorkspaceSidebarDropPreviewViewModel(
        sourceWindowId: workspaceSidebarFolderSourceWindowId(section),
        label: section.project.displayName,
        appName: "\(section.workspaces.count) tab\(section.workspaces.count == 1 ? "" : "s")",
        appBundleIdentifier: primaryItem?.appBundleIdentifier,
        appBundlePath: primaryItem?.appBundlePath,
        targetWorkspaceName: nil,
        targetsNewWorkspace: false,
        isTabGroup: true,
        windowCount: windowCount,
        tabItems: tabItems,
    )
}

func workspaceSidebarWorkspaceSourcePreview(
    _ workspace: WorkspaceSidebarWorkspaceViewModel
) -> WorkspaceSidebarDropPreviewViewModel {
    let tabItems = workspaceSidebarWorkspaceSourcePreviewTabItems(workspace)
    let primaryItem = tabItems.first
    let windowCount = max(workspace.tabSummary.windowCount, tabItems.count, 1)
    return WorkspaceSidebarDropPreviewViewModel(
        sourceWindowId: workspaceSidebarWorkspaceSourceWindowId(workspace),
        label: workspace.displayName.isEmpty ? workspace.tabSummary.title : workspace.displayName,
        appName: primaryItem?.appName ?? workspace.tabSummary.subtitle ?? workspace.tabSummary.title,
        appBundleIdentifier: primaryItem?.appBundleIdentifier ?? workspace.tabSummary.appBundleId,
        appBundlePath: primaryItem?.appBundlePath ?? workspace.tabSummary.appBundlePath,
        targetWorkspaceName: nil,
        targetsNewWorkspace: false,
        isTabGroup: windowCount > 1,
        windowCount: windowCount,
        tabItems: windowCount > 1 ? tabItems : [],
    )
}

private func workspaceSidebarWorkspaceSourceWindowId(
    _ workspace: WorkspaceSidebarWorkspaceViewModel
) -> UInt32 {
    for item in workspace.items {
        switch item.kind {
            case .window(let window):
                return window.windowId
            case .tabGroup(let group):
                return group.representativeWindowId
        }
    }
    return 0
}

private func workspaceSidebarFolderSourceWindowId(
    _ section: WorkspaceSidebarFolderSection
) -> UInt32 {
    for workspace in section.workspaces {
        let windowId = workspaceSidebarWorkspaceSourceWindowId(workspace)
        if windowId != 0 {
            return windowId
        }
    }
    return 0
}

func workspaceSidebarWorkspaceSourcePreviewTabItems(
    _ workspace: WorkspaceSidebarWorkspaceViewModel
) -> [WorkspaceSidebarDropPreviewTabItem] {
    workspace.items.flatMap { item -> [WorkspaceSidebarDropPreviewTabItem] in
        switch item.kind {
            case .window(let window):
                return [workspaceSidebarWorkspaceSourcePreviewTabItem(window)]
            case .tabGroup(let group):
                return group.tabs.map(workspaceSidebarWorkspaceSourcePreviewTabItem)
        }
    }
}

private func workspaceSidebarWorkspaceSourcePreviewTabItem(
    _ window: WorkspaceSidebarWindowViewModel
) -> WorkspaceSidebarDropPreviewTabItem {
    WorkspaceSidebarDropPreviewTabItem(
        title: window.title ?? window.appName,
        appName: window.appName,
        appBundleIdentifier: window.appBundleId,
        appBundlePath: window.appBundlePath,
    )
}

func workspaceSidebarIsProjectPreviewTarget(
    projectId: WorkspaceProjectId,
    sourceWorkspaceName: String?,
    sourceWorkspace: WorkspaceSidebarWorkspaceViewModel?,
    target: WorkspaceSidebarWorkspaceDragTarget?
) -> Bool {
    guard let sourceWorkspace,
          let placement = workspaceSidebarWorkspaceReorderPreviewPlacement(
            sourceWorkspaceName: sourceWorkspace.name,
            target: target
          )
    else { return false }
    switch placement {
        case .before, .after:
            guard case .reorder(let reorderTarget)? = target else { return false }
            return reorderTarget.projectId == projectId && sourceWorkspaceName != nil
        case .intoFolder(let folderProjectId):
            return folderProjectId == projectId && sourceWorkspaceName != nil
    }
}

private func workspaceSidebarWorkspaceListEntries(
    visibleWorkspaces: [WorkspaceSidebarWorkspaceViewModel],
    sourceWorkspace: WorkspaceSidebarWorkspaceViewModel,
    projectId: WorkspaceProjectId,
    targetWorkspaceName: String,
    insertBefore: Bool,
    retainsSourceGestureAnchor: Bool
) -> [WorkspaceSidebarWorkspaceListEntry] {
    var entries: [WorkspaceSidebarWorkspaceListEntry] = []
    var didInsertPlaceholder = false

    for workspace in visibleWorkspaces {
        if insertBefore && workspace.name == targetWorkspaceName {
            entries.append(.placeholder(sourceWorkspace, projectId: projectId))
            didInsertPlaceholder = true
        }
        entries.append(.workspace(
            workspace,
            isDragAnchor: retainsSourceGestureAnchor && workspace.name == sourceWorkspace.name
        ))
        if !insertBefore && workspace.name == targetWorkspaceName {
            entries.append(.placeholder(sourceWorkspace, projectId: projectId))
            didInsertPlaceholder = true
        }
    }

    if !didInsertPlaceholder {
        entries.append(.placeholder(sourceWorkspace, projectId: projectId))
    }
    return entries
}

func workspaceSidebarProjectFrameIsVisibleDropTarget(
    projectId: WorkspaceProjectId,
    sourceProjectId: WorkspaceProjectId?
) -> Bool {
    guard let sourceProjectId else { return false }
    return projectId != workspaceProjectDefaultId && projectId != sourceProjectId
}

func workspaceSidebarWorkspacePointerIsBeforeMidline(_ pointer: CGPoint, frame: CGRect) -> Bool {
    pointer.y < frame.midY
}

private let workspaceSidebarWorkspaceReorderHorizontalTolerance: CGFloat = 160
private let workspaceSidebarWorkspaceReorderVerticalTolerance: CGFloat = 0

private func workspaceSidebarPointerIsInsideWorkspaceReorderXBand(_ pointer: CGPoint, frame: CGRect) -> Bool {
    frame.minX - workspaceSidebarWorkspaceReorderHorizontalTolerance <= pointer.x &&
        pointer.x <= frame.maxX + workspaceSidebarWorkspaceReorderHorizontalTolerance
}

private func workspaceSidebarWorkspaceReorderFrameContains(_ frame: CGRect, pointer: CGPoint) -> Bool {
    workspaceSidebarPointerIsInsideWorkspaceReorderXBand(pointer, frame: frame) &&
        frame.minY - workspaceSidebarWorkspaceReorderVerticalTolerance <= pointer.y &&
        pointer.y <= frame.maxY + workspaceSidebarWorkspaceReorderVerticalTolerance
}

private func workspaceSidebarProjectFrameExists(
    projectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarFolderReorderFrame]
) -> Bool {
    frames.contains { $0.projectId == projectId }
}

private func workspaceSidebarProjectFrameContains(
    projectId: WorkspaceProjectId,
    pointer: CGPoint,
    frames: [WorkspaceSidebarFolderReorderFrame]
) -> Bool {
    frames.contains { $0.projectId == projectId && $0.frame.contains(pointer) }
}

private func workspaceSidebarProjectFrameIsWorkspaceDropTarget(
    projectId: WorkspaceProjectId,
    frames: [WorkspaceSidebarFolderReorderFrame]
) -> Bool {
    frames.contains { $0.projectId == projectId && $0.isDropTarget }
}

private func workspaceSidebarWorkspaceReorderCandidateHasVisibleProjectFrame(
    _ candidate: WorkspaceSidebarWorkspaceReorderFrame,
    sourceProjectId: WorkspaceProjectId,
    folderFrames: [WorkspaceSidebarFolderReorderFrame]
) -> Bool {
    guard candidate.projectId != sourceProjectId else { return true }
    return workspaceSidebarProjectFrameIsWorkspaceDropTarget(
        projectId: candidate.projectId,
        frames: folderFrames
    )
}

func workspaceSidebarWorkspaceReorderPlacement(
    sourceWorkspaceName: String,
    sourceProjectId: WorkspaceProjectId,
    targetWorkspaceName: String,
    frames: [WorkspaceSidebarWorkspaceReorderFrame]
) -> WorkspaceReorderPlacement? {
    let projectFrames = frames
        .filter { $0.isReorderable && $0.projectId == sourceProjectId }
        .sorted { $0.frame.midY < $1.frame.midY }
    guard let sourceIndex = projectFrames.firstIndex(where: { $0.workspaceName == sourceWorkspaceName }),
          let targetIndex = projectFrames.firstIndex(where: { $0.workspaceName == targetWorkspaceName }),
          sourceIndex != targetIndex
    else {
        return nil
    }
    return sourceIndex < targetIndex ? .after(targetWorkspaceName) : .before(targetWorkspaceName)
}

struct WorkspaceSidebarWorkspaceReorderGestureModifier: ViewModifier {
    let isEnabled: Bool
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    @State private var isDragging = false

    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(
                DragGesture(minimumDistance: workspaceSidebarDragStartDistance, coordinateSpace: .named("workspaceSidebarContent"))
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            beginWorkspaceSidebarItemDrag()
                        }
                        noteCurrentMousePointerSample()
                        onChanged(value.location)
                    }
                    .onEnded { value in
                        noteCurrentMousePointerSample()
                        onEnded(value.location)
                        if isDragging {
                            isDragging = false
                            endWorkspaceSidebarItemDrag()
                        }
                    },
            )
            .onDisappear {
                if isDragging {
                    isDragging = false
                    endWorkspaceSidebarItemDrag()
                }
            }
        } else {
            content
        }
    }
}

struct WorkspaceSidebarWorkspaceReorderPlaceholder: View {
    let width: CGFloat
    let nestedContentIndent: CGFloat
    let previewWorkspace: WorkspaceSidebarWorkspaceViewModel?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        HStack(spacing: workspaceSidebarAppIconTextSpacing) {
            if let previewWorkspace,
               let icon = appIconImage(
                bundleIdentifier: previewWorkspace.tabSummary.appBundleId,
                bundlePath: previewWorkspace.tabSummary.appBundlePath
               )
            {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
                    .cornerRadius(4)
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.componentBackground(.hover))
                    .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
            }

            if let previewWorkspace {
                VStack(alignment: .leading, spacing: standardGap * 0.5) {
                    Text(previewWorkspace.displayName)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.content(.primary))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = previewWorkspace.tabSummary.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(palette.content(.secondary))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(palette.componentBackground(.active))
                    .frame(width: 92, height: 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .frame(height: workspaceSidebarTabRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            rowShape.fill(palette.componentBackground(.active))
        }
        .overlay {
            rowShape
                .strokeBorder(palette.geistBorder(.active), lineWidth: 0.95)
        }
        .padding(.leading, workspaceSidebarSectionInnerHorizontalInset + nestedContentIndent)
        .padding(.trailing, workspaceSidebarSectionInnerHorizontalInset)
        .frame(width: width, alignment: .leading)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.88), value: nestedContentIndent)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct WorkspaceSidebarFolderReorderPlaceholder: View {
    let width: CGFloat
    let section: WorkspaceSidebarFolderSection
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        HStack(spacing: workspaceSidebarHeaderSpacing) {
            Image(systemName: "folder.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.content(.secondary))
                .frame(width: workspaceSidebarAppIconSize + 2, height: workspaceSidebarAppIconSize + 2)
            Text(section.project.displayName)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(palette.content(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
        .padding(.trailing, workspaceSidebarRowHorizontalPadding)
        .frame(height: workspaceSidebarWorkspaceSectionHeaderHeight)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
                .fill(palette.componentBackground(.active))
        }
        .overlay {
            RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
                .strokeBorder(palette.geistBorder(.active), lineWidth: 0.95)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct WorkspaceSidebarProjectedDragAnchorModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        // Keep the source row mounted so its DragGesture continues to own the
        // mouse, but never turn it into a ghost. A translucent or collapsed
        // source makes the interaction look broken and changes the measured
        // row geometry mid-drag.
        content
    }
}
