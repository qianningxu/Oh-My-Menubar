import AppKit
import Common

struct ConfigCommand: Command {
    let args: ConfigCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> Bool {
        switch args.mode {
            case .getKey(let key):
                return getKey(io, args: args, key: key)
            case .majorKeys:
                let modeKeys = config.modes.keys.sorted().flatMap { ["mode.\($0).binding", "mode.\($0).binding-tap"] }
                let out = """
                    .
                    tab-sidebar
                    window-tabs
                    mode
                    \(modeKeys.joined(separator: "\n"))
                    """
                return io.out(out)
            case .allKeys:
                let configMap = buildConfigMap()
                var allKeys: [String] = []
                configMap.dumpAllKeysRecursive(path: ".", result: &allKeys)
                return io.out(allKeys.joined(separator: "\n"))
            case .configPath:
                return io.out(configUrl.absoluteURL.path)
        }
    }
}

extension String {
    fileprivate func toKeyPath() -> Result<[String], String> {
        if self == "." { return .success([]) }
        if isEmpty { return .failure("Invalid empty key") }
        if self.contains("..") { return .failure("Invalid key '\(self)'") }
        if self.hasSuffix(".") { return .failure("Invalid key '\(self)'") }
        return .success(self.split(separator: ".", omittingEmptySubsequences: false).map(String.init))
    }
}

@MainActor private func getKey(_ io: CmdIo, args: ConfigCmdArgs, key: String) -> Bool {
    let keyPath: [String]
    switch key.toKeyPath() {
        case .success(let _keyPath): keyPath = _keyPath
        case .failure(let error):
            return io.err(error)
    }
    let canonicalKeyPath = canonicalConfigKeyPath(keyPath)
    var configMap: ConfigMapValue
    switch buildConfigMap().find(keyPath: canonicalKeyPath.slice) {
        case .success(let value):
            configMap = value
        case .failure(let error):
            return io.err(error)
    }
    if args.keys {
        switch configMap {
            case .scalar(let scalar):
                return io.err("--keys flag cannot be applied to scalar object '\(scalar)'")
            case .map(let map):
                configMap = .array(map.keys.map { .scalar(.string($0)) })
            case .array(let array):
                configMap = .array((0 ..< array.count).map { .scalar(.int($0)) })
        }
    }
    if args.json {
        if let json = JSONEncoder.winMuxDefault.encodeToString(configMap) {
            return io.out(json)
        } else {
            return io.err("Can't convert json Data to String")
        }
    } else {
        switch configMap {
            case .scalar(let scalar):
                return io.out(scalar.describe)
            case .map:
                return io.err("Complicated objects can be printed only with --json flag. " +
                    "Alternatively, you can try to inspect keys of the object with --keys flag")
            case .array(let array):
                let plainArray: Result<[String], String> = array.mapAllOrFailure {
                    switch $0 {
                        case .scalar(let scalar): .success(scalar.describe)
                        default: .failure("Printing array of non-string objects is supported only with --json flag." +
                                "Alternatively, you can try to inspect keys of the object with --keys flag")
                    }
                }
                return switch plainArray {
                    case .success(let array): io.out(array.sorted().joined(separator: "\n"))
                    case .failure(let error): io.err(error)
                }
        }
    }
}

private func canonicalConfigKeyPath(_ keyPath: [String]) -> [String] {
    guard keyPath.first == "workspace-sidebar" else { return keyPath }
    var canonical = keyPath
    canonical[0] = "tab-sidebar"
    return canonical
}

extension ConfigMapValue {
    func find(keyPath: StrArrSlice) -> Result<ConfigMapValue, String> {
        if let key = keyPath.first {
            switch self {
                case .scalar(let scalar):
                    return .failure("Can't dereference scalar value '\(scalar.describe)'")
                case .map(let map):
                    if let child = map[key] {
                        return child.find(keyPath: keyPath.slice(1...).orDie())
                    } else {
                        return .failure("No value at key token '\(key)'")
                    }
                case .array(let array):
                    if let key = Int(key) {
                        if let child = array.getOrNil(atIndex: key) {
                            return child.find(keyPath: keyPath.slice(1...).orDie())
                        } else {
                            return .failure("Index out of bounds. Index: \(key), Size: \(array.count)")
                        }
                    } else {
                        return .failure("Can't convert key token '\(key)' to Int")
                    }
            }
        } else {
            return .success(self)
        }
    }

    func dumpAllKeysRecursive(path: String, result: inout [String]) {
        result.append(path)
        switch self {
            case .scalar: break
            case .map(let map):
                for (key, value) in map {
                    let path = path == "." ? key : path + "." + key
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
            case .array(let array):
                for (index, value) in array.enumerated() {
                    let path = path == "." ? String(index) : path + "." + String(index)
                    value.dumpAllKeysRecursive(path: path, result: &result)
                }
        }
    }
}

extension [Command] {
    var prettyDescription: String {
        map { $0.args.description }.joined(separator: "; ")
    }
}

@MainActor func buildConfigMap() -> ConfigMapValue {
    let mode = config.modes.mapValues { (mode: Mode) -> ConfigMapValue in
        var keyNotationToScript: [String: ConfigMapValue] = [:]
        for binding in mode.bindings.values {
            keyNotationToScript[binding.descriptionWithKeyNotation] =
                .scalar(.string(binding.commands.prettyDescription))
        }
        var tapKeyNotationToScript: [String: ConfigMapValue] = [:]
        for binding in mode.tapBindings.values {
            tapKeyNotationToScript[binding.descriptionWithKeyNotation] =
                .scalar(.string(binding.commands.prettyDescription))
        }
        return .map([
            "binding": .map(keyNotationToScript),
            "binding-tap": .map(tapKeyNotationToScript),
        ])
    }
    return .map([
        "mode": .map(mode),
        "tab-sidebar": workspaceSidebarConfigMap(config.workspaceSidebar),
        "window-tabs": windowTabsConfigMap(config.windowTabs),
        "enable-projects": .scalar(.bool(config.enableProjects)),
    ])
}

private func windowTabsConfigMap(_ config: WindowTabsConfig) -> ConfigMapValue {
    .map([
        "enabled": .scalar(.bool(config.enabled)),
        "height": .scalar(.int(config.height)),
    ])
}

private func workspaceSidebarConfigMap(_ config: WorkspaceSidebarConfig) -> ConfigMapValue {
    .map([
        "widgets": .array(config.resolvedWidgets.map(workspaceSidebarWidgetConfigMap)),
    ])
}

private func workspaceSidebarWidgetConfigMap(_ widget: WorkspaceSidebarWidgetConfig) -> ConfigMapValue {
    var map: [String: ConfigMapValue] = [
        "id": .scalar(.string(widget.id)),
        "type": .scalar(.string(widget.type.rawValue)),
        "enabled": .scalar(.bool(widget.enabled)),
    ]
    switch widget.type {
        case .builtInTodoList:
            break
        case .builtInTasks:
            map["tasks-path"] = .scalar(.string(widget.tasksPath ?? defaultWorkspaceSidebarTasksPath))
        case .builtInTimeDate:
            map["show-date"] = .scalar(.bool(widget.showDate))
        case .builtInTodayFocus:
            map["entries-path"] = .scalar(.string(widget.entriesPath ?? defaultWorkspaceSidebarTogglEntriesPath))
        case .builtInTogglWeeklyFocus, .builtInTogglWeekFocus:
            map["entries-path"] = .scalar(.string(widget.entriesPath ?? defaultWorkspaceSidebarTogglEntriesPath))
            map["target-date"] = .scalar(.string(widget.targetDate ?? defaultWorkspaceSidebarTogglWeeklyFocusTargetDate))
        case .builtInPeriodHeatmap:
            map["entries-path"] = .scalar(.string(widget.entriesPath ?? defaultWorkspaceSidebarPeriodEntriesPath))
        case .builtInSpendingCategories:
            map["entries-path"] = .scalar(.string(widget.entriesPath ?? defaultWorkspaceSidebarSpendingEntriesPath))
            map["days"] = .scalar(.int(widget.days ?? defaultWorkspaceSidebarSpendingDays))
        case .builtInScheduleHeatmap:
            map["schedule-path"] = .scalar(.string(widget.schedulePath ?? defaultWorkspaceSidebarSchedulePath))
            map["toggl-entries-path"] = .scalar(.string(widget.togglEntriesPath ?? defaultWorkspaceSidebarTogglEntriesPath))
            map["deviation-path"] = .scalar(.string(widget.deviationPath ?? defaultWorkspaceSidebarDeviationPath))
            map["days"] = .scalar(.int(widget.days ?? defaultWorkspaceSidebarScheduleHeatmapDays))
        case .plugin:
            if let bundle = widget.bundle {
                map["bundle"] = .scalar(.string(bundle))
            }
    }
    if let rotationGroup = widget.rotationGroup {
        map["rotation-group"] = .scalar(.string(rotationGroup))
    }
    if let rotationIntervalSeconds = widget.rotationIntervalSeconds {
        map["rotation-interval-seconds"] = .scalar(.int(rotationIntervalSeconds))
    }
    return .map(map)
}

enum ConfigScalarValue: Encodable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    var describe: String {
        return switch self {
            case .string(let string): string
            case .int(let int): String(int)
            case .bool(let bool): String(bool)
        }
    }

    func encode(to encoder: Encoder) throws {
        let value: Encodable = switch self {
            case .string(let string): string
            case .int(let int): int
            case .bool(let bool): bool
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum ConfigMapValue: Encodable {
    case scalar(ConfigScalarValue)
    case map([String: ConfigMapValue])
    case array([ConfigMapValue])

    func encode(to encoder: Encoder) throws {
        let value: Encodable = switch self {
            case .scalar(let scalar): scalar
            case .map(let map): map
            case .array(let array): array
        }
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

extension ConfigMapValue: Equatable {
    static func == (lhs: ConfigMapValue, rhs: ConfigMapValue) -> Bool {
        switch (lhs, rhs) {
            case (.scalar(let lhs), .scalar(let rhs)):
                lhs == rhs
            case (.map(let lhs), .map(let rhs)):
                lhs == rhs
            case (.array(let lhs), .array(let rhs)):
                lhs == rhs
            default:
                false
        }
    }
}
