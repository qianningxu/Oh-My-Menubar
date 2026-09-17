@testable import AppBundle
import Common
import XCTest

final class SubscribeCmdArgsTest: XCTestCase {
    func testParseValidEvents() {
        let result = parseSubscribeCmdArgs(["focus-changed", "focused-tab-changed", "mode-changed"].slice)
        switch result {
            case .cmd(let args):
                assertEquals(args.events, Set([.focusChanged, .tabChanged, .modeChanged]))
            case .help, .failure:
                XCTFail("Expected success")
        }
    }

    func testParseLegacyFocusedWorkspaceEventAsTabAlias() {
        let result = parseSubscribeCmdArgs(["focused-workspace-changed"].slice)
        switch result {
            case .cmd(let args):
                assertEquals(args.events, Set([.tabChanged]))
            case .help, .failure:
                XCTFail("Expected success")
        }
    }

    func testParseAllFlag() {
        let result = parseSubscribeCmdArgs(["--all"].slice)
        switch result {
            case .cmd(let args):
                assertEquals(args.events, Set(ServerEventType.allCases))
            case .help, .failure:
                XCTFail("Expected success")
        }
    }

    func testParseUnknownEvent() {
        let result = parseSubscribeCmdArgs(["unknown-event"].slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, """
                    ERROR: Can't parse 'unknown-event'.
                           Possible values: (focus-changed|focused-monitor-changed|focused-tab-changed|mode-changed|window-detected|binding-triggered)
                    """)
        }
    }

    func testParseDuplicateEvent() {
        let result = parseSubscribeCmdArgs(["focus-changed", "focus-changed"].slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, "ERROR: Duplicate event 'focus-changed'")
        }
    }

    func testParseDuplicateLegacyAndTabEventAliases() {
        let result = parseSubscribeCmdArgs(["focused-tab-changed", "focused-workspace-changed"].slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, "ERROR: Duplicate event 'focused-workspace-changed'")
        }
    }

    func testParseNoEvents() {
        let result = parseSubscribeCmdArgs([String]().slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, "Either --all or at least one <event> must be specified")
        }
    }

    func testParseAllWithEventsConflict() {
        let result = parseSubscribeCmdArgs(["--all", "focus-changed"].slice)
        switch result {
            case .cmd, .help:
                XCTFail("Expected failure")
            case .failure(let err):
                assertEquals(err, "--all conflicts with specifying individual events")
        }
    }
}
