import AppKit
import SwiftUI

struct WindowTabStripView: View {
    let strip: WindowTabStripViewModel

    @ObservedObject var trayModel = TrayMenuModel.shared
    @State var draggingTabId: UInt32?
    @State var dragOriginalOrder: [UInt32]?
    @State var pendingReorderClearToken = UUID()
    @State var hoveredTabId: UInt32?
    @State var dragTranslationX: CGFloat = 0
    @State var reorderPreviewTargetIndex: Int?
    @State var tabFramesById: [UInt32: CGRect] = [:]
    @State var hasCommittedToDetach = false
    @State var pendingReorderDrop: WindowTabPendingReorderDrop?
    @State var tabScrollContentMinX: CGFloat = 0
    @State var tabScrollContentMaxX: CGFloat = 0
    @State var tabAutoScrollDirection: WindowTabAutoScrollDirection?
    @State var editingTabId: UInt32?
    @State var editingTabTitle: String = ""
    @Environment(\.colorScheme) var barColorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var palette: WinMuxOverlayPalette { trayModel.projectPalette(workspaceName: strip.workspaceName, colorScheme: barColorScheme) }

    var body: some View {
        GeometryReader { proxy in
            tabStripBody(
                stripWidth: max(proxy.size.width, 0),
                stripHeight: max(proxy.size.height, 0),
            )
        }
    }
}
