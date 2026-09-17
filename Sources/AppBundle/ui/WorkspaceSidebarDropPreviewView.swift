import AppKit
import SwiftUI

struct WorkspaceSidebarDropPreviewView: View {
    let preview: WorkspaceSidebarDropPreviewViewModel
    let rowHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.workspaceSidebarProjectThemeFamily) private var projectThemeFamily

    private var palette: WinMuxOverlayPalette {
        WinMuxOverlayPalette(colorScheme: colorScheme, projectThemeFamily: projectThemeFamily)
    }

    private var sectionShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarSectionCornerRadius, style: .continuous)
    }
    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: workspaceSidebarRowCornerRadius, style: .continuous)
    }

    var body: some View {
        if preview.targetsNewWorkspace {
            newWorkspacePreview
        } else {
            previewRows
                .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
                .allowsHitTesting(false)
        }
    }

    private var newWorkspacePreview: some View {
        VStack(alignment: .leading, spacing: standardGap * 0.5) {
            HStack(spacing: workspaceSidebarHeaderSpacing) {
                Text("New tab")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.content(.primary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.leading, workspaceSidebarHeaderRowLeadingPadding)
            .padding(.trailing, workspaceSidebarRowHorizontalPadding)
            .frame(height: rowHeight + 8)
            .frame(maxWidth: .infinity, alignment: .leading)

            previewRows
                .padding(.leading, workspaceSidebarWindowRowsLeadingIndent)
        }
        .padding(.vertical, standardGap * 2)
        .padding(.horizontal, workspaceSidebarSectionInnerHorizontalInset)
        .background(sectionShape.fill(palette.geistBackground(.primary)))
        .overlay {
            sectionShape.strokeBorder(
                palette.geistBorder(.active),
                lineWidth: 0.9
            )
        }
        .contentShape(Rectangle())
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var previewRows: some View {
        if preview.isTabGroup {
            VStack(alignment: .leading, spacing: standardGap * 0.5) {
                tabGroupHeaderRow
                ForEach(Array(preview.tabItems.enumerated()), id: \.offset) { _, tab in
                    singleWindowRow(
                        title: tab.title,
                        appBundleIdentifier: tab.appBundleIdentifier,
                        appBundlePath: tab.appBundlePath
                    )
                    .padding(.leading, workspaceSidebarTabGroupChildLeadingIndent)
                }
            }
        } else {
            singleWindowRow(
                title: preview.label,
                appBundleIdentifier: preview.appBundleIdentifier,
                appBundlePath: preview.appBundlePath
            )
        }
    }

    private var tabGroupHeaderRow: some View {
        let icons = preview.tabItems.map { ($0.appBundleIdentifier, $0.appBundlePath) }
        return HStack(spacing: standardGap * 3) {
            if !icons.isEmpty {
                HStack(spacing: standardGap * -1.5) {
                    ForEach(Array(icons.prefix(4).enumerated()), id: \.offset) { _, icon in
                        if let image = appIconImage(bundleIdentifier: icon.0, bundlePath: icon.1) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 14, height: 14)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            Text(preview.label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.content(.primary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, standardGap * 0.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(palette.componentBackground(.active)))
        .overlay {
            rowShape.strokeBorder(palette.geistBorder(.active), lineWidth: 0.8)
        }
    }

    private func singleWindowRow(
        title: String,
        appBundleIdentifier: String?,
        appBundlePath: String?
    ) -> some View {
        HStack(spacing: standardGap * 3) {
            if let icon = appIconImage(bundleIdentifier: appBundleIdentifier, bundlePath: appBundlePath) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .cornerRadius(3)
            }
            Text(title)
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(palette.content(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, workspaceSidebarRowHorizontalPadding)
        .padding(.vertical, standardGap * 0.5)
        .frame(height: rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowShape.fill(palette.componentBackground(.normal)))
        .overlay {
            rowShape.strokeBorder(palette.geistBorder(.normal), lineWidth: 0.75)
        }
    }
}
