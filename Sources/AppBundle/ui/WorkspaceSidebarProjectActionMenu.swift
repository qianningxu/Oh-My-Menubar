import SwiftUI

let workspaceSidebarProjectActionMenuWidth = workspaceSidebarProjectPopupMaximumWidth

struct WorkspaceSidebarProjectActionMenu: View {
    let project: WorkspaceSidebarProjectViewModel
    let menuWidth: CGFloat
    let onRename: () -> Void
    let onSetColor: (String?) -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    @State private var isColorMenuOpen = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var selectedColorHex: String {
        project.colorHex.flatMap(normalizedWorkspaceSidebarColorHex)
            ?? workspaceSidebarDefaultProjectColorHex
    }

    var body: some View {
        actionMenu
    }

    private var actionMenu: some View {
        VStack(alignment: .leading, spacing: standardGap * 0.5) {
            WorkspaceSidebarProjectActionMenuRow(
                title: "Rename project",
                symbol: "pencil",
                action: onRename
            )
            WorkspaceSidebarProjectActionMenuRow(
                title: "Color",
                symbol: "paintpalette",
                showsChevron: true,
                action: { isColorMenuOpen = true }
            )

            Rectangle()
                .fill(palette.geistBorder(.normal))
                .frame(height: WinMuxSpacing.hairline)
                .padding(.horizontal, workspaceSidebarDropdownPadding)
                .padding(.vertical, WinMuxSpacing.hairline)

            WorkspaceSidebarProjectActionMenuRow(
                title: "Delete project",
                symbol: "trash",
                isDestructive: true,
                isDisabled: !canDeleteWorkspaceProject(project.id),
                action: onDelete
            )
        }
        .padding(standardGap * 2)
        .frame(width: menuWidth, alignment: .leading)
        .background(menuSurface)
        .contentShape(RoundedRectangle(cornerRadius: workspaceSidebarProjectPopupCornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(project.displayName)")
        .overlay(alignment: .topTrailing) {
            if isColorMenuOpen {
                colorMenu
                    .offset(x: menuWidth + standardGap * 2, y: -standardGap * 2)
                    .zIndex(1_000)
            }
        }
    }

    private var colorMenu: some View {
        VStack(alignment: .leading, spacing: standardGap * 1) {
            ForEach(workspaceSidebarProjectColorPresets) { preset in
                WorkspaceSidebarProjectColorMenuRow(
                    preset: preset,
                    isSelected: selectedColorHex == preset.hex,
                    action: {
                        onSetColor(preset.hex)
                        onDismiss()
                    }
                )
            }
        }
        .padding(standardGap * 2)
        .frame(width: menuWidth, alignment: .leading)
        .background(menuSurface)
        .contentShape(RoundedRectangle(cornerRadius: workspaceSidebarProjectPopupCornerRadius, style: .continuous))
        .accessibilityLabel("Project color")
    }

    private var menuSurface: some View {
        let shape = RoundedRectangle(cornerRadius: workspaceSidebarProjectPopupCornerRadius, style: .continuous)
        return shape
            .fill(palette.geistBackground(.primary))
            .overlay {
                shape.strokeBorder(palette.geistBorder(.normal), lineWidth: 0.75)
            }
    }
}

private struct WorkspaceSidebarProjectActionMenuRow: View {
    let title: String
    let symbol: String
    var showsChevron = false
    var isDestructive = false
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: standardGap * 3.5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: .medium))
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, standardGap * 3.5)
            .frame(height: workspaceSidebarProjectPopupRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && !isDisabled ? palette.componentBackground(.hover) : WinMuxDesignTokens.transparent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovered)
    }

    private var foreground: Color {
        palette.content(.secondary)
    }
}

private struct WorkspaceSidebarProjectColorMenuRow: View {
    let preset: WorkspaceSidebarProjectColorPreset
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: standardGap * 4) {
                Circle()
                    .fill(workspaceSidebarProjectColor(projectId: WorkspaceProjectId(rawValue: preset.id), configuredHex: preset.hex))
                    .frame(width: 10, height: 10)
                Text(preset.name)
                    .font(.system(size: workspaceSidebarProjectLabelFontSize, weight: .medium))
                Spacer(minLength: 0)
                Image(systemName: "check")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(isSelected ? 1 : 0)
            }
            .foregroundStyle(palette.content(.primary))
            .padding(.horizontal, standardGap * 3.5)
            .frame(height: workspaceSidebarProjectPopupRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered || isSelected ? palette.componentBackground(isSelected ? .active : .hover) : WinMuxDesignTokens.transparent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.10), value: isHovered)
    }
}
