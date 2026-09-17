import Common
import Foundation
import AppKit
import SwiftUI

private struct MenuBarLabelImageCacheKey: Hashable {
    let style: MenuBarStyle
    let trayText: String
    let trayItems: [TrayItem]
}

@MainActor
private final class MenuBarLabelImageCache {
    static let shared = MenuBarLabelImageCache()

    private let limit: Int
    private var images: [MenuBarLabelImageCacheKey: NSImage] = [:]
    private var order: [MenuBarLabelImageCacheKey] = []

    fileprivate init(limit: Int = 16) {
        precondition(limit > 0)
        self.limit = limit
    }

    func image(
        for key: MenuBarLabelImageCacheKey,
        render: () -> NSImage?
    ) -> NSImage? {
        if let image = images[key] {
            order.removeAll { $0 == key }
            order.append(key)
            return image
        }
        guard let image = render() else { return nil }
        images[key] = image
        order.append(key)
        while order.count > limit {
            images.removeValue(forKey: order.removeFirst())
        }
        return image
    }
}

@MainActor
func exerciseMenuBarLabelImageCacheForTests(
    capacity: Int,
    keys: [String],
    render: (String) -> NSImage
) -> [NSImage] {
    let cache = MenuBarLabelImageCache(limit: capacity)
    return keys.map { value in
        let key = MenuBarLabelImageCacheKey(
            style: .systemText,
            trayText: value,
            trayItems: []
        )
        return cache.image(for: key) { render(value) }!
    }
}

@MainActor
struct MenuBarLabel: View {
    @Environment(\.colorScheme) var menuColorScheme: ColorScheme
    @EnvironmentObject var viewModel: TrayMenuModel
    let color: Color?
    let style: MenuBarStyle?

    let hStackSpacing = CGFloat(standardGap * 3)
    let itemSize = CGFloat(40)
    let itemBorderSize = CGFloat(3)
    let itemCornerRadius = CGFloat(6)

    private var finalColor: Color {
        return color ?? winMuxOverlayContent(.primary)
    }

    init(style: MenuBarStyle? = nil, color: Color? = nil) {
        self.style = style
        self.color = color
    }

    var body: some View {
        if #available(macOS 14, *) { // https://github.com/nikitabobko/WinMux/issues/1122
            if let image = renderedMenuBarImage() {
                Image(nsImage: image)
                    .accessibilityLabel(Text(viewModel.trayText.isEmpty ? "WinMux" : viewModel.trayText))
            } else {
                fallbackMenuBarContent
            }
        } else { // macOS 13 and lower
            fallbackMenuBarContent
        }
    }

    private func renderedMenuBarImage() -> NSImage? {
        guard color == nil else { return renderMenuBarImage() }
        let key = MenuBarLabelImageCacheKey(
            style: style ?? viewModel.experimentalUISettings.displayStyle,
            trayText: viewModel.trayText,
            trayItems: viewModel.trayItems,
        )
        return MenuBarLabelImageCache.shared.image(for: key, render: renderMenuBarImage)
    }

    private func renderMenuBarImage() -> NSImage? {
        let renderer = ImageRenderer(content: menuBarContent)
        guard let cgImage = renderer.cgImage else { return nil }
        // Using scale: 1 results in a blurry image for unknown reasons.
        let image = NSImage(cgImage: cgImage, size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2))
        // Default menu bar labels must be template images so macOS can tint them for light/dark menu bars.
        image.isTemplate = color == nil
        return image
    }

    var menuBarContent: some View {
        return HStack(spacing: hStackSpacing) {
            let style = style ?? viewModel.experimentalUISettings.displayStyle
            if menuBarLabelShouldUseAppIndicator(trayText: viewModel.trayText, trayItems: viewModel.trayItems) {
                appIndicator
            } else {
                switch style {
                    case .monospacedText: getText(for: .monospaced)
                    case .systemText: getText(for: .default)
                    case .squares:
                        if viewModel.trayItems.isEmpty {
                            appIndicator
                        } else {
                            squares
                        }
                    case .i3:
                        if viewModel.trayItems.isEmpty {
                            appIndicator
                        } else {
                            squares
                        }
                    case .i3Ordered:
                        let modeItem = viewModel.trayItems.first { $0.type == .mode }
                        if let modeItem {
                            itemView(for: modeItem)
                        } else {
                            appIndicator
                        }
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private var fallbackMenuBarContent: some View {
        if menuBarLabelShouldUseAppIndicator(trayText: viewModel.trayText, trayItems: viewModel.trayItems) {
            appIndicator
        } else {
            getText(for: .default)
        }
    }

    private func getText(for design: Font.Design) -> some View {
        Text(viewModel.trayText)
            .font(.system(.largeTitle, design: design))
            .foregroundStyle(finalColor)
    }

    private var squares: some View {
        ForEach(viewModel.trayItems, id: \.id) { item in
            itemView(for: item)
            if item.type == .mode {
                modeSeparator(with: .monospaced)
            }
        }
    }

    private var appIndicator: some View {
        WinMuxMenuBarMark(color: finalColor)
        .frame(width: itemSize, height: itemSize)
        .accessibilityLabel("WinMux")
    }

    private func otherWorkspaces(with otherWorkspaces: [WorkspaceViewModel]) -> some View {
        Group {
            Text("|")
                .font(.system(.largeTitle))
                .foregroundStyle(finalColor)
                .bold()
                .padding(.bottom, standardGap * 3)
            ForEach(otherWorkspaces, id: \.name) { item in
                itemView(for: TrayItem(
                    type: .workspace,
                    name: item.name,
                    displayName: item.displayName,
                    isActive: false,
                    hasFullscreenWindows: item.hasFullscreenWindows,
                ))
            }
        }
        .opacity(0.6)
    }

    private func modeSeparator(with design: Font.Design) -> some View {
        Text(":")
            .font(.system(.largeTitle, design: design))
            .foregroundStyle(finalColor)
            .bold()
    }

    @ViewBuilder
    fileprivate func itemView(for item: TrayItem) -> some View {
        let view = itemSubView(for: item)
        if item.hasFullscreenWindows {
            let strokeStyle = StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter, miterLimit: 10, dash: [10, 5], dashPhase: 3)
            view
                .padding(standardGap * 2)
                .overlay {
                    RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                        .strokeBorder(finalColor, style: strokeStyle)
                }
        } else {
            view
        }
    }

    @ViewBuilder
    fileprivate func itemSubView(for item: TrayItem) -> some View {
        let renderedName = item.displayName
        // If workspace name contains emojis we use the plain emoji in text to avoid visibility issues scaling the emoji to fit the squares
        if renderedName.containsEmoji() {
            Text(renderedName)
                .font(.system(.largeTitle))
                .foregroundStyle(finalColor)
                .frame(height: itemSize)
        } else {
            if let imageName = item.systemImageName {
                Image(systemName: imageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(finalColor)
                    .frame(width: itemSize, height: itemSize)
            } else {
                let text = Text(renderedName)
                    .font(.system(.largeTitle))
                    .bold()
                    .padding(.horizontal, itemBorderSize * 2)
                    .frame(height: itemSize)
                if item.isActive {
                    ZStack {
                        text.background {
                            RoundedRectangle(cornerRadius: itemCornerRadius, style: .circular)
                        }
                        text.blendMode(.destinationOut)
                    }
                    .compositingGroup()
                    .foregroundStyle(finalColor)
                    .frame(height: itemSize)
                } else {
                    text.background {
                        RoundedRectangle(cornerRadius: itemCornerRadius, style: .continuous)
                            .strokeBorder(lineWidth: itemBorderSize)
                    }
                    .foregroundStyle(finalColor)
                    .frame(height: itemSize)
                }
            }
        }
    }
}

func menuBarLabelShouldUseAppIndicator(trayText: String, trayItems: [TrayItem]) -> Bool {
    trayText.isEmpty && trayItems.isEmpty
}

extension String {
    fileprivate func containsEmoji() -> Bool {
        unicodeScalars.contains { $0.properties.isEmoji && $0.properties.isEmojiPresentation }
    }
}

private struct WinMuxMenuBarMark: View {
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let lineWidth = max(1.8, side * 0.055)
            ZStack {
                menuBarWindow(width: side * 0.48, height: side * 0.28, lineWidth: lineWidth)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -side * 0.04, y: -side * 0.11)
                menuBarWindow(width: side * 0.34, height: side * 0.38, lineWidth: lineWidth)
                    .rotationEffect(.degrees(12))
                    .offset(x: side * 0.18, y: -side * 0.03)
                menuBarWindow(width: side * 0.50, height: side * 0.30, lineWidth: lineWidth)
                    .rotationEffect(.degrees(8))
                    .offset(x: -side * 0.10, y: side * 0.16)
                menuBarWindow(width: side * 0.30, height: side * 0.30, lineWidth: lineWidth)
                    .rotationEffect(.degrees(-8))
                    .offset(x: side * 0.20, y: side * 0.18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func menuBarWindow(width: CGFloat, height: CGFloat, lineWidth: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: min(width, height) * 0.23, style: .continuous)
            .stroke(color, lineWidth: lineWidth)
            .frame(width: width, height: height)
    }
}
