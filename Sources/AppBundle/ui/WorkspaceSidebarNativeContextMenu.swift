import AppKit
import SwiftUI

/// Native macOS context menus, anchored above the workspace windows.
struct WorkspaceSidebarNativeContextMenu: NSViewRepresentable {
    let items: [Item]
    let colorScheme: ColorScheme

    struct Item {
        let title: String
        var isEnabled = true
        var symbol: String? = nil
        var children: [Item]? = nil
        var action: () -> Void = {}

        static var separator: Item { Item(title: "", isEnabled: false) }
    }

    func makeNSView(context: Context) -> MenuView {
        MenuView()
    }

    func updateNSView(_ view: MenuView, context: Context) {
        view.items = items
        view.colorScheme = colorScheme
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    }

    final class MenuView: NSView {
        var items: [Item] = []
        var colorScheme: ColorScheme = .light

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent,
                  event.type == .rightMouseDown ||
                    (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            guard let window else { return }
            // Native menus inherit their anchor's ordering group. Use an independent
            // invisible anchor rather than the tab bar beneath workspace windows.
            let anchor = NSPanelHud()
            anchor.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
            anchor.setFrame(NSRect(
                origin: window.convertPoint(toScreen: event.locationInWindow),
                size: NSSize(width: 1, height: 1)
            ), display: false)
            anchor.appearance = appearance
            anchor.level = .popUpMenu
            anchor.hasShadow = false
            anchor.ignoresMouseEvents = true
            anchor.orderFrontRegardless()
            defer { anchor.orderOut(nil) }
            makeMenu(items).popUp(positioning: nil, at: .zero, in: anchor.contentView)
        }

        override func mouseDown(with event: NSEvent) {
            rightMouseDown(with: event)
        }

        func makeMenu(_ items: [Item]) -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false
            for item in items {
                if item.title.isEmpty {
                    menu.addItem(.separator())
                    continue
                }
                let row = NSMenuItem(title: item.title, action: #selector(performMenuAction(_:)), keyEquivalent: "")
                row.target = self
                row.representedObject = item
                row.isEnabled = item.isEnabled
                if let symbol = item.symbol {
                    row.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                }
                if let children = item.children { row.submenu = makeMenu(children) }
                menu.addItem(row)
            }
            return menu
        }

        @objc private func performMenuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? Item)?.action()
        }
    }
}
