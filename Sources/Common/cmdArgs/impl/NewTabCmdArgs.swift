public struct NewTabCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .newTab,
        allowInConfig: true,
        help: """
        USAGE: new-tab

        Opens a fresh empty Tab on the focused monitor.
        """,
        flags: [:],
        posArgs: [],
    )
}
