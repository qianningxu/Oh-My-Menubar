import TOMLKit

private let windowTabsParser: [String: any ParserProtocol<WindowTabsConfig>] = [
    "enabled": Parser(\.enabled, parseBool),
    "height": Parser(\.height, parseWindowTabsHeight),
    "tab-labels": Parser(\.tabLabels, parseWindowTabLabels),
]

func parseWindowTabs(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> WindowTabsConfig {
    parseTable(raw, WindowTabsConfig(), windowTabsParser, backtrace, &errors)
}

private func parseWindowTabsHeight(_ raw: TOMLValueConvertible, _ backtrace: TomlBacktrace) -> ParsedToml<Int> {
    parseInt(raw, backtrace)
        .filter(.semantic(backtrace, "Must be greater than 20")) { $0 > 20 }
}

private func parseWindowTabLabels(
    _ raw: TOMLValueConvertible,
    _ backtrace: TomlBacktrace,
    _ errors: inout [TomlParseError],
) -> [String: String] {
    guard let rawTable = raw.table else {
        errors += [expectedActualTypeError(expected: .table, actual: raw.type, backtrace)]
        return [:]
    }
    var result: [String: String] = [:]
    for (key, rawLabel) in rawTable {
        if let label = parseString(rawLabel, backtrace + .key(key)).getOrNil(appendErrorTo: &errors) {
            result[key] = label
        }
    }
    return result
}
