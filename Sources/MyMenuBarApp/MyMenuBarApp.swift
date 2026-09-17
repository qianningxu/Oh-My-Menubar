import AppBundle
import AppKit
import SwiftUI

private let workspaceRenameNotification = Notification.Name("com.qianningxu.oh-my-win.workspace.rename")

private struct MenuWorkspace: Identifiable {
    let id: String
    var displayName: String
}

private struct MenuProject: Identifiable {
    let id: String
    let displayName: String
    var workspaces: [MenuWorkspace]
}

private struct PersistedWorkspaceState: Decodable {
    let sidebar: Sidebar

    struct Sidebar: Decodable {
        let projects: [Project]
        let projectLabels: [String: String]
        let workspaceLabels: [String: String]
    }

    struct Project: Decodable {
        let id: String
        let name: String
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
    @Published private(set) var projects: [MenuProject] = []
    @Published private var workspaceNameDrafts: [String: String] = [:]

    private let stateUrl = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/WinMux/sidebar-state.json")

    init() {
        reload()
    }

    func reload() {
        guard let data = try? Data(contentsOf: stateUrl),
              let state = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data)
        else {
            projects = []
            return
        }

        var seen: Set<String> = []
        projects = state.sidebar.projects.sorted { $0.order < $1.order }.map { project in
            let workspaceNames = project.folders
                .sorted { $0.order < $1.order }
                .flatMap(\.workspaceNames)
                .filter { seen.insert($0).inserted }
            return MenuProject(
                id: project.id,
                displayName: state.sidebar.projectLabels[project.id] ?? project.name,
                workspaces: workspaceNames.map {
                    MenuWorkspace(id: $0, displayName: state.sidebar.workspaceLabels[$0] ?? "Tab \($0)")
                }
            )
        }
        workspaceNameDrafts = projects
            .flatMap(\.workspaces)
            .reduce(into: [:]) { $0[$1.id] = $1.displayName }
    }

    func workspaceNameBinding(for workspace: MenuWorkspace) -> Binding<String> {
        Binding(
            get: { self.workspaceNameDrafts[workspace.id] ?? workspace.displayName },
            set: { self.workspaceNameDrafts[workspace.id] = $0 }
        )
    }

    func commitRename(_ workspace: MenuWorkspace) {
        let displayName = (workspaceNameDrafts[workspace.id] ?? workspace.displayName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else { return }

        DistributedNotificationCenter.default().post(
            name: workspaceRenameNotification,
            object: nil,
            userInfo: ["workspaceName": workspace.id, "displayName": displayName]
        )
        for projectIndex in projects.indices {
            if let workspaceIndex = projects[projectIndex].workspaces.firstIndex(where: { $0.id == workspace.id }) {
                projects[projectIndex].workspaces[workspaceIndex].displayName = displayName
                break
            }
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
        MenuBarExtra {
            Group {
                if workspaceMenuModel.projects.isEmpty {
                    Text("No workspaces found")
                } else {
                    ForEach(workspaceMenuModel.projects) { project in
                        Menu(project.displayName) {
                            ForEach(project.workspaces) { workspace in
                                TextField(
                                    "Workspace name",
                                    text: workspaceMenuModel.workspaceNameBinding(for: workspace)
                                )
                                .textFieldStyle(.plain)
                                .frame(width: 180)
                                .onSubmit { workspaceMenuModel.commitRename(workspace) }
                            }
                        }
                    }
                }
                Divider()
                Button("Quit Oh-My-Menubar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .onAppear { workspaceMenuModel.reload() }
        } label: {
            Text("oh!")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
    }
}
