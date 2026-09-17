import AppBundle
import AppKit
import SwiftUI

private let workspaceRenameNotification = Notification.Name("com.qianningxu.oh-my-win.workspace.rename")

private struct MenuWorkspace: Identifiable {
    let id: String
    var displayName: String
}

private struct PersistedWorkspaceState: Decodable {
    let sidebar: Sidebar

    struct Sidebar: Decodable {
        let projects: [Project]
        let workspaceLabels: [String: String]
    }

    struct Project: Decodable {
        let order: Int
        let folders: [Folder]
    }

    struct Folder: Decodable {
        let order: Int
        let workspaceNames: [String]
    }
}

@MainActor
private final class WorkspaceMenuModel: ObservableObject {
    @Published private(set) var workspaces: [MenuWorkspace] = []

    private let stateUrl = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/WinMux/sidebar-state.json")

    init() {
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: stateUrl),
              let state = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data)
        else {
            workspaces = []
            return
        }

        var seen: Set<String> = []
        workspaces = state.sidebar.projects
            .sorted { $0.order < $1.order }
            .flatMap { $0.folders.sorted { $0.order < $1.order } }
            .flatMap(\.workspaceNames)
            .filter { seen.insert($0).inserted }
            .map { MenuWorkspace(id: $0, displayName: state.sidebar.workspaceLabels[$0] ?? "Tab \($0)") }
    }

    func promptToRename(_ workspace: MenuWorkspace) {
        let field = NSTextField(string: workspace.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)

        let alert = NSAlert()
        alert.messageText = "Name workspace"
        alert.informativeText = "Choose the name shown in Oh-My-Menubar and the workspace switcher."
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let displayName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }

        DistributedNotificationCenter.default().post(
            name: workspaceRenameNotification,
            object: nil,
            userInfo: ["workspaceName": workspace.id, "displayName": displayName]
        )
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index].displayName = displayName
        }
    }
}

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
    @StateObject private var workspaceMenuModel = WorkspaceMenuModel()

    var body: some Scene {
        MenuBarExtra("Oh-My-Menubar", systemImage: "rectangle.topthird.inset.filled") {
            Group {
                Text("Workspaces")
                if workspaceMenuModel.workspaces.isEmpty {
                    Text("No workspaces found")
                } else {
                    ForEach(workspaceMenuModel.workspaces) { workspace in
                        Button {
                            workspaceMenuModel.promptToRename(workspace)
                        } label: {
                            Label(workspace.displayName, systemImage: "pencil")
                        }
                    }
                }
                Divider()
                Button("Quit Oh-My-Menubar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .onAppear { workspaceMenuModel.reload() }
        }
    }
}
