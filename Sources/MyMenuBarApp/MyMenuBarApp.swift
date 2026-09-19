import AppBundle
import AppKit
import SwiftUI

@MainActor
final class MyMenuBarAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MenuBarStatusWidgetsController.shared.install()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarStatusWidgetsController.shared.remove()
    }
}

@main
struct MyMenuBarApp: App {
    @NSApplicationDelegateAdaptor(MyMenuBarAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
