    import AppKit
    import Common
    import Foundation
    import SwiftUI
    
@MainActor
public func menuBar(viewModel: TrayMenuModel) -> some Scene {
    MenuBarExtra {
        WorkspaceProjectMenuBarContent(viewModel: viewModel)
    } label: {
        MenuBarLabel().environmentObject(viewModel)
    }
}

private struct WorkspaceProjectMenuBarContent: View {
    @ObservedObject var viewModel: TrayMenuModel

    private var selectedProjectId: WorkspaceProjectId {
        viewModel.workspaceSidebarActiveProjectId
    }

    private var selectedProject: WorkspaceSidebarProjectViewModel? {
        viewModel.workspaceSidebarProjects.first { $0.id == selectedProjectId }
    }

    var body: some View {
        ForEach(viewModel.workspaceSidebarProjects) { project in
            Button {
                handleWorkspaceSidebarAction(.selectProject(project.id), viewModel: viewModel)
            } label: {
                if project.id == selectedProjectId {
                    Label(project.displayName, systemImage: "checkmark")
                } else {
                    Text(project.displayName)
                }
            }
        }

        Divider()

        Menu("Config") {
            Menu("Theme") {
                themeButton("Light", theme: .light)
                themeButton("Dark", theme: .dark)
                themeButton("System", theme: nil)
            }

            Button {
                handleWorkspaceSidebarAction(
                    .setAutoHide(!viewModel.isWorkspaceSidebarAutoHideEnabled),
                    viewModel: viewModel
                )
            } label: {
                if viewModel.isWorkspaceSidebarAutoHideEnabled {
                    Label("Auto hide", systemImage: "checkmark")
                } else {
                    Text("Auto hide")
                }
            }

            if let project = selectedProject, projectsAreEnabled() {
                Divider()
                Button("Rename project…") { rename(project) }
                Menu("Project color") {
                    ForEach(workspaceSidebarProjectColorPresets) { preset in
                        Button(preset.name) {
                            handleWorkspaceSidebarAction(
                                .setProjectColor(project.id, colorHex: preset.hex),
                                viewModel: viewModel
                            )
                        }
                    }
                }
                Button("Delete project") {
                    handleWorkspaceSidebarAction(.deleteProject(project.id), viewModel: viewModel)
                }
                .disabled(!canDeleteWorkspaceProject(project.id))
            }
        }

        if projectsAreEnabled() {
            Button("New project") { createProject() }
        }
    }

    @ViewBuilder
    private func themeButton(_ title: String, theme: AppearanceTheme?) -> some View {
        Button {
            setWorkspaceSidebarAppearance(theme)
        } label: {
            if currentWorkspaceSidebarAppearancePreference() == theme {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    private func createProject() {
        guard let name = projectNamePrompt(title: "New project", initialValue: "") else { return }
        createWorkspaceSidebarProject(displayName: name, viewModel: viewModel)
    }

    private func rename(_ project: WorkspaceSidebarProjectViewModel) {
        guard let name = projectNamePrompt(title: "Rename project", initialValue: project.displayName) else { return }
        handleWorkspaceSidebarAction(.renameProject(project.id, displayName: name), viewModel: viewModel)
    }
}

@MainActor
private func projectNamePrompt(title: String, initialValue: String) -> String? {
    let field = NSTextField(string: initialValue)
    field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
    let alert = NSAlert()
    alert.messageText = title
    alert.accessoryView = field
    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { return nil }
    let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

@MainActor @ViewBuilder
func openConfigButton(showShortcutGroup: Bool = false) -> some View {
    let button = Button("Open configuration file") {
        switch findCustomConfigUrl() {
            case .file(let url):
                NSWorkspace.shared.open(url)
            case .noCustomConfigExists:
                let createdUrl = try? ensureBootstrapConfigExistsIfNeeded()
                NSWorkspace.shared.open(createdUrl ?? preferredEditableConfigUrl())
            case .ambiguousConfigError:
                NSWorkspace.shared.open(preferredEditableConfigUrl())
        }
    }.keyboardShortcut(",", modifiers: .command)
    if showShortcutGroup {
        shortcutGroup(label: Text("⌘ ,"), content: button)
    } else {
        button
    }
}

@MainActor @ViewBuilder
func reloadConfigButton(showShortcutGroup: Bool = false) -> some View {
    if let token: RunSessionGuard = .isServerEnabled {
        let button = Button("Reload configuration") {
            Task {
                try await runLightSession(.menuBarButton, token) { _ = try await reloadConfig() }
            }
        }.keyboardShortcut("R", modifiers: .command)
        if showShortcutGroup {
            shortcutGroup(label: Text("⌘ R"), content: button)
        } else {
            button
        }
    }
}

func shortcutGroup(label: some View, content: some View) -> some View {
    GroupBox {
        VStack(alignment: .trailing, spacing: standardGap * 3) {
            label
                .foregroundStyle(winMuxOverlayContent(.secondary))
            content
        }
    }
}
