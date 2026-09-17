import Common
import Foundation
import TOMLKit

let legacyConfigDotfileName = ".winmux.toml"
let generatedConfigDirectoryName = "winmux"
let generatedConfigFileName = "winmux.toml"
let aerospaceLegacyConfigDotfileName = ".aerospace.toml"
let aerospaceConfigDirectoryName = "aerospace"
let aerospaceConfigFileName = "aerospace.toml"

func xdgConfigHomeUrl() -> URL {
    ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/")
}

func generatedConfigUrl() -> URL {
    xdgConfigHomeUrl()
        .appending(path: generatedConfigDirectoryName)
        .appending(path: generatedConfigFileName)
}

func legacyConfigCandidateUrls() -> [URL] {
    [
        xdgConfigHomeUrl().appending(path: "winmux").appending(path: "winmux.toml"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: legacyConfigDotfileName),
    ]
}

func preferredLegacyConfigImportUrl() -> URL? {
    legacyConfigCandidateUrls().first { FileManager.default.fileExists(atPath: $0.path) }
}

func aerospaceConfigCandidateUrls() -> [URL] {
    [
        xdgConfigHomeUrl().appending(path: aerospaceConfigDirectoryName).appending(path: aerospaceConfigFileName),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: aerospaceLegacyConfigDotfileName),
    ]
}

func preferredAerospaceConfigImportUrl() -> URL? {
    aerospaceConfigCandidateUrls().first { FileManager.default.fileExists(atPath: $0.path) }
}

@MainActor
func preferredEditableConfigUrl() -> URL {
    if let configLocation = serverArgs.configLocation {
        return URL(filePath: configLocation)
    }
    if let customConfigUrl = findCustomConfigUrl().urlOrNil {
        return customConfigUrl
    }
    return generatedConfigUrl()
}

func starterConfigText() -> String {
    let starterBindings: [String: String] = [
        ("alt-space", "layout horizontal vertical"),
        ("ctrl-alt-j", "split 1:2"),
        ("ctrl-alt-k", "split 1:1"),
        ("ctrl-alt-l", "split 2:1"),
        ("ctrl-f", "open-sidebar"),
        ("alt-b", "open-sidebar"),
        ("alt-h", "focus left"),
        ("alt-j", "split 1:2"),
        ("alt-k", "split 1:1"),
        ("alt-l", "split 2:1"),
        ("alt-n", "new-tab"),
        ("alt-shift-n", "move-node-to-tab new"),
        ("alt-p", "focus dfs-prev"),
        ("alt-tab", "tab next"),
        ("alt-shift-tab", "tab prev"),
        ("alt-0", "tab 10"),
        ("alt-1", "tab 1"),
        ("alt-2", "tab 2"),
        ("alt-3", "tab 3"),
        ("alt-4", "tab 4"),
        ("alt-5", "tab 5"),
        ("alt-6", "tab 6"),
        ("alt-7", "tab 7"),
        ("alt-8", "tab 8"),
        ("alt-9", "tab 9"),
        ("alt-shift-h", "move left"),
        ("alt-shift-j", "move down"),
        ("alt-shift-k", "move up"),
        ("alt-shift-l", "move right"),
        ("cmd-shift-h", "join-with left"),
        ("cmd-shift-j", "join-with down"),
        ("cmd-shift-k", "join-with up"),
        ("cmd-shift-l", "join-with right"),
        ("cmd-shift-i", "balance-sizes"),
        ("alt-cmd-j", "swap down"),
        ("alt-cmd-k", "swap up"),
        ("alt-shift-t", "layout floating tiling"),
        ("alt-shift-m", "fullscreen"),
        ("ctrl-q", "tab 11"),
        ("ctrl-w", "tab 12"),
        ("ctrl-e", "tab 13"),
        ("ctrl-r", "tab 14"),
        ("ctrl-t", "tab 15"),
        ("ctrl-h", "tab prev"),
        ("ctrl-l", "tab next"),
        ("cmd-ctrl-h", "tab prev"),
        ("cmd-ctrl-l", "tab next"),
        ("alt-shift-0", "move-node-to-tab 10"),
        ("alt-shift-1", "move-node-to-tab 1"),
        ("alt-shift-2", "move-node-to-tab 2"),
        ("alt-shift-3", "move-node-to-tab 3"),
        ("alt-shift-4", "move-node-to-tab 4"),
        ("alt-shift-5", "move-node-to-tab 5"),
        ("alt-shift-6", "move-node-to-tab 6"),
        ("alt-shift-7", "move-node-to-tab 7"),
        ("alt-shift-8", "move-node-to-tab 8"),
        ("alt-shift-9", "move-node-to-tab 9"),
        ("ctrl-shift-h", "move-node-to-tab --focus-follows-window prev"),
        ("ctrl-shift-l", "move-node-to-tab --focus-follows-window next"),
    ].reduce(into: [:]) { result, pair in
        result[pair.0] = pair.1
    }
    let defaultText = (try? String(contentsOf: defaultConfigUrl, encoding: .utf8)) ?? """
        config-version = 3

        [mode.main.binding]
        """
    return updateModeBindingConfig(
        in: defaultText,
        modeName: mainModeId,
        tableKey: "binding",
        managedCommands: [],
        assignments: starterBindings,
    )
}

@MainActor
func ensureBootstrapConfigExistsIfNeeded() throws -> URL? {
    guard serverArgs.configLocation == nil else { return nil }
    let targetUrl = generatedConfigUrl()
    let existingLegacyUrls = preferredLegacyConfigImportUrl().map { [$0] } ?? []
    let aerospaceImportUrl = preferredAerospaceConfigImportUrl()
    if try materializeBootstrapConfigIfNeeded(
        targetUrl: targetUrl,
        existingLegacyUrls: existingLegacyUrls,
        aerospaceImportUrl: aerospaceImportUrl,
    ) {
        return targetUrl
    } else {
        return nil
    }
}

func materializeBootstrapConfigIfNeeded(
    targetUrl: URL,
    existingLegacyUrls: [URL],
    aerospaceImportUrl: URL? = nil,
) throws -> Bool {
    guard !FileManager.default.fileExists(atPath: targetUrl.path) else { return false }
    let parentUrl = targetUrl.deletingLastPathComponent()
    if parentUrl.path != targetUrl.path {
        try FileManager.default.createDirectory(at: parentUrl, withIntermediateDirectories: true)
    }
    if let legacyUrl = existingLegacyUrls.first {
        try FileManager.default.copyItem(at: legacyUrl, to: targetUrl)
    } else if let aerospaceImportUrl {
        let migratedConfig = try migrateAerospaceConfigForWinMux(
            try String(contentsOf: aerospaceImportUrl, encoding: .utf8),
        )
        try migratedConfig.write(to: targetUrl, atomically: true, encoding: .utf8)
    } else {
        try starterConfigText().write(to: targetUrl, atomically: true, encoding: .utf8)
    }
    return true
}

func migrateAerospaceConfigForWinMux(_ rawToml: String) throws -> String {
    _ = try TOMLTable(string: rawToml)

    var migrated = aerospaceKeyboardConfigSections(from: rawToml)
    let literalReplacements = [
        ("AEROSPACE_FOCUSED_WORKSPACE", "WINMUX_FOCUSED_TAB"),
        ("AEROSPACE_PREV_WORKSPACE", "WINMUX_PREV_TAB"),
        ("AEROSPACE_WINDOW_ID", "WINMUX_WINDOW_ID"),
        ("AEROSPACE_WORKSPACE", "WINMUX_TAB"),
        ("accordion-padding", "folder-padding"),
        ("h_accordion", "h_tiles"),
        ("v_accordion", "v_tiles"),
    ]
    for (old, new) in literalReplacements {
        migrated = migrated.replacingOccurrences(of: old, with: new)
    }
    migrated = migrated.replacingRegex(
        #"(?<![A-Za-z0-9_-])accordion(?![A-Za-z0-9_-])"#,
        with: "tiles",
    )
    migrated = migrated.replacingRegex(
        #"(?<![A-Za-z0-9_-])move-node-to-workspace(?![A-Za-z0-9_-])"#,
        with: "move-node-to-tab",
    )
    migrated = migrated.replacingRegex(
        #"(?<![A-Za-z0-9_-])workspace(?![A-Za-z0-9_-])"#,
        with: "tab",
    )
    let baseConfig = migrated.isEmpty
        ? starterConfigText()
        : removingAerospaceKeyboardConfigSections(from: starterConfigText())

    return """
        # Migrated from AeroSpace config by WinMux.
        # WinMux owns this file after import; the AeroSpace source is not read again.
        # Current WinMux defaults are used for WinMux-specific behavior; AeroSpace keyboard sections are preserved below.

        \(baseConfig)
        \(migrated.isEmpty ? "" : "\n# Keyboard configuration imported from AeroSpace.\n\(migrated)")
        """
}

private extension String {
    func replacingRegex(_ pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return self }
        let range = NSRange(startIndex ..< endIndex, in: self)
        return regex.stringByReplacingMatches(in: self, range: range, withTemplate: replacement)
    }
}

private func aerospaceKeyboardConfigSections(from rawToml: String) -> String {
    keyboardConfigSections(from: rawToml, keepMatchingSections: true)
}

private func removingAerospaceKeyboardConfigSections(from rawToml: String) -> String {
    keyboardConfigSections(from: rawToml, keepMatchingSections: false)
}

private func keyboardConfigSections(from rawToml: String, keepMatchingSections: Bool) -> String {
    let lines = rawToml.components(separatedBy: "\n")
    var sections: [[String]] = []
    var current: [String] = []
    var shouldKeepCurrent = !keepMatchingSections

    func flushCurrentSection() {
        if shouldKeepCurrent {
            sections.append(current)
        }
        current = []
        shouldKeepCurrent = false
    }

    for line in lines {
        if isTomlSectionHeader(line) {
            flushCurrentSection()
            current = [line]
            shouldKeepCurrent = isAerospaceKeyboardSectionHeader(line) == keepMatchingSections
        } else {
            current.append(line)
        }
    }
    flushCurrentSection()

    return sections
        .map { sectionLines in
            sectionLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
}

private func isAerospaceKeyboardSectionHeader(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return trimmed == "[key-mapping]" ||
        trimmed == "[mode]" ||
        trimmed.hasPrefix("[mode.") ||
        trimmed.hasPrefix("[[mode.")
}

private func isTomlSectionHeader(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    return (trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]")) ||
        (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
}

func findCustomConfigUrl() -> ConfigFile {
    let candidates: [URL] = if let configLocation = serverArgs.configLocation {
        [URL(filePath: configLocation)]
    } else {
        [generatedConfigUrl()]
    }
    let existingCandidates: [URL] = candidates.filter { (candidate: URL) in FileManager.default.fileExists(atPath: candidate.path) }
    let count = existingCandidates.count
    return switch count {
        case 0: .noCustomConfigExists
        case 1: .file(existingCandidates.first.orDie())
        default: .ambiguousConfigError(existingCandidates)
    }
}

enum ConfigFile {
    case file(URL), ambiguousConfigError(_ candidates: [URL]), noCustomConfigExists

    var urlOrNil: URL? {
        return switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }
}
