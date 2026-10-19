// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A Cursor `preToolUse` payload read as the Claude Code payload a tool's hook decisions are written against, and each decision written back in Cursor's response schema.
///
/// Both ends are a translation and nothing else, so one engine judges both harnesses: a refusal becomes Cursor's deny, and an amended input Cursor's `updated_input`. Only the tool inputs a probe of a real Cursor recorded are read, key for key; a payload carrying anything else is not read at all, because on Cursor a response that does not fit the schema can block the call, and silence is the one answer that never can.
///
/// What names the tool's own MCP calls is the consumer's, passed in as a closure.
public struct CursorPreToolUse {
    /// The Claude Code payload `payload` stands for, or `nil` where it is not a `preToolUse` payload of a tool input this reads.
    ///
    /// The working directory is the first workspace root: Shell's own `cwd` has always come empty, and is taken only where it names a directory.
    ///
    /// `mcpToolName` is given the Cursor tool name and input of a call that is none of Cursor's own tools, and returns the Claude Code name the consumer's MCP tool goes by, or `nil` where the call is not the consumer's.
    public static func claudePayload(
        from payload: [String: Any],
        mcpToolName: (_ cursorName: String, _ input: [String: Any]) -> String?
    ) -> [String: Any]? {
        guard payload["hook_event_name"] as? String == "preToolUse",
              let name = payload["tool_name"] as? String,
              let input = payload["tool_input"] as? [String: Any],
              let root = (payload["workspace_roots"] as? [Any])?.first as? String, root.hasPrefix("/"),
              let tool = claudeTool(name, input: input, mcpToolName: mcpToolName)
        else {
            return nil
        }
        let shellDirectory = (input["cwd"] as? String).flatMap { $0.hasPrefix("/") ? $0 : nil }
        var claude: [String: Any] = ["hook_event_name": "PreToolUse", "tool_name": tool.name, "tool_input": tool.input]
        claude["cwd"] = tool.name == "Bash" ? shellDirectory ?? root : root
        claude["session_id"] = payload["session_id"] as? String ?? payload["conversation_id"] as? String
        claude["transcript_path"] = payload["transcript_path"] as? String
        claude["tool_use_id"] = payload["tool_use_id"] as? String
        return claude
    }

    /// What Cursor is told for the hook's Claude Code `output`, or `nil` where its schema has no room for it.
    ///
    /// A refusal carries its reason as the message the model reads. An amended input carries over for one of the consumer's MCP calls and for a shell call: the whole input goes back with the command replaced and no `permission`, so Cursor runs the rewritten command under its own approval. Context for the model has no carrier a probe saw delivered, so it prints nothing.
    ///
    /// `toolName` is the Claude Code name the payload was read into, so a Cursor `Shell` call arrives here as `Bash`. `isMcpTool` says whether that name is one of the consumer's MCP tools.
    public static func response(to output: String, toolName: String?, isMcpTool: (_ claudeName: String) -> Bool) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any],
              let specific = object["hookSpecificOutput"] as? [String: Any]
        else {
            return nil
        }
        if specific["permissionDecision"] as? String == "deny", let reason = specific["permissionDecisionReason"] as? String {
            return CursorHookOutput.preToolUseDenial(message: reason)
        }
        let toolName = toolName ?? "Bash"
        guard specific["permissionDecision"] == nil,
              let input = specific["updatedInput"] as? [String: Any],
              isMcpTool(toolName) || (toolName == "Bash" && input["command"] is String)
        else {
            return nil
        }
        return CursorHookOutput.preToolUseAmendment(input: input)
    }

    /// The rewrite notice to file for the call's `postToolUse`, where `response` amends a Shell input and `output` carried context for the model, or `nil` where there is none to file.
    ///
    /// It takes the Claude-shaped payload (`tool_name` `Bash`), as ``CursorHookPayload`` reads it from Cursor's, not Cursor's own.
    ///
    /// Cursor drops that context from a `preToolUse` answer, so a ticket is how the same call's `postToolUse` delivers it. Nothing is filed without a session and a call id.
    public static func ticket(output: String, response: String, claudePayload: [String: Any]) -> Ticket? {
        guard claudePayload["tool_name"] as? String == "Bash",
              response.contains("updated_input"),
              let object = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any],
              let specific = object["hookSpecificOutput"] as? [String: Any],
              let notice = specific["additionalContext"] as? String, !notice.isEmpty,
              let session = claudePayload["session_id"] as? String, !session.isEmpty,
              let call = claudePayload["tool_use_id"] as? String, !call.isEmpty
        else {
            return nil
        }
        return Ticket(notice: notice, session: session, call: call)
    }

    /// The Claude Code tool and input a Cursor tool call is, in the shapes a probe recorded.
    private static func claudeTool(
        _ name: String,
        input: [String: Any],
        mcpToolName: (String, [String: Any]) -> String?
    ) -> (name: String, input: [String: Any])? {
        let keys = Set(input.keys)
        switch name {
        case "Shell":
            guard keys.isSubset(of: ["command", "cwd", "timeout"]), let command = input["command"] as? String, !command.isEmpty else { return nil }
            return ("Bash", input)
        case "Read":
            // Cursor's Read payload carries only the path, never `offset` or `limit`, so a ranged read looks like a whole-file one; and its edit tool raises the same Read-shaped event under the edit's own call id.
            return nil
        case "Grep":
            guard keys.isSubset(of: ["pattern", "file_path"]), let pattern = input["pattern"] as? String, !pattern.isEmpty else { return nil }
            var read: [String: Any] = ["pattern": pattern]
            if let path = input["file_path"] {
                guard let path = path as? String else { return nil }
                read["path"] = path
            }
            return ("Grep", read)
        case "Write":
            guard keys.isSubset(of: ["file_path", "content"]), input["file_path"] is String else { return nil }
            return ("Write", input)
        default:
            guard let tool = mcpToolName(name, input) else { return nil }
            return (tool, input)
        }
    }
}

public extension CursorPreToolUse {
    /// What a `preToolUse` answer files for the same call's `postToolUse`: the notice, and the session and call id it is filed under.
    struct Ticket: Equatable, Sendable {
        public let notice: String
        public let session: String
        public let call: String
    }
}
