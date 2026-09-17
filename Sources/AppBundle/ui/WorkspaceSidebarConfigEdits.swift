import Foundation

private let workspaceSidebarSectionHeader = "[tab-sidebar]"
private let workspaceSidebarLegacySectionHeaders: Set<String> = ["[workspace-sidebar]"]
private let workspaceSidebarMenuBarReserveKey = "menu-bar-reserve-height"
private let workspaceSidebarFolderDeletionActionKey = "folder-deletion-action"
private let workspaceSidebarLegacyProjectDeletionActionKey = "project-deletion-action"

/// WinMux used `[workspace-sidebar]` before the sidebar was renamed to
/// `[tab-sidebar]`.  Updating a nested setting used to add a new
/// `[tab-sidebar.*]` section while leaving the old root in place.  The
/// resulting mixed-root TOML is rejected at startup, which made WinMux load
/// defaults and lose the visible folders.  Canonicalize every related header
/// together so a config always has exactly one sidebar root.
func canonicalWorkspaceSidebarConfigRoots(in configText: String) -> String {
    configText
        .components(separatedBy: "\n")
        .map { line in
            let leadingWhitespace = String(line.prefix(while: { $0.isWhitespace }))
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed == "[workspace-sidebar]" ||
                (trimmed.hasPrefix("[workspace-sidebar.") && trimmed.hasSuffix("]"))
            else {
                return line
            }
            return leadingWhitespace + trimmed.replacingOccurrences(
                of: "[workspace-sidebar",
                with: "[tab-sidebar",
            )
        }
        .joined(separator: "\n")
}

func updateWorkspaceSidebarMenuBarReserveConfig(
    in configText: String,
    height: Int,
) -> String {
    updateWorkspaceSidebarScalarConfig(
        in: configText,
        key: workspaceSidebarMenuBarReserveKey,
        renderedValue: "\(height)",
    )
}

func updateWorkspaceSidebarProjectDeletionActionConfig(
    in configText: String,
    action: WorkspaceProjectDeletionAction,
) -> String {
    updateWorkspaceSidebarScalarConfig(
        in: configText,
        key: workspaceSidebarFolderDeletionActionKey,
        legacyKeys: [workspaceSidebarLegacyProjectDeletionActionKey],
        renderedValue: "'\(action.rawValue)'",
    )
}

private func updateWorkspaceSidebarScalarConfig(
    in configText: String,
    key: String,
    legacyKeys: Set<String> = [],
    renderedValue: String,
) -> String {
    let canonicalConfigText = canonicalWorkspaceSidebarConfigRoots(in: configText)
    let lines = canonicalConfigText.components(separatedBy: "\n")
    let sectionHeaders = workspaceSidebarLegacySectionHeaders.union([workspaceSidebarSectionHeader])
    guard let sectionIndex = lines.firstIndex(where: { sectionHeaders.contains($0.trimmingCharacters(in: .whitespaces)) }) else {
        var result = canonicalConfigText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(workspaceSidebarSectionHeader)\n"
        result += "    \(key) = \(renderedValue)"
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex

    var resultLines = lines
    resultLines[sectionIndex] = workspaceSidebarSectionHeader
    for lineIndex in (sectionIndex + 1)..<sectionEnd {
        guard workspaceSidebarConfigKey(in: resultLines[lineIndex]).map({ $0 == key || legacyKeys.contains($0) }) == true else {
            continue
        }
        let indentation = String(resultLines[lineIndex].prefix(while: { $0.isWhitespace }))
        let trailingComment = trailingTomlComment(in: resultLines[lineIndex]).map { " " + $0 } ?? ""
        resultLines[lineIndex] = "\(indentation)\(key) = \(renderedValue)\(trailingComment)"
        return resultLines.joined(separator: "\n")
    }

    resultLines.insert("    \(key) = \(renderedValue)", at: sectionIndex + 1)
    return resultLines.joined(separator: "\n")
}

@MainActor
func persistWorkspaceSidebarMenuBarReserveHeight(_ height: Int) throws -> URL {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? starterConfigText()
    let updatedText = updateWorkspaceSidebarMenuBarReserveConfig(in: currentText, height: height)
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
    return targetUrl
}

@MainActor
func persistWorkspaceSidebarProjectDeletionAction(_ action: WorkspaceProjectDeletionAction) throws -> URL {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? starterConfigText()
    let updatedText = updateWorkspaceSidebarProjectDeletionActionConfig(in: currentText, action: action)
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
    return targetUrl
}

func updateWorkspaceSidebarLabelConfig(
    in configText: String,
    workspaceName: String,
    label: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: canonicalWorkspaceSidebarConfigRoots(in: configText),
        sectionHeader: "[tab-sidebar.tab-labels]",
        legacySectionHeaders: ["[tab-sidebar.workspace-labels]", "[workspace-sidebar.tab-labels]", "[workspace-sidebar.workspace-labels]"],
        key: workspaceName,
        value: label,
    )
}

func updateWorkspaceSidebarProjectLabelConfig(
    in configText: String,
    projectId: String,
    label: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: canonicalWorkspaceSidebarConfigRoots(in: configText),
        sectionHeader: "[tab-sidebar.project-labels]",
        legacySectionHeaders: ["[workspace-sidebar.project-labels]"],
        key: projectId,
        value: label,
    )
}

func updateWorkspaceSidebarFolderLabelConfig(
    in configText: String,
    folderId: String,
    label: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: canonicalWorkspaceSidebarConfigRoots(in: configText),
        sectionHeader: "[tab-sidebar.folder-labels]",
        legacySectionHeaders: ["[workspace-sidebar.folder-labels]"],
        key: folderId,
        value: label,
    )
}

func updateWorkspaceSidebarProjectColorConfig(
    in configText: String,
    projectId: String,
    colorHex: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: canonicalWorkspaceSidebarConfigRoots(in: configText),
        sectionHeader: "[tab-sidebar.project-colors]",
        legacySectionHeaders: ["[workspace-sidebar.project-colors]"],
        key: projectId,
        value: colorHex,
    )
}

func updateWorkspaceSidebarFolderColorConfig(
    in configText: String,
    folderId: String,
    colorHex: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: canonicalWorkspaceSidebarConfigRoots(in: configText),
        sectionHeader: "[tab-sidebar.folder-colors]",
        legacySectionHeaders: ["[workspace-sidebar.folder-colors]"],
        key: folderId,
        value: colorHex,
    )
}

func updateWindowTabLabelConfig(
    in configText: String,
    key: String,
    label: String?,
) -> String {
    updateTomlKeyValueSectionConfig(
        in: configText,
        sectionHeader: "[window-tabs.tab-labels]",
        key: key,
        value: label,
    )
}

private func updateTomlKeyValueSectionConfig(
    in configText: String,
    sectionHeader: String,
    legacySectionHeaders: Set<String> = [],
    key: String,
    value: String?,
) -> String {
    let lines = configText.components(separatedBy: "\n")
    let sectionHeaders = legacySectionHeaders.union([sectionHeader])
    guard let sectionIndex = lines.firstIndex(where: { sectionHeaders.contains($0.trimmingCharacters(in: .whitespaces)) }) else {
        guard let value else { return configText }
        var result = configText
        if !result.isEmpty, !result.hasSuffix("\n") {
            result += "\n"
        }
        if !result.isEmpty {
            result += "\n"
        }
        result += "\(sectionHeader)\n"
        result += tomlKeyValueLine(key: key, value: value)
        return result
    }

    let sectionEnd = lines[(sectionIndex + 1)...]
        .firstIndex(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        }) ?? lines.endIndex

    var resultLines = Array(lines[..<sectionIndex])
    resultLines.append(sectionHeader)

    var wroteValue = false
    var bodyLines: [String] = []
    for line in lines[(sectionIndex + 1)..<sectionEnd] {
        if workspaceSidebarLabelKey(in: line) == key {
            if let value, !wroteValue {
                bodyLines.append(tomlKeyValueLine(key: key, value: value))
                wroteValue = true
            }
            continue
        }
        bodyLines.append(line)
    }
    if let value, !wroteValue {
        bodyLines.append(tomlKeyValueLine(key: key, value: value))
    }

    let hasAnyEntries = bodyLines.contains(where: { workspaceSidebarLabelKey(in: $0) != nil })
    if hasAnyEntries {
        resultLines.append(contentsOf: bodyLines)
    } else {
        resultLines.removeLast()
        if !resultLines.isEmpty, resultLines.last?.isEmpty == false {
            resultLines.append("")
        }
    }
    resultLines.append(contentsOf: lines[sectionEnd...])
    return resultLines.joined(separator: "\n")
}

@MainActor
func persistWorkspaceSidebarLabel(workspaceName: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarLabelConfig(
        in: currentText,
        workspaceName: workspaceName,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWorkspaceSidebarProjectLabel(projectId: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarProjectLabelConfig(
        in: currentText,
        projectId: projectId,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWorkspaceSidebarFolderLabel(folderId: String, label: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarFolderLabelConfig(
        in: currentText,
        folderId: folderId,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWorkspaceSidebarProjectColor(projectId: String, colorHex: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarProjectColorConfig(
        in: currentText,
        projectId: projectId,
        colorHex: colorHex,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWorkspaceSidebarFolderColor(folderId: String, colorHex: String?) throws {
    let targetUrl = preferredWorkspaceSidebarConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWorkspaceSidebarFolderColorConfig(
        in: currentText,
        folderId: folderId,
        colorHex: colorHex,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
func persistWindowTabLabel(key: String, label: String?) throws {
    let targetUrl = preferredEditableConfigUrl()
    let currentText = (try? String(contentsOf: targetUrl, encoding: .utf8)) ?? ""
    let updatedText = updateWindowTabLabelConfig(
        in: currentText,
        key: key,
        label: label,
    )
    if let parent = targetUrl.deletingLastPathComponent().takeIf({ $0.path != targetUrl.path }) {
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    try updatedText.write(to: targetUrl, atomically: true, encoding: .utf8)
}

@MainActor
private func preferredWorkspaceSidebarConfigUrl() -> URL {
    preferredEditableConfigUrl()
}

private func workspaceSidebarLabelKey(in line: String) -> String? {
    workspaceSidebarConfigKey(in: line)
}

private func workspaceSidebarConfigKey(in line: String) -> String? {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { return nil }
    let key = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
    if key.hasPrefix("\""), key.hasSuffix("\""), key.count >= 2 {
        let inner = key.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
    }
    return String(key)
}

private func trailingTomlComment(in line: String) -> String? {
    guard let hashIndex = line.firstIndex(of: "#") else { return nil }
    return String(line[hashIndex...]).trimmingCharacters(in: .whitespaces)
}

private func tomlKeyValueLine(key: String, value: String) -> String {
    "\"\(tomlEscape(key))\" = \"\(tomlEscape(value))\""
}

private func tomlEscape(_ raw: String) -> String {
    raw
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
}
