import AppKit
import SwiftUI

struct WindowTabStripScrollFadeMask: View {
    let leadingFadeWidth: CGFloat
    let trailingFadeWidth: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let leadingFade = min(leadingFadeWidth, proxy.size.width / 2)
            let trailingFade = min(trailingFadeWidth, proxy.size.width / 2)
            HStack(spacing: standardGap * 0) {
                LinearGradient(colors: [WinMuxDesignTokens.transparent, winMuxOverlayContent(.primary)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: leadingFade)
                Rectangle().fill(winMuxOverlayContent(.primary))
                LinearGradient(colors: [winMuxOverlayContent(.primary), WinMuxDesignTokens.transparent], startPoint: .leading, endPoint: .trailing)
                    .frame(width: trailingFade)
            }
        }
    }
}

struct WindowTabStripScrollContentFramePreferenceKey: PreferenceKey {
    static let defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

struct WindowTabStripTabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UInt32: CGRect] = [:]

    static func reduce(value: inout [UInt32: CGRect], nextValue: () -> [UInt32: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct WindowTabGroupHandleView: View {
    let windowId: UInt32?
    let workspaceName: String
    @Environment(\.colorScheme) private var colorScheme

    @ObservedObject private var trayModel = TrayMenuModel.shared
    private var palette: WinMuxOverlayPalette { trayModel.projectPalette(workspaceName: workspaceName, colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: standardGap * 1.25) {
            ForEach(0..<2, id: \.self) { _ in
                Capsule(style: .continuous)
                    .fill(winMuxBarForeground(palette))
                    .frame(width: 9, height: 1.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel("Stacked window")
        .help("Focus or drag stacked window")
        .frame(width: windowTabStripReservedGroupHandleWidth())
        .contentShape(Rectangle())
        .onTapGesture {
            guard let windowId, !isWindowTabStripDragInProgress() else { return }
            focusWindowFromTabStripClick(windowId, fallbackWorkspace: workspaceName)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: windowTabStripGroupDragMinimumDistance, coordinateSpace: .global)
                .onChanged { _ in
                    noteCurrentMousePointerSample()
                    guard let windowId,
                          shouldAllowTabStripChromeGroupDrag(windowId: windowId)
                    else { return }
                    updateMoveFromTabStrip(windowId)
                }
                .onEnded { _ in
                    noteCurrentMousePointerSample()
                    guard let windowId,
                          shouldContinueCurrentGroupDrag(windowId: windowId)
                    else { return }
                    finishMoveFromTabStrip()
                },
        )
    }
}

struct WindowTabOcclusionMask: Shape {
    let panelFrame: CGRect
    let occludingScreenFrames: [CGRect]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        for localRect in windowTabLocalOcclusionRects(
            panelFrame: panelFrame,
            occludingScreenFrames: occludingScreenFrames,
        ) {
            path.addRect(localRect)
        }
        return path
    }
}

extension View {
    func windowTabOcclusionMasked(panelFrame: CGRect, occludingScreenFrames: [CGRect]) -> some View {
        mask(
            WindowTabOcclusionMask(
                panelFrame: panelFrame,
                occludingScreenFrames: occludingScreenFrames,
            )
            .fill(style: FillStyle(eoFill: true))
        )
    }
}
