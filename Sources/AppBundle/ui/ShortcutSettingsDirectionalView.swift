import AppKit
import Common
import MASShortcut
import SwiftUI

struct ManagedDirectionalShortcutsView: View {
    @ObservedObject var model: ShortcutSettingsModel
    @State private var availableWidth: CGFloat = .zero

    private static let horizontalLayoutMinWidth: CGFloat = 880

    var body: some View {
        Group {
            if availableWidth >= Self.horizontalLayoutMinWidth {
                HStack(alignment: .top, spacing: standardGap * 12) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }

                    Spacer(minLength: 0)
                }
            } else {
                VStack(alignment: .leading, spacing: standardGap * 12) {
                    directionalPad(title: "Focus", prefix: "focus") {
                        FocusDemoView()
                    }

                    directionalPad(title: "Move", prefix: "move") {
                        MoveDemoView()
                    }
                }
            }
        }
        .background {
            GeometryReader { proxy in
                WinMuxDesignTokens.transparent
                    .preference(key: ManagedDirectionalShortcutsWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(ManagedDirectionalShortcutsWidthKey.self) { width in
            availableWidth = width
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func directionalPad<Demo: View>(
        title: String,
        prefix: String,
        @ViewBuilder demo: () -> Demo
    ) -> some View {
        VStack(alignment: .leading, spacing: standardGap * 6) {
            Text(title)
                .font(.headline)
            CompassPad(model: model, title: title, prefix: prefix, demo: demo)
        }
    }
}

private struct ManagedDirectionalShortcutsWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = .zero

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct DemoColors {
    static let win1 = winMuxOverlayColor(.blue, .color7)
    static let win1Muted = winMuxOverlayColor(.blue, .color3)
    static let win2 = winMuxOverlayColor(.amber, .color7)
    static let win2Muted = winMuxOverlayColor(.amber, .color3)
    static let win3 = winMuxOverlayColor(.purple, .color7)
}

struct DemoContainer<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .frame(width: 100, height: 60)
            .padding(standardGap * 4)
            .background(winMuxOverlayGeistBackground(.secondary))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(winMuxOverlayBorder(.normal), lineWidth: 0.5))
    }
}

struct FocusDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            HStack(spacing: standardGap * 3) {
                RoundedRectangle(cornerRadius: 4).fill(phase == 1 ? DemoColors.win1 : DemoColors.win1Muted)
                RoundedRectangle(cornerRadius: 4).fill(phase == 2 ? DemoColors.win2 : DemoColors.win2Muted)
            }
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 4 // 0: reset, 1: left focused, 2: right focused, 3: delay
        }
    }
}

struct MoveDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let spacing = standardGap * 2
                let winW = (geo.size.width - spacing) / 2
                let h = geo.size.height
                
                // Left position x: winW / 2
                // Right position x: winW + spacing + winW / 2
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? (winW + spacing + winW / 2) : winW / 2,
                        y: h / 2
                    )
                
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2)
                    .frame(width: winW, height: h)
                    .position(
                        x: phase == 1 ? winW / 2 : (winW + spacing + winW / 2),
                        y: h / 2
                    )
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: A-B, 1: B-A, 2: delay
        }
    }
}

struct SplitDemoView: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 1.2, on: .main, in: .common).autoconnect()

    var body: some View {
        DemoContainer {
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let spacing = standardGap * 2
                
                // Left Window (Win 1)
                RoundedRectangle(cornerRadius: 4).fill(DemoColors.win1Muted)
                    .frame(width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3, height: h)
                    .position(x: phase == 1 ? (w - spacing) / 4 : (w - 2 * spacing) / 6, y: h / 2)
                
                // Container for Win 2 and Win 3
                Group {
                    // Win 2 (Top in split)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win2Muted)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : (w - 2 * spacing) / 2 + spacing,
                            y: phase == 1 ? (h - spacing) / 4 : h / 2
                        )
                    
                    // Win 3 (Bottom in split, Focused)
                    RoundedRectangle(cornerRadius: 4).fill(DemoColors.win3)
                        .frame(
                            width: phase == 1 ? (w - spacing) / 2 : (w - 2 * spacing) / 3,
                            height: phase == 1 ? (h - spacing) / 2 : h
                        )
                        .position(
                            x: phase == 1 ? 3 * (w - spacing) / 4 + spacing : 5 * (w - 2 * spacing) / 6 + 2 * spacing,
                            y: phase == 1 ? 3 * (h - spacing) / 4 + spacing : h / 2
                        )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
        }
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3 // 0: side-by-side, 1: stacked, 2: delay
        }
    }
}

struct CompassPad<Demo: View>: View {
    @ObservedObject var model: ShortcutSettingsModel
    let title: String
    let prefix: String
    let demo: Demo

    init(model: ShortcutSettingsModel, title: String, prefix: String, @ViewBuilder demo: () -> Demo) {
        self.model = model
        self.title = title
        self.prefix = prefix
        self.demo = demo()
    }

    var body: some View {
        Grid(horizontalSpacing: standardGap * 6, verticalSpacing: standardGap * 6) {
            GridRow {
                WinMuxDesignTokens.transparent.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-up", label: "Up")
                WinMuxDesignTokens.transparent.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            GridRow {
                recorderCell(for: "\(prefix)-left", label: "Left")
                demo
                    .frame(width: 120, height: 80)
                recorderCell(for: "\(prefix)-right", label: "Right")
            }
            GridRow {
                WinMuxDesignTokens.transparent.gridCellUnsizedAxes([.horizontal, .vertical])
                recorderCell(for: "\(prefix)-down", label: "Down")
                WinMuxDesignTokens.transparent.gridCellUnsizedAxes([.horizontal, .vertical])
            }
        }
        .padding(standardGap * 10)
        .background(winMuxOverlayGeistBackground(.primary))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(winMuxOverlayBorder(.normal), lineWidth: 0.5)
        )
    }

    private func recorderCell(for id: String, label: String) -> some View {
        VStack(spacing: standardGap * 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(winMuxOverlayContent(.secondary))
            ShortcutRecorderView(
                shortcut: .init(get: { model.shortcutValue(for: id) },
                                set: { model.setShortcutValue($0, for: id) }),
                onChange: { _ in }
            )
            .frame(width: 120, height: 22)
        }
    }
}
