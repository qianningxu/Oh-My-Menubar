public struct OpenSidebarCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .openSidebar,
        allowInConfig: true,
        help: """
        USAGE: open-sidebar

        Opens or toggles the Tab sidebar.
        """,
        flags: [:],
        posArgs: [],
    )
}
