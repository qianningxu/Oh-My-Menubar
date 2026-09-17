import AppKit
import SwiftUI

/// Give the native project menu the same appearance as its SwiftUI label,
/// without changing the application or the containing panel's appearance.
struct ProjectMenuAppearanceHost<Content: View>: NSViewRepresentable {
    let colorScheme: ColorScheme
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSHostingView<AnyView> {
        let view = NSHostingView(rootView: themedContent)
        view.appearance = menuAppearance
        return view
    }

    func updateNSView(_ view: NSHostingView<AnyView>, context: Context) {
        view.appearance = menuAppearance
        view.rootView = themedContent
    }

    private var themedContent: AnyView {
        AnyView(content().environment(\.colorScheme, colorScheme))
    }

    private var menuAppearance: NSAppearance? {
        NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }
}
