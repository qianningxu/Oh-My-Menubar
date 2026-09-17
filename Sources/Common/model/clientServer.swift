import Foundation

// TO EVERYONE REVERSE-ENGINEERING THE PROTOCOL
// client-server socket API is not public yet.
// Tracking issue for making it public: https://github.com/nikitabobko/WinMux/issues/1513
public struct ServerAnswer: Codable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public var stderr: String
    public let serverVersionAndHash: String

    public init(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = "",
        serverVersionAndHash: String,
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.serverVersionAndHash = serverVersionAndHash
    }
}

// TO EVERYONE REVERSE-ENGINEERING THE PROTOCOL
// client-server socket API is not public yet.
// Tracking issue for making it public: https://github.com/nikitabobko/WinMux/issues/1513
public struct ClientRequest: Codable, Sendable, ConvenienceCopyable, Equatable {
    // periphery:ignore - Unused. keep it for API compatibility with old servers for a couple of version
    public var command: String? = nil

    public let args: [String]
    public let stdin: String

    // Double Optional to encode explicit null into JSON
    public var windowId: UInt32??  // Please forward WINMUX_WINDOW_ID env variable here
    // Please forward WINMUX_TAB here. Legacy clients may still use WINMUX_WORKSPACE.
    public var workspace: String??

    public init(
        args: [String],
        stdin: String,
        windowId: UInt32?,
        workspace: String?,
    ) {
        self.args = args
        self.stdin = stdin
        self.windowId = .some(windowId)
        self.workspace = .some(workspace)
    }

    public static func decodeJson(_ data: Data) -> Result<ClientRequest, String> {
        Result { try JSONDecoder().decode(Self.self, from: data) }.mapError { $0.localizedDescription }
    }

    enum CodingKeys: String, CodingKey {
        case args
        case stdin
        case windowId
        case workspace
        case tab
    }

    public init(from decoder: any Decoder) throws {
        let data = try ClientRequestData.init(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let tab = try container.decodeIfPresent(String?.self, forKey: .tab)
        var raw = ClientRequest(
            args: data.args,
            stdin: data.stdin,
            windowId: data.windowId.flatMap { $0 },
            workspace: data.workspace.flatMap { $0 } ?? tab.flatMap { $0 },
        )
        if !container.contains(.windowId) { raw.windowId = nil }
        if !container.contains(.workspace), !container.contains(.tab) { raw.workspace = nil }
        self = raw
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(args, forKey: .args)
        try container.encode(stdin, forKey: .stdin)
        switch windowId {
            case .none:
                break
            case .some(.none):
                try container.encodeNil(forKey: .windowId)
            case .some(.some(let value)):
                try container.encode(value, forKey: .windowId)
        }
        switch workspace {
            case .none:
                break
            case .some(.none):
                try container.encodeNil(forKey: .tab)
                try container.encodeNil(forKey: .workspace)
            case .some(.some(let value)):
                try container.encode(value, forKey: .tab)
                try container.encode(value, forKey: .workspace)
        }
    }
}

private struct ClientRequestData: Codable, Sendable {
    var args: [String]
    var stdin: String
    var windowId: UInt32??
    var workspace: String??
}
