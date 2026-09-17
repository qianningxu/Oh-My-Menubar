import AppKit
import Common

func confirmedMinimumSizeAfterNativeProbe(
    original: CGSize,
    observed: CGSize,
    tolerance: CGFloat = 0.5
) -> CGSize? {
    let width = observed.width.isFinite && observed.width > 0 &&
        observed.width < original.width - tolerance ? observed.width : 0
    let height = observed.height.isFinite && observed.height > 0 &&
        observed.height < original.height - tolerance ? observed.height : 0
    guard width > 0 || height > 0 else { return nil }
    return CGSize(width: width, height: height)
}

/// Preserve requested proportions where possible, redistributing only the
/// space needed by constrained children. Infeasible layouts retain minimums.
func constrainedTileWeights(proposed: [CGFloat], minimums: [CGFloat], available: CGFloat) -> [CGFloat] {
    guard !proposed.isEmpty else { return [] }
    precondition(proposed.count == minimums.count)
    var result = minimums
    var remaining = Set(proposed.indices)
    var budget = max(available, minimums.reduce(0, +))
    while !remaining.isEmpty {
        let delta = (budget - remaining.reduce(CGFloat(0)) { $0 + proposed[$1] }) / CGFloat(remaining.count)
        let constrained = remaining.filter { proposed[$0] + delta < minimums[$0] }
        if constrained.isEmpty {
            for index in remaining { result[index] = proposed[index] + delta }
            break
        }
        for index in constrained {
            budget -= minimums[index]
            remaining.remove(index)
        }
    }
    return result
}

extension TreeNode {
    @MainActor
    func minimumLayoutSize(gaps: ResolvedGaps) -> CGSize {
        if let window = self as? Window { return window.minimumSize ?? .zero }
        guard let container = self as? TilingContainer else { return .zero }
        let sizes = children.map { $0.minimumLayoutSize(gaps: gaps) }
        var size = CGSize(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
        if container.layout == .tiles {
            let gap = CGFloat(gaps.inner.get(container.orientation)) * CGFloat(max(0, children.count - 1))
            if container.orientation == .h {
                size.width = sizes.reduce(0) { $0 + $1.width } + gap
            } else {
                size.height = sizes.reduce(0) { $0 + $1.height } + gap
            }
        } else if container.usesWindowTabBehavior {
            if container.showsWindowTabs {
                size.width += windowTabGroupShellHorizontalInset() * 2
                size.height += container.windowTabBarHeight + windowTabGroupShellTopInset() + windowTabGroupShellBottomInset()
            }
        } else if children.count > 1 {
            let padding = CGFloat(config.tabGroupPadding) * 2
            if container.orientation == .h { size.width += padding } else { size.height += padding }
        }
        return size
    }

    @MainActor
    var resizeMinimumWeight: CGFloat {
        guard let parent = parent as? TilingContainer, parent.layout == .tiles,
              let workspace = nodeWorkspace, let ownIndex else { return 0 }
        let gaps = ResolvedGaps(gaps: config.gaps, monitor: workspace.workspaceMonitor,
                                canvasGap: config.workspaceSidebar.enabled ? Int(WinMuxSpacing.comfortable) : nil)
        return parent.minimumTileWeights(gaps: gaps)[ownIndex]
    }
}

extension TilingContainer {
    @MainActor
    func minimumTileWeights(gaps: ResolvedGaps) -> [CGFloat] {
        let rawGap = CGFloat(gaps.inner.get(orientation))
        return children.enumerated().map { index, child in
            let size = child.minimumLayoutSize(gaps: gaps)
            let gap = rawGap - (index == 0 ? rawGap / 2 : 0) - (index == children.count - 1 ? rawGap / 2 : 0)
            return (orientation == .h ? size.width : size.height) + gap
        }
    }
}
