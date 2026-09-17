import SwiftUI

struct ExposeWinCard: View {
    let item: ExposeWindowItem
    let cw: CGFloat
    let ch: CGFloat
    var badgeLabel: String? = nil
    var hoverOverride: Bool? = nil
    @State private var localHover = false

    private var isHovered: Bool { hoverOverride ?? localHover }

    var body: some View {
        VStack(spacing: standardGap * 2) {
            ZStack(alignment: .topTrailing) {
                exposeCardThumb(item, w: cw, h: ch - 20, hov: isHovered)
                if let badgeLabel {
                    exposeGroupBadge(label: badgeLabel)
                }
            }
            Text(item.title)
                .font(.system(size: 11, weight: item.isFocused ? .semibold : .regular))
                .foregroundStyle(winMuxOverlayContent(isHovered ? .primary : .secondary))
                .lineLimit(1)
                .frame(maxWidth: cw)
        }
        .frame(width: cw, height: ch)
        .contentShape(Rectangle())
        .onHover { hovering in
            guard hoverOverride == nil else { return }
            localHover = hovering
        }
        .scaleEffect(isHovered ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private func exposeGroupBadge(label: String) -> some View {
        HStack(spacing: standardGap * 2) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(winMuxOverlayGeistBackground(.primary))
        .padding(.horizontal, standardGap * 4)
        .padding(.vertical, standardGap * 2.5)
        .background(Capsule().fill(winMuxOverlayColor(.blue, .color7)))
        .padding(standardGap * 3)
    }
}
