public struct ReorderWorkspaceCmdArgs: CmdArgs {
    /*conforms*/ public var commonState: CmdArgsCommonState
    public init(rawArgs: StrArrSlice) { self.commonState = .init(rawArgs) }
    public static let parser: CmdParser<Self> = .init(
        kind: .reorderWorkspace,
        allowInConfig: true,
        help: reorder_workspace_help_generated,
        flags: [
            "--before": ArgParser(\.beforeTarget, upcastArgParserFun(parseWorkspaceNameSubArg)),
            "--after": ArgParser(\.afterTarget, upcastArgParserFun(parseWorkspaceNameSubArg)),
        ],
        posArgs: [
            newMandatoryPosArgParser(\.source, parseReorderWorkspaceSource, placeholder: "<tab-name>"),
        ],
        conflictingOptions: [
            ["--before", "--after"],
        ],
    )

    public var source: Lateinit<WorkspaceName> = .uninitialized
    public var beforeTarget: WorkspaceName?
    public var afterTarget: WorkspaceName?
}

func parseReorderWorkspaceCmdArgs(_ args: StrArrSlice) -> ParsedCmd<ReorderWorkspaceCmdArgs> {
    parseSpecificCmdArgs(ReorderWorkspaceCmdArgs(rawArgs: args), args)
        .filter("Either --before or --after is required") {
            $0.beforeTarget != nil || $0.afterTarget != nil
        }
}

private func parseReorderWorkspaceSource(i: PosArgParserInput) -> ParsedCliArgs<WorkspaceName> {
    .init(WorkspaceName.parse(i.arg), advanceBy: 1)
}
