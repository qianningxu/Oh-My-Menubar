import SwiftUI

struct WorkspaceSidebarInUseOverrideOverlay: View {
    let text: String
    let onOverride: () -> Void
    @State private var isOverrideHovered = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            WinMuxDesignTokens.transparent
                .background(palette.geistBackground(.primary))
                .overlay {
                    shape.fill(palette.color(.red, .color1))
                }
                .clipShape(shape)

            shape.strokeBorder(palette.color(.red, .color4), lineWidth: 0.8)

            VStack(spacing: standardGap * 4) {
                Text(text)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(palette.content(.primary))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, standardGap * 6)

                Button(action: onOverride) {
                    Text("Override")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.geistBackground(.primary))
                        .padding(.horizontal, standardGap * 7)
                        .padding(.vertical, standardGap * 2)
                }
                .buttonStyle(.plain)
                .background {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(palette.color(.red, isOverrideHovered ? .color8 : .color7))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(palette.color(.red, isOverrideHovered ? .color6 : .color5), lineWidth: 0.6)
                }
                .onHover { hovering in
                    isOverrideHovered = hovering
                }
            }
            .padding(.vertical, standardGap * 5)
        }
        .contentShape(Rectangle())
    }
}
