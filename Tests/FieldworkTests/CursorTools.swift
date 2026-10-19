// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Made-up tools for the Cursor tests, each passing its identity as values: a name, a server, the events its hooks register for and the flag its handler takes.
struct CursorTools {
    let tool: FieldworkTool
    let installer: CursorHookInstaller

    var install: CursorInstall {
        installer.cursor
    }

    var mcp: CursorMcpFile {
        install.mcp
    }

    var hooks: CursorHooksFile {
        install.hooks
    }

    init(name: String, arguments: [String] = ["mcp"], agentFlag: String = "--agent cursor") {
        tool = FieldworkTool(name: name, hookSubcommands: ["session-start", "pre-tool-use", "post-tool-use"])
        let hooks = CursorHooksFile(
            tool: tool,
            agentFlag: agentFlag,
            hooks: [
                CursorHooksFile.Hook(event: "sessionStart", subcommand: "session-start"),
                CursorHooksFile.Hook(event: "preToolUse", subcommand: "pre-tool-use"),
                CursorHooksFile.Hook(event: "postToolUse", subcommand: "post-tool-use"),
                CursorHooksFile.Hook(event: "postToolUseFailure", subcommand: "post-tool-use"),
            ]
        )
        let install = CursorInstall(
            mcp: CursorMcpFile(server: ClaudeMcpServer(tool: tool, arguments: arguments)),
            hooks: hooks,
            directoryFlag: "--cursor-dir"
        )
        installer = CursorHookInstaller(
            cursor: install,
            unsupported: ["unsupported on Cursor: \(name) audit — no documented transcript format"],
            experimental: "experimental: not verified in a live Cursor"
        )
    }

    static let gizmo = CursorTools(name: "gizmo")
    static let widget = CursorTools(name: "widget", arguments: ["serve"])

    /// `text` reserialized the way a merge writes a file, so a fixture and a merge's output compare byte for byte.
    static func canonical(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let object = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], sourceLocation: sourceLocation)
        return try CursorConfigJSON.encode(object)
    }

    static func object(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }
}
