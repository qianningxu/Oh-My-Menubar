public struct LayoutCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    fileprivate init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .layout,
        allowInConfig: true,
        help: layout_help_generated,
        flags: [
            "--window-id": optionalWindowIdFlag(),
        ],
        posArgs: [newMandatoryPosArgParser(\.toggleBetween, parseToggleBetween, placeholder: LayoutDescription.unionLiteral)],
    )

    public var toggleBetween: Lateinit<[LayoutDescription]> = .uninitialized

    public init(rawArgs: [String], toggleBetween: [LayoutDescription]) {
        self.commonState = .init(rawArgs.slice)
        self.toggleBetween = .initialized(toggleBetween)
    }

    public var description: String {
        var args = [Self.info.kind.rawValue]
        if let windowId {
            args.append("--window-id")
            args.append(String(windowId))
        }
        args.append(contentsOf: toggleBetween.val.map(\.rawValue))
        return args.joinArgs()
    }

    public enum LayoutDescription: String, CaseIterable, Equatable, Sendable {
        case tabGroup = "tab-group"
        case tiles
        case horizontal, vertical
        case hTabGroup = "h_tab_group"
        case vTabGroup = "v_tab_group"
        case h_tiles, v_tiles
        case tiling, floating
    }

    public static let enabledLayoutLiteral = [
        LayoutDescription.h_tiles.rawValue,
        LayoutDescription.v_tiles.rawValue,
        LayoutDescription.tiles.rawValue,
        LayoutDescription.horizontal.rawValue,
        LayoutDescription.vertical.rawValue,
        LayoutDescription.tiling.rawValue,
        LayoutDescription.floating.rawValue,
    ].joinedCliArgs
}

private func parseToggleBetween(input: PosArgParserInput) -> ParsedCliArgs<[LayoutCmdArgs.LayoutDescription]> {
    let args = input.nonFlagArgs()

    var result: [LayoutCmdArgs.LayoutDescription] = []
    var i = 0
    for arg in args {
        if let layout = arg.parseLayoutDescription() {
            result.append(layout)
        } else {
            return .fail(
                "Can't parse '\(arg)'\nPossible values: \(LayoutCmdArgs.enabledLayoutLiteral)",
                advanceBy: i + 1,
            )
        }
        i += 1
    }

    return .succ(result, advanceBy: args.count)
}

func parseLayoutCmdArgs(_ args: StrArrSlice) -> ParsedCmd<LayoutCmdArgs> {
    parseSpecificCmdArgs(LayoutCmdArgs(rawArgs: args), args).map {
        let normalizedLayouts = dropDisabledOldTopTabGroupLayoutsWhenMixed(withEnabledLayouts: $0.toggleBetween.val)
        check(!normalizedLayouts.isEmpty)
        return $0.copy(\.toggleBetween, .initialized(normalizedLayouts))
    }
}

private func dropDisabledOldTopTabGroupLayoutsWhenMixed(
    withEnabledLayouts layouts: [LayoutCmdArgs.LayoutDescription]
) -> [LayoutCmdArgs.LayoutDescription] {
    let enabledLayouts = layouts.filter { !$0.isOldTopTabGroupLayout }
    return enabledLayouts.isEmpty ? layouts : enabledLayouts
}

extension String {
    fileprivate func parseLayoutDescription() -> LayoutCmdArgs.LayoutDescription? {
        LayoutCmdArgs.LayoutDescription(rawValue: self)
    }
}

extension LayoutCmdArgs.LayoutDescription {
    public var isOldTopTabGroupLayout: Bool {
        switch self {
            case .tabGroup, .hTabGroup, .vTabGroup:
                true
            case .tiles, .horizontal, .vertical, .h_tiles, .v_tiles, .tiling, .floating:
                false
        }
    }
}
