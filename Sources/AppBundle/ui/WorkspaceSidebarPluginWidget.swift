import Common
import Foundation
import SidebarWidgetsAPI
import SwiftUI

struct WorkspaceSidebarPluginWidget: View {
    let config: WorkspaceSidebarWidgetConfig
    let sectionWidth: CGFloat
    let isCompact: Bool

    var body: some View {
        if let plugin = WorkspaceSidebarPluginRegistry.shared.plugin(for: config) {
            plugin.makeView(context: SidebarWidgetContext(
                id: config.id,
                sectionWidth: sectionWidth,
                isCompact: isCompact,
            ))
            .frame(width: sectionWidth, alignment: .leading)
        } else {
            EmptyView()
        }
    }
}

@MainActor
final class WorkspaceSidebarPluginRegistry {
    static let shared = WorkspaceSidebarPluginRegistry()

    private var cache: [String: SidebarWidgetPlugin?] = [:]

    func plugin(for config: WorkspaceSidebarWidgetConfig) -> SidebarWidgetPlugin? {
        guard let bundleName = config.bundle else { return nil }
        if let cached = cache[bundleName] {
            return cached
        }

        let plugin = loadPlugin(bundleName: bundleName, widgetId: config.id)
        cache[bundleName] = plugin
        return plugin
    }

    private func loadPlugin(bundleName: String, widgetId: String) -> SidebarWidgetPlugin? {
        let bundleURL = sidebarWidgetPluginDirectoryURL().appending(component: bundleName)
        guard let bundle = Bundle(url: bundleURL) else {
            logPluginDiagnostic("Widget '\(widgetId)' bundle not found: \(bundleURL.path)")
            return nil
        }
        guard bundle.load() else {
            logPluginDiagnostic("Widget '\(widgetId)' bundle could not be loaded: \(bundleURL.path)")
            return nil
        }
        guard let principalClass = bundle.principalClass as? NSObject.Type else {
            logPluginDiagnostic("Widget '\(widgetId)' bundle has no NSObject principal class: \(bundleURL.path)")
            return nil
        }
        guard let plugin = principalClass.init() as? SidebarWidgetPlugin else {
            logPluginDiagnostic("Widget '\(widgetId)' principal class does not conform to SidebarWidgetPlugin")
            return nil
        }
        guard plugin.apiVersion == sidebarWidgetAPIVersion else {
            logPluginDiagnostic(
                "Widget '\(widgetId)' API version \(plugin.apiVersion) does not match \(sidebarWidgetAPIVersion)"
            )
            return nil
        }
        return plugin
    }

    private func sidebarWidgetPluginDirectoryURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(component: "Library/Application Support")
        return appSupport
            .appending(component: winMuxAppName, directoryHint: .isDirectory)
            .appending(component: "sidebar_widgets", directoryHint: .isDirectory)
    }

    private func logPluginDiagnostic(_ message: String) {
        NSLog("[WinMux sidebar widgets] %@", message)
    }
}
