// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Made-up tools for the Codex tests, each passing its identity as values: a name and the hooks it registers.
struct CodexTools {
    let tool: FieldworkTool
    let file: CodexHooksFile

    init(name: String, hooks: [CodexHooksFile.Hook]) {
        tool = FieldworkTool(name: name, hookSubcommands: Set(hooks.map(\.subcommand)).sorted())
        file = CodexHooksFile(tool: tool, hooks: hooks)
    }

    static let gizmo = CodexTools(name: "gizmo", hooks: [
        CodexHooksFile.Hook(event: "SessionStart", subcommand: "session-start", matcher: nil),
        CodexHooksFile.Hook(event: "PreToolUse", subcommand: "pre-tool-use", matcher: "*"),
        CodexHooksFile.Hook(event: "PostToolUse", subcommand: "post-tool-use", matcher: "*"),
    ])

    /// The same events as ``gizmo`` with other subcommands, the set a switch between two of a tool's hook sets moves to.
    static let gizmoOther = CodexTools(name: "gizmo", hooks: [
        CodexHooksFile.Hook(event: "SessionStart", subcommand: "begin", matcher: nil),
        CodexHooksFile.Hook(event: "PreToolUse", subcommand: "before-tool", matcher: "*"),
        CodexHooksFile.Hook(event: "PostToolUse", subcommand: "after-tool", matcher: "*"),
    ])

    /// Two events, sharing `PreToolUse` and `PostToolUse` with ``gizmo``.
    static let widget = CodexTools(name: "widget", hooks: [
        CodexHooksFile.Hook(event: "PreToolUse", subcommand: "pre-tool-use", matcher: "*"),
        CodexHooksFile.Hook(event: "PostToolUse", subcommand: "post-tool-use", matcher: "*"),
    ])

    static func object(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    /// `text` reserialized the way a merge writes a file, so a fixture and a merge's output compare byte for byte.
    static func canonical(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        try CursorConfigJSON.encode(object(Data(text.utf8), sourceLocation: sourceLocation))
    }
}
