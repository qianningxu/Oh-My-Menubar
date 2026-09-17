import AppKit
import Common
import SwiftUI

// MARK: - Window Row

struct WorkspaceSidebarWindowRow: View {
    enum Style {
        case window
        case tabGroupHeader
        case tabGroupChild
    }

    let title: String
    let badge: String?
    let isFocused: Bool
    let suppressFocusedStyle: Bool
    let rowHeight: CGFloat
    let isHovered: Bool
    let isActiveInteraction: Bool
    let style: Style
    let appBundleIds: [String?]
    let appBundlePaths: [String?]
    let reservesCloseButtonSpace: Bool
    let leadingContentInset: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var isTabGroupHeader: Bool { style == .tabGroupHeader }
    private var isTabGroupChild: Bool { style == .tabGroupChild }
    private var isActiveRow: Bool { isFocused && !suppressFocusedStyle }
    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }
    var body: some View {
        HStack(spacing: workspaceSidebarAppIconTextSpacing) {
            if leadingContentInset > 0 {
                WinMuxDesignTokens.transparent
                    .frame(width: leadingContentInset)
            }
            appIconStack
            Text(title)
                .font(.system(size: rowTitleFontSize, weight: rowTitleWeight))
                .foregroundStyle(rowTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if let badge {
                Text(badge)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.content(.secondary))
            }
            if reservesCloseButtonSpace {
                WinMuxDesignTokens.transparent
                    .frame(width: workspaceSidebarWindowCloseButtonReservedWidth)
            }
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, standardGap * 0.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .workspaceSidebarTabRowChrome(
            palette,
            isSelected: isActiveRow,
            isHovered: isHovered,
            isActiveInteraction: isActiveInteraction
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var appIconStack: some View {
        if isTabGroupHeader {
            HStack(spacing: standardGap * -1.5) {
                ForEach(Array(appIconInputs.prefix(4).enumerated()), id: \.offset) { _, input in
                    appIcon(input)
                }
            }
        } else if let input = appIconInputs.first {
            appIcon(input)
        }
    }

    private var appIconInputs: [(String?, String?)] {
        Array(zip(appBundleIds, appBundlePaths)).filter { $0.0 != nil || $0.1 != nil }
    }

    private func appIcon(_ input: (String?, String?)) -> some View {
        Group {
            if let icon = appIconImage(bundleIdentifier: input.0, bundlePath: input.1) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: rowIconSize, height: rowIconSize)
                    .cornerRadius(isTabGroupChild ? 4 : 3)
            }
        }
    }

    private var rowTitleFontSize: CGFloat {
        13.5
    }

    private var rowTitleWeight: Font.Weight {
        if isActiveRow {
            return .semibold
        }
        return .medium
    }

    private var rowIconSize: CGFloat {
        workspaceSidebarAppIconSize + 2
    }

    private var rowTextColor: Color {
        if isActiveRow {
            return palette.content(.primary)
        }
        return palette.content(isTabGroupChild ? .primary : .secondary)
    }

}

// MARK: - Drop Preview Row

struct WorkspaceSidebarPreviewRow: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let expansionProgress: CGFloat
    let rowHeight: CGFloat
    let expandedContentWidth: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        HStack(spacing: standardGap * 3.5) {
            ZStack {
                Circle()
                    .fill(palette.componentBackground(.hover))
                Image(systemName: preview.isTabGroup ? "square.stack.3d.up.fill" : "macwindow")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(palette.content(.secondary))
            }
            .frame(width: 18, height: 18)

            Text(preview.label)
                .font(.system(size: 11.2, weight: .semibold))
                .foregroundStyle(palette.content(.primary))
                .lineLimit(1)
                .opacity(max(expansionProgress, 0.12))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, standardGap * 0.75)
        .frame(height: rowHeight + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                .fill(palette.geistBackground(.primary))
                .overlay {
                    RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
                        .strokeBorder(
                            palette.geistBorder(.active),
                            lineWidth: 0.9
                        )
                }
        )
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }
}
