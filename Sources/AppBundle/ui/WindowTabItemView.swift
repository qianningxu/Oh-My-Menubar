import AppKit
import SwiftUI

struct WindowTabItemView: View {
    let tab: WindowTabItemViewModel
    let width: CGFloat
    let height: CGFloat
    let isDragSource: Bool
    let isHovered: Bool
    let showsTitle: Bool
    let reservesCloseButtonSpace: Bool
    var hidesTitle = false
    @Environment(\.colorScheme) var colorScheme

    @ObservedObject private var trayModel = TrayMenuModel.shared
    var palette: WinMuxOverlayPalette { trayModel.projectPalette(workspaceName: tab.workspaceName, colorScheme: colorScheme) }

    var body: some View {
        HStack(spacing: showsTitle ? WinMuxBarStyle.iconSpacing : WinMuxSpacing.none) {
            appIcon(size: iconSize)

            if showsTitle {
                Text(hidesTitle ? "" : tab.title)
                    .font(.system(size: WinMuxBarStyle.fontSize, weight: tab.isActive ? .semibold : .regular))
                    .opacity(tab.isActive || isHovered ? 1 : WinMuxBarStyle.windowTabUnfocusedTextOpacity)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .foregroundStyle(tabForegroundStyle)
        .padding(.horizontal, showsTitle ? max(WinMuxBarStyle.contentInset, reservesCloseButtonSpace ? windowTabStripCloseButtonReservedWidth : 0) : WinMuxSpacing.none)
        .frame(width: width, height: height, alignment: .center)
        .winMuxBarSegment(
            palette,
            isSelected: tab.isActive || isDragSource,
            isHovered: isHovered,
            selectedOpacity: WinMuxBarStyle.windowSelectedSegmentOpacity,
            hoveredOpacity: WinMuxBarStyle.windowTabHoveredSegmentOpacity
        )
        .clipShape(RoundedRectangle(cornerRadius: WinMuxBarStyle.workspaceTabCornerRadius, style: .continuous))
        .contentShape(Rectangle())
    }

    private var tabForegroundStyle: Color {
        winMuxBarForeground(palette)
    }

    private var iconSize: CGFloat {
        showsTitle ? workspaceSidebarAppIconSize + 2 : min(16, max(10, width - 14))
    }
}

struct WindowTabRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let onCommit: @MainActor @Sendable () -> Void
    let onCancel: @MainActor @Sendable () -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = winMuxBarForegroundNSColor(WinMuxOverlayPalette(colorScheme: colorScheme))
        field.font = .systemFont(ofSize: WinMuxBarStyle.fontSize, weight: .semibold)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        field.font = .systemFont(ofSize: WinMuxBarStyle.fontSize, weight: .semibold)
        field.textColor = winMuxBarForegroundNSColor(WinMuxOverlayPalette(colorScheme: colorScheme))
        if field.stringValue != text {
            field.stringValue = text
        }
        field.delegate = context.coordinator
        DispatchQueue.main.async {
            context.coordinator.focus(field)
        }
    }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        field.delegate = nil
        coordinator.tearDown()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit, onCancel: onCancel)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding var text: String
        let onCommit: @MainActor @Sendable () -> Void
        let onCancel: @MainActor @Sendable () -> Void
        var didFocus = false
        var didFinish = false
        var focusAttempts = 0
        weak var editingWindow: NSWindow?

        init(
            text: Binding<String>,
            onCommit: @escaping @MainActor @Sendable () -> Void,
            onCancel: @escaping @MainActor @Sendable () -> Void,
        ) {
            _text = text
            self.onCommit = onCommit
            self.onCancel = onCancel
        }

        @MainActor
        func focus(_ field: NSTextField) {
            guard !didFocus, !didFinish else { return }
            guard let window = field.window else {
                scheduleFocusRetry(field)
                return
            }
            (window as? WindowTabStripPanel)?.beginTabRename()
            editingWindow = window
            window.makeKeyAndOrderFront(nil)
            let accepted = window.makeFirstResponder(field)
            field.selectText(nil)
            didFocus = accepted && window.isKeyWindow && field.currentEditor() != nil &&
                window.firstResponder === field.currentEditor()
            if !didFocus { scheduleFocusRetry(field) }
        }

        @MainActor
        private func scheduleFocusRetry(_ field: NSTextField) {
            guard focusAttempts < 8, !didFinish else { return }
            focusAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self, weak field] in
                guard let self, let field else { return }
                self.focus(field)
            }
        }

        @MainActor
        func tearDown() {
            didFinish = true
            (editingWindow as? WindowTabStripPanel)?.endTabRename()
            editingWindow = nil
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !didFinish, let field = notification.object as? NSTextField else { return }
            text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard !didFinish, let field = notification.object as? NSTextField else { return }
            text = field.stringValue
            // Activation can end editing before the field actually acquires keyboard focus.
            if didFocus { finish(commit: true) }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !didFinish else { return true }
            switch commandSelector {
                case #selector(NSResponder.insertNewline(_:)):
                    text = textView.string
                    finish(commit: true)
                    return true
                case #selector(NSResponder.cancelOperation(_:)):
                    finish(commit: false)
                    return true
                default:
                    return false
            }
        }

        @MainActor
        private func finish(commit: Bool) {
            guard !didFinish else { return }
            didFinish = true
            (editingWindow as? WindowTabStripPanel)?.endTabRename()
            if commit {
                onCommit()
            } else {
                onCancel()
            }
        }
    }
}
