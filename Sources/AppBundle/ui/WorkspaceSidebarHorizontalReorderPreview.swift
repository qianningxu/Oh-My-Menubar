import Foundation

struct WorkspaceSidebarPendingHorizontalReorder {
    let id = UUID()
    let order: [String]
    let offsets: [String: CGFloat]
}

/// Slot movements use the same before/after placement as the committed reorder.
func workspaceSidebarHorizontalReorderSteps(
    order: [String], source: String, placement: WorkspaceReorderPlacement
) -> [String: Int] {
    guard order.contains(source), Set(order).count == order.count else { return [:] }
    var reordered = order.filter { $0 != source }
    let target: String
    let after: Bool
    switch placement {
    case .before(let name): (target, after) = (name, false)
    case .after(let name): (target, after) = (name, true)
    }
    guard let targetIndex = reordered.firstIndex(of: target) else { return [:] }
    reordered.insert(source, at: targetIndex + (after ? 1 : 0))
    let originalIndices = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
    return Dictionary(uniqueKeysWithValues: reordered.enumerated().map {
        ($0.element, $0.offset - originalIndices[$0.element, default: $0.offset])
    })
}
