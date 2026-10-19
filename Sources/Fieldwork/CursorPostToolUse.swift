// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A Cursor `postToolUse` payload read as the Claude Code payload a tool's hook judges, and what the hook prints written back in Cursor's schema.
///
/// A probe saw Cursor report both a new file and a search-and-replace edit as `Write` with the file's whole new content and no content from before it; so an edit is judged as a Claude Code `Write` with nothing known of the prior file. Anything else it sends is not read at all.
public struct CursorPostToolUse {
    /// The Claude Code payload `payload` stands for, or `nil` where it is not a `postToolUse` payload of a `Write`, in the shape a probe recorded, with an absolute workspace root and a session.
    public static func claudePayload(from payload: [String: Any]) -> [String: Any]? {
        guard payload["hook_event_name"] as? String == "postToolUse",
              payload["tool_name"] as? String == "Write",
              let input = payload["tool_input"] as? [String: Any],
              Set(input.keys).isSubset(of: ["file_path", "content"]),
              let path = input["file_path"] as? String, !path.isEmpty,
              let root = (payload["workspace_roots"] as? [Any])?.first as? String, root.hasPrefix("/"),
              let session = payload["session_id"] as? String ?? payload["conversation_id"] as? String
        else {
            return nil
        }
        var claude: [String: Any] = ["hook_event_name": "PostToolUse", "tool_name": "Write", "tool_input": input, "cwd": root, "session_id": session]
        claude["transcript_path"] = payload["transcript_path"] as? String
        return claude
    }

    /// The notice filed for this `Shell` call, taken by `take` with the call's session and id, or `nil` where `payload` is no `Shell` result or names no session and call.
    public static func rewriteNotice(for payload: [String: Any], take: (_ session: String, _ call: String) -> String?) -> String? {
        guard isShellResult(payload),
              let session = payload["session_id"] as? String ?? payload["conversation_id"] as? String,
              let call = payload["tool_use_id"] as? String
        else {
            return nil
        }
        return take(session, call)
    }

    /// Whether `payload` is the result of a `Shell` call: `postToolUse` of one that succeeded, `postToolUseFailure` of one that did not.
    public static func isShellResult(_ payload: [String: Any]) -> Bool {
        ["postToolUse", "postToolUseFailure"].contains(payload["hook_event_name"] as? String ?? "") && payload["tool_name"] as? String == "Shell"
    }

    /// The Claude Code `Bash` payload a `Shell` result stands for, for a diagnostics note, or `nil` where it is not one or names no directory.
    ///
    /// The response text is `tool_output`'s `output` (a JSON string) on success and `error_message` on failure. The call's `tool_input` and `is_interrupt` come along. The directory is the payload's `cwd`, else the first workspace root, as `cwd` may be empty.
    public static func shellPayload(from payload: [String: Any]) -> [String: Any]? {
        guard isShellResult(payload) else { return nil }
        let text: String? = if let raw = payload["tool_output"] as? String {
            ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any])?["output"] as? String ?? raw
        } else {
            payload["error_message"] as? String
        }
        let roots = payload["workspace_roots"] as? [Any]
        guard let text,
              let cwd = (payload["cwd"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? roots?.first as? String
        else {
            return nil
        }
        return ["tool_name": "Bash", "tool_input": payload["tool_input"] as Any, "tool_response": text, "cwd": cwd, "is_interrupt": payload["is_interrupt"] as Any]
    }

    /// What Cursor is told for the hook's Claude Code `output`, or `nil` where its schema has no room for it.
    ///
    /// Both of the hook's answers reach the model as context, the one carrier a probe saw delivered on `postToolUse`: a nudge, and a block's reason, since no block of a call already made was probed.
    public static func response(to output: String) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [String: Any] else {
            return nil
        }
        if object["decision"] as? String == "block", let reason = object["reason"] as? String {
            return CursorHookOutput.additionalContext(reason)
        }
        guard let specific = object["hookSpecificOutput"] as? [String: Any],
              specific["hookEventName"] as? String == "PostToolUse",
              let context = specific["additionalContext"] as? String
        else {
            return nil
        }
        return CursorHookOutput.additionalContext(context)
    }
}
