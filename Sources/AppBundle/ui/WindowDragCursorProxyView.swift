import SwiftUI

struct WindowDragCursorProxyView: View {
    let label: String
    let isGroup: Bool
    let preview: WorkspaceSidebarDropPreviewViewModel?
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WinMuxOverlayPalette { WinMuxOverlayPalette(colorScheme: colorScheme) }

    init(label: String, isGroup: Bool) {
        self.label = label
        self.isGroup = isGroup
        self.preview = nil
    }

    init(preview: WorkspaceSidebarDropPreviewViewModel) {
        self.label = preview.label
        self.isGroup = preview.isTabGroup
        self.preview = preview
    }

    var body: some View {
        HStack(spacing: standardGap * 2) {
            if let preview, preview.isTabGroup {
                sidebarIconStack(preview)
            } else if let preview, let icon = appIconImage(bundleIdentifier: preview.appBundleIdentifier, bundlePath: preview.appBundlePath) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: workspaceSidebarAppIconSize, height: workspaceSidebarAppIconSize)
                    .cornerRadius(3)
            } else {
                Image(systemName: isGroup ? "square.stack" : "macwindow")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
            }
            Text(label)
                .font(.system(size: isGroup ? 12.5 : 12, weight: .medium))
                .foregroundStyle(palette.content(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, standardGap * 3.5)
        .padding(.vertical, standardGap * 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WindowDragCursorProxyBackground(isGroup: isGroup))
        .allowsHitTesting(false)
    }

    private func sidebarIconStack(_ preview: WorkspaceSidebarDropPreviewViewModel) -> some View {
        HStack(spacing: standardGap * -1.5) {
            ForEach(Array(preview.tabItems.prefix(4).enumerated()), id: \.offset) { _, tab in
                if let icon = appIconImage(bundleIdentifier: tab.appBundleIdentifier, bundlePath: tab.appBundlePath) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: workspaceSidebarAppIconSize, height: workspaceSidebarAppIconSize)
                        .cornerRadius(3)
                }
            }
        }
    }
}
