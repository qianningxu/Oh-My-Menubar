import AppKit
import Common
import HotKey
import TOMLKit
import OrderedCollections

@MainActor
func readConfig(forceConfigUrl: URL? = nil) -> Result<(Config, URL), String> {
    let configUrl: URL
    if let forceConfigUrl {
        configUrl = forceConfigUrl
    } else {
        switch findCustomConfigUrl() {
            case .file(let url): configUrl = url
            case .noCustomConfigExists: configUrl = defaultConfigUrl
            case .ambiguousConfigError(let candidates):
                let msg = """
                    Ambiguous config error. Several configs found:
                    \(candidates.map(\.path).joined(separator: "\n"))
                    """
                return .failure(msg)
        }
    }
    let configText = try? String(contentsOf: configUrl, encoding: .utf8)
    let canonicalConfigText = configText.map(canonicalWorkspaceSidebarConfigRoots)
    // Repair the legacy/new mixed-root configuration produced by older
    // sidebar edits before parsing.  Parsing the canonical text keeps the
    // running app safe even if this best-effort write cannot succeed.
    if let configText, let canonicalConfigText, configText != canonicalConfigText {
        try? canonicalConfigText.write(to: configUrl, atomically: true, encoding: .utf8)
    }
    let (parsedConfig, errors) = canonicalConfigText.map(parseConfig) ?? (defaultConfig, [])

    if errors.isEmpty {
        return .success((parsedConfig, configUrl))
    } else {
        let msg = """
            Failed to parse \(configUrl.absoluteURL.path)

            \(errors.map(\.description).joined(separator: "\n\n"))
            """
        return .failure(msg)
    }
}

private let keyMappingConfigRootKey = "key-mapping"
private let modeConfigRootKey = "mode"
private let persistentTabsKey = "persistent-tabs"
private let legacyPersistentWorkspacesKey = "persistent-workspaces"
private let tabToMonitorForceAssignmentKey = "tab-to-monitor-force-assignment"
private let legacyWorkspaceToMonitorForceAssignmentKey = "workspace-to-monitor-force-assignment"
private let execOnTabChangeKey = "exec-on-tab-change"
private let legacyExecOnWorkspaceChangeKey = "exec-on-workspace-change"
private let tabSidebarConfigRootKey = "tab-sidebar"
private let legacyWorkspaceSidebarConfigRootKey = "workspace-sidebar"

// For every new config option you add, think:
// 1. Does it make sense to have different value
// 2. Prefer commands and commands flags over toml options if possible
private let configParser: [String: any ParserProtocol<Config>] = [
    "config-version": Parser(\.configVersion, parseConfigVersion),

    "after-login-command": Parser(\.afterLoginCommand, parseAfterLoginCommand),
    "after-startup-command": Parser(\.afterStartupCommand) { parseCommandOrCommands($0).toParsedToml($1) },

    "on-focus-changed": Parser(\.onFocusChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-mode-changed": Parser(\.onModeChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    "on-focused-monitor-changed": Parser(\.onFocusedMonitorChanged) { parseCommandOrCommands($0).toParsedToml($1) },
    // "on-focused-workspace-changed": Parser(\.onFocusedWorkspaceChanged, { parseCommandOrCommands($0).toParsedToml($1) }),

    "enable-normalization-flatten-containers": Parser(\.enableNormalizationFlattenContainers, parseBool),
    "enable-normalization-opposite-orientation-for-nested-containers": Parser(\.enableNormalizationOppositeOrientationForNestedContainers, parseBool),

    "default-root-container-layout": Parser(\.defaultRootContainerLayout, parseLayout),
    "default-root-container-orientation": Parser(\.defaultRootContainerOrientation, parseDefaultContainerOrientation),

    "start-at-login": Parser(\.startAtLogin, parseBool),
    "auto-reload-config": Parser(\.autoReloadConfig, parseBool),
    "enable-projects": Parser(\.enableProjects, parseBool),
    "automatically-unhide-macos-hidden-apps": Parser(\.automaticallyUnhideMacosHiddenApps, parseBool),
    "shortcuts-preset": Parser(\.shortcutsPreset, parseShortcutsPreset),
    "folder-padding": Parser(\.tabGroupPadding, parseInt),
    persistentTabsKey: Parser(\.persistentWorkspaces, parsePersistentTabs),
    legacyPersistentWorkspacesKey: Parser(\.persistentWorkspaces, parsePersistentTabs),
    execOnTabChangeKey: Parser(\.execOnWorkspaceChange, parseArrayOfStrings),
    legacyExecOnWorkspaceChangeKey: Parser(\.execOnWorkspaceChange, parseArrayOfStrings),
    "exec": Parser(\.execConfig, parseExecConfig),

    keyMappingConfigRootKey: Parser(\.keyMapping, skipParsing(Config().keyMapping)), // Parsed manually
    modeConfigRootKey: Parser(\.modes, skipParsing(Config().modes)), // Parsed manually

    "auto-add-new-windows-to-folder": Parser(\.autoAddNewWindowsToTabGroup, parseBool),
    "gaps": Parser(\.gaps, parseGaps),
    tabSidebarConfigRootKey: Parser(\.workspaceSidebar, parseWorkspaceSidebar),
    legacyWorkspaceSidebarConfigRootKey: Parser(\.workspaceSidebar, parseWorkspaceSidebar),
    "window-tabs": Parser(\.windowTabs, parseWindowTabs),
    tabToMonitorForceAssignmentKey: Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    legacyWorkspaceToMonitorForceAssignmentKey: Parser(\.workspaceToMonitorForceAssignment, parseWorkspaceToMonitorAssignment),
    "on-window-detected": Parser(\.onWindowDetected, parseOnWindowDetectedArray),

    // Deprecated
    "tab-group-padding": Parser(\.tabGroupPadding, parseInt),
    "auto-add-new-windows-to-tab-group": Parser(\.autoAddNewWindowsToTabGroup, parseBool),
    "non-empty-workspaces-root-containers-layout-on-startup": Parser(\._nonEmptyWorkspacesRootContainersLayoutOnStartup, parseStartupRootContainerLayout),
    "indent-for-nested-containers-with-the-same-orientation": Parser(\._indentForNestedContainersWithTheSameOrientation, parseIndentForNestedContainersWithTheSameOrientation),
]

extension ParsedCmd where T == any Command {
    fileprivate func toEither() -> Parsed<T> {
        return switch self {
            case .cmd(let a):
                a.info.allowInConfig
                    ? .success(a)
                    : .failure("Command '\(a.info.kind.rawValue)' cannot be used in config")
            case .help(let a): .failure(a)
            case .failure(let a): .failure(a)
        }
    }
}

extension Command {
    fileprivate var isMacOsNativeCommand: Bool { // Problem ID-B6E178F2
        self is MacosNativeMinimizeCommand || self is MacosNativeFullscreenCommand
    }
}

func parseAfterLoginCommand(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[any Command]> {
    if let array = raw.array, array.count == 0 {
        return .success([])
    }
    let msg = "after-login-command is deprecated since WinMux 0.19.0. https://github.com/nikitabobko/WinMux/issues/1482"
    return .failure(.semantic(backtrace, msg))
}

func parseCommandOrCommands(_ raw: TOMLValueConvertible) -> Parsed<[any Command]> {
    if let rawString = raw.string {
        return parseCommand(rawString).toEither().map { [$0] }
    } else if let rawArray = raw.array {
        let commands: Parsed<[any Command]> = (0 ..< rawArray.count).mapAllOrFailure { index in
            let rawString: String = rawArray[index].string ?? expectedActualTypeError(expected: .string, actual: rawArray[index].type)
            return parseCommand(rawString).toEither()
        }
        return commands.filter("macos-native-* commands are only allowed to be the last commands in the list") {
            !$0.dropLast().contains(where: { $0.isMacOsNativeCommand })
        }
    } else {
        return .failure(expectedActualTypeError(expected: [.string, .array], actual: raw.type))
    }
}

@MainActor func parseConfig(_ rawToml: String) -> (config: Config, errors: [TomlParseError]) { // todo change return value to Result
    let rawTable: TOMLTable
    do {
        rawTable = try TOMLTable(string: rawToml)
    } catch let e as TOMLParseError {
        return (defaultConfig, [.syntax(e.debugDescription)])
    } catch let e {
        return (defaultConfig, [.syntax(e.localizedDescription)])
    }

    var errors: [TomlParseError] = []

    var config = rawTable.parseTable(Config(), configParser, .emptyRoot, &errors)

    if let mapping = rawTable[keyMappingConfigRootKey].flatMap({ parseKeyMapping($0, .rootKey(keyMappingConfigRootKey), &errors) }) {
        config.keyMapping = mapping
    }

    // Parse modeConfigRootKey after keyMappingConfigRootKey
    if let modes = rawTable[modeConfigRootKey].flatMap({ parseModes($0, .rootKey(modeConfigRootKey), &errors, config.keyMapping.resolve()) }) {
        config.modes = modes
    }
    applyShortcutsPreset(&config, mapping: config.keyMapping.resolve(), errors: &errors)
    let shouldValidateMainMode = rawTable.contains(key: modeConfigRootKey) || config.shortcutsPreset != .none
    if shouldValidateMainMode && !config.modes.keys.contains(mainModeId) {
        errors += [.semantic(.rootKey(modeConfigRootKey), "Please specify '\(mainModeId)' mode")]
    }
    if rawTable.contains(key: persistentTabsKey), rawTable.contains(key: legacyPersistentWorkspacesKey) {
        errors += [.semantic(
            .rootKey(persistentTabsKey),
            "Use either '\(persistentTabsKey)' or legacy '\(legacyPersistentWorkspacesKey)', not both"
        )]
    }
    if rawTable.contains(key: tabToMonitorForceAssignmentKey),
       rawTable.contains(key: legacyWorkspaceToMonitorForceAssignmentKey)
    {
        errors += [.semantic(
            .rootKey(tabToMonitorForceAssignmentKey),
            "Use either '\(tabToMonitorForceAssignmentKey)' or legacy '\(legacyWorkspaceToMonitorForceAssignmentKey)', not both"
        )]
    }
    if rawTable.contains(key: execOnTabChangeKey),
       rawTable.contains(key: legacyExecOnWorkspaceChangeKey)
    {
        errors += [.semantic(
            .rootKey(execOnTabChangeKey),
            "Use either '\(execOnTabChangeKey)' or legacy '\(legacyExecOnWorkspaceChangeKey)', not both"
        )]
    }
    if rawTable.contains(key: tabSidebarConfigRootKey),
       rawTable.contains(key: legacyWorkspaceSidebarConfigRootKey)
    {
        errors += [.semantic(
            .rootKey(tabSidebarConfigRootKey),
            "Use either '\(tabSidebarConfigRootKey)' or legacy '\(legacyWorkspaceSidebarConfigRootKey)', not both"
        )]
    }

    if config.configVersion <= 1 {
        for key in [persistentTabsKey, legacyPersistentWorkspacesKey] where rawTable.contains(key: key) {
            errors += [.semantic(.rootKey(key), "This config option is only available since 'config-version = 2'")]
        }
        config.persistentWorkspaces = (config.modes.values.lazy
            .flatMap { (mode: Mode) -> [HotkeyBinding] in Array(mode.bindings.values) }
            .flatMap { (binding: HotkeyBinding) -> [String] in
                binding.commands.filterIsInstance(of: WorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw } +
                    binding.commands.filterIsInstance(of: MoveNodeToWorkspaceCommand.self).compactMap { $0.args.target.val.workspaceNameOrNil()?.raw }
            }
            + (config.workspaceToMonitorForceAssignment).keys)
            .toOrderedSet()
    }

    if config.enableNormalizationFlattenContainers {
        let containsSplitCommand = config.modes.values.lazy.flatMap { $0.bindings.values }
            .flatMap { $0.commands }
            .contains { ($0 as? SplitCommand).map { $0.args.arg.val.leftFraction == nil } ?? false }
        if containsSplitCommand {
            errors += [.semantic(
                .emptyRoot, // todo Make 'split' + flatten normalization prettier
                """
                The config contains:
                1. usage of 'split' command
                2. enable-normalization-flatten-containers = true
                These two settings don't play nicely together. 'split' command has no effect when enable-normalization-flatten-containers is disabled.

                My recommendation: keep the normalizations enabled, and prefer 'join-with' over 'split'.
                """,
            )]
        }
    }
    if config.configVersion < 3 {
        config.workspaceSidebar.folderLabels.merge(config.workspaceSidebar.projectLabels) { current, _ in current }
        config.workspaceSidebar.folderColors.merge(config.workspaceSidebar.projectColors) { current, _ in current }
        config.workspaceSidebar.projectLabels = [workspaceProjectDefaultId.rawValue: "Main"]
        config.workspaceSidebar.projectColors = [:]
    }
    return (config, errors)
}

func parseIndentForNestedContainersWithTheSameOrientation(
    _ _: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
) -> ParsedToml<Void> {
    let msg = "Deprecated. Please drop it from the config. See https://github.com/nikitabobko/WinMux/issues/96"
    return .failure(.semantic(backtrace, msg))
}

func parseConfigVersion(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    let min = 1
    let max = 3
    return parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be in [\(min), \(max)] range")) { (min ... max).contains($0) }
}

func parseInt(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    raw.int.orFailure(expectedActualTypeError(expected: .int, actual: raw.type, backtrace))
}

func parseString(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<String> {
    raw.string.orFailure(expectedActualTypeError(expected: .string, actual: raw.type, backtrace))
}

func parseSimpleType<T>(_ raw: TOMLValueConvertible) -> T? {
    (raw.int as? T) ?? (raw.string as? T) ?? (raw.bool as? T)
}

func parseTomlArray(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<TOMLArray> {
    raw.array.orFailure(expectedActualTypeError(expected: .array, actual: raw.type, backtrace))
}

func parseTable<T: ConvenienceCopyable>(
    _ raw: TOMLValueConvertible,
    _ initial: T,
    _ fieldsParser: [String: any ParserProtocol<T>],
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> T {
    guard let table = raw.table else {
        errors.append(expectedActualTypeError(expected: .table, actual: raw.type, backtrace))
        return initial
    }
    return table.parseTable(initial, fieldsParser, backtrace, &errors)
}

private func parseStartupRootContainerLayout(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Void> {
    parseString(raw, backtrace)
        .filter(.semantic(backtrace, "'non-empty-workspaces-root-containers-layout-on-startup' is deprecated. Please drop it from your config")) { raw in raw == "smart" }
        .map { _ in () }
}

private func parseLayout(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Layout> {
    parseString(raw, backtrace)
        .flatMap { $0.parseLayout().orFailure(.semantic(backtrace, "Can't parse layout '\($0)'")) }
}

private func parseShortcutsPreset(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<ShortcutsPreset> {
    parseString(raw, backtrace)
        .flatMap { rawValue in
            ShortcutsPreset(rawValue: rawValue)
                .orFailure(.semantic(backtrace, "Can't parse shortcuts preset '\(rawValue)'. Possible values: (none|rectangle)"))
        }
}

@MainActor
private func applyShortcutsPreset(_ config: inout Config, mapping: [String: Key], errors: inout [TomlParseError]) {
    guard config.shortcutsPreset == .rectangle else { return }
    errors += [.semantic(.rootKey("shortcuts-preset"), "The 'rectangle' shortcuts preset has been removed")]
}

private func skipParsing<T: Sendable>(_ value: T) -> @Sendable (_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<T> {
    { _, _ in .success(value) }
}

private func parsePersistentTabs(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<OrderedSet<String>> {
    parseArrayOfStrings(raw, backtrace)
        .flatMap { arr in
            let set = arr.toOrderedSet()
            return set.count == arr.count ? .success(set) : .failure(.semantic(backtrace, "Contains duplicated tab names"))
        }
}

private func parseArrayOfStrings(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<[String]> {
    parseTomlArray(raw, backtrace)
        .flatMap { arr in
            arr.enumerated().mapAllOrFailure { (index, elem) in
                parseString(elem, backtrace + .index(index))
            }
        }
}

private func parseDefaultContainerOrientation(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<DefaultContainerOrientation> {
    parseString(raw, backtrace).flatMap {
        DefaultContainerOrientation(rawValue: $0)
            .orFailure(.semantic(backtrace, "Can't parse default container orientation '\($0)'"))
    }
}

extension Parsed where Failure == String {
    func toParsedToml(_ backtrace: TomlBacktrace) -> ParsedToml<Success> {
        mapError { .semantic(backtrace, $0) }
    }
}

func parseBool(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Bool> {
    raw.bool.orFailure(expectedActualTypeError(expected: .bool, actual: raw.type, backtrace))
}
