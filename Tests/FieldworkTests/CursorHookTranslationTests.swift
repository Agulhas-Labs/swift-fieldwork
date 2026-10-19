// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the two translations a Cursor hook is: Cursor's payload into the Claude Code payload a made-up tool, `gizmo`, judges, and the tool's Claude Code answer into Cursor's response schema.
struct CursorHookTranslationTests {
    private static var root: String {
        "/work/app"
    }

    /// The tool's own MCP calls, spelled `MCP:<tool>` by Cursor and `mcp__gizmo__<tool>` by Claude Code, for `lookup` with a `target`.
    private static func mcpToolName(_ name: String, _ input: [String: Any]) -> String? {
        name == "MCP:lookup" && input["target"] is String ? "mcp__gizmo__lookup" : nil
    }

    private static func isMcpTool(_ name: String) -> Bool {
        name.hasPrefix("mcp__gizmo__")
    }

    private func cursor(_ name: String, _ input: [String: Any], extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "hook_event_name": "preToolUse", "tool_name": name, "tool_input": input, "workspace_roots": [Self.root],
            "conversation_id": "c1", "tool_use_id": "t1", "transcript_path": "/t.txt",
        ]
        payload.merge(extra) { $1 }
        return payload
    }

    private func object(_ printed: String?, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let printed = try #require(printed, sourceLocation: sourceLocation)
        return try #require(JSONSerialization.jsonObject(with: Data(printed.utf8)) as? [String: Any], "\(printed)", sourceLocation: sourceLocation)
    }

    // MARK: preToolUse payload

    @Test func aShellCallBecomesABashCallInTheWorkspaceRoot() throws {
        let claude = try #require(CursorPreToolUse.claudePayload(from: cursor("Shell", ["command": "make", "cwd": ""]), mcpToolName: Self.mcpToolName(_:_:)))

        #expect(claude["tool_name"] as? String == "Bash")
        #expect(claude["hook_event_name"] as? String == "PreToolUse")
        #expect(claude["cwd"] as? String == Self.root)
        #expect(claude["session_id"] as? String == "c1")
        #expect(claude["tool_use_id"] as? String == "t1")
        #expect(claude["transcript_path"] as? String == "/t.txt")
    }

    @Test func aShellCallsOwnAbsoluteDirectoryIsItsWorkingDirectory() throws {
        let claude = try #require(CursorPreToolUse.claudePayload(from: cursor("Shell", ["command": "make", "cwd": "/work/app/sub"]), mcpToolName: Self.mcpToolName(_:_:)))

        #expect(claude["cwd"] as? String == "/work/app/sub")
    }

    @Test func aGrepBecomesAReadShapedGrepAndASessionIdWinsOverTheConversation() throws {
        let payload = cursor("Grep", ["pattern": "x", "file_path": "A.swift"], extra: ["session_id": "s9"])
        let claude = try #require(CursorPreToolUse.claudePayload(from: payload, mcpToolName: Self.mcpToolName(_:_:)))

        #expect(claude["tool_name"] as? String == "Grep")
        #expect((claude["tool_input"] as? [String: Any])?["path"] as? String == "A.swift")
        #expect(claude["session_id"] as? String == "s9")
    }

    @Test func aCursorMcpCallTakesTheNameTheConsumerGives() throws {
        let claude = try #require(CursorPreToolUse.claudePayload(from: cursor("MCP:lookup", ["target": "A"]), mcpToolName: Self.mcpToolName(_:_:)))

        #expect(claude["tool_name"] as? String == "mcp__gizmo__lookup")
        #expect(claude["cwd"] as? String == Self.root)
    }

    @Test func aCallThisCannotReadIsNotTranslated() {
        let calls: [(String, [String: Any])] = [
            ("Read", ["file_path": "/a"]),
            ("Shell", ["command": "make", "working_directory": "/a"]),
            ("Shell", ["command": ""]),
            ("Grep", ["pattern": "x", "glob": "*.swift"]),
            ("Write", ["file_path": "/a", "old_string": "x"]),
            ("MCP:lookup", ["path": "A"]),
            ("Bash", ["command": "make"]),
        ]
        for (name, input) in calls {
            #expect(CursorPreToolUse.claudePayload(from: cursor(name, input), mcpToolName: Self.mcpToolName(_:_:)) == nil, "\(name)")
        }
    }

    @Test func aPayloadWithoutAnAbsoluteRootOrOfAnotherEventIsNotTranslated() {
        for extra: [String: Any] in [["workspace_roots": []], ["workspace_roots": ["app"]], ["hook_event_name": "postToolUse"]] {
            #expect(CursorPreToolUse.claudePayload(from: cursor("Shell", ["command": "make"], extra: extra), mcpToolName: Self.mcpToolName(_:_:)) == nil, "\(extra)")
        }
    }

    // MARK: preToolUse response

    @Test func aDenialIsCursorsDenialWithTheReasonTwice() throws {
        let claude = #"{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"use lookup"}}"#
        let response = try object(CursorPreToolUse.response(to: claude, toolName: "Bash", isMcpTool: Self.isMcpTool(_:)))

        #expect(Set(response.keys) == ["permission", "user_message", "agent_message"])
        #expect(response["permission"] as? String == "deny")
        #expect(response["user_message"] as? String == "use lookup")
        #expect(response["agent_message"] as? String == "use lookup")
    }

    @Test func anAmendedShellCommandAndAnAmendedMcpInputCarryOver() throws {
        let amended = #"{"hookSpecificOutput":{"updatedInput":{"command":"gizmo run -- make"}}}"#
        let shell = try object(CursorPreToolUse.response(to: amended, toolName: nil, isMcpTool: Self.isMcpTool(_:)))
        let mcp = try object(CursorPreToolUse.response(to: #"{"hookSpecificOutput":{"updatedInput":{"target":"A","root":"/r"}}}"#, toolName: "mcp__gizmo__lookup", isMcpTool: Self.isMcpTool(_:)))

        #expect((shell["updated_input"] as? [String: Any])?["command"] as? String == "gizmo run -- make")
        #expect(shell["permission"] == nil)
        #expect((mcp["updated_input"] as? [String: Any])?["root"] as? String == "/r")
    }

    @Test func anAnswerCursorHasNoRoomForIsSilence() {
        let answers: [(String, String?)] = [
            ("not json", "Bash"),
            (#"{"hookSpecificOutput":{"additionalContext":"hi"}}"#, "Bash"),
            (#"{"hookSpecificOutput":{"updatedInput":{"path":"a"}}}"#, "Bash"),
            (#"{"hookSpecificOutput":{"updatedInput":{"command":"x"}}}"#, "Grep"),
            (#"{"hookSpecificOutput":{"permissionDecision":"allow","updatedInput":{"command":"x"}}}"#, "Bash"),
            (#"{"hookSpecificOutput":{"updatedInput":{"target":"A"}}}"#, "mcp__widget__lookup"),
        ]
        for (output, tool) in answers {
            #expect(CursorPreToolUse.response(to: output, toolName: tool, isMcpTool: Self.isMcpTool(_:)) == nil, "\(output)")
        }
    }

    @Test func aRewriteNoticeIsFiledOnlyForAnAmendedShellCallWithASessionAndACall() {
        let output = #"{"hookSpecificOutput":{"additionalContext":"rewrote it","updatedInput":{"command":"x"}}}"#
        let response = #"{"updated_input":{"command":"x"}}"#
        let shell = cursor("Bash", [:], extra: ["session_id": "s1"])

        #expect(CursorPreToolUse.ticket(output: output, response: response, claudePayload: shell) == CursorPreToolUse.Ticket(notice: "rewrote it", session: "s1", call: "t1"))
        #expect(CursorPreToolUse.ticket(output: output, response: "{}", claudePayload: shell) == nil)
        #expect(CursorPreToolUse.ticket(output: output, response: response, claudePayload: cursor("Bash", [:])) == nil)
        #expect(CursorPreToolUse.ticket(output: output, response: response, claudePayload: cursor("Grep", [:], extra: ["session_id": "s1"])) == nil)
        #expect(CursorPreToolUse.ticket(output: #"{"hookSpecificOutput":{"additionalContext":""}}"#, response: response, claudePayload: shell) == nil)
    }

    // MARK: postToolUse

    private func write(_ extra: [String: Any] = [:]) -> [String: Any] {
        var payload: [String: Any] = [
            "hook_event_name": "postToolUse", "tool_name": "Write", "tool_input": ["file_path": "/work/app/A.swift", "content": "x"],
            "workspace_roots": [Self.root], "conversation_id": "c1", "transcript_path": "/t.txt",
        ]
        payload.merge(extra) { $1 }
        return payload
    }

    @Test func aWriteBecomesAClaudeWriteInTheWorkspaceRoot() throws {
        let claude = try #require(CursorPostToolUse.claudePayload(from: write()))

        #expect(claude["hook_event_name"] as? String == "PostToolUse")
        #expect(claude["tool_name"] as? String == "Write")
        #expect(claude["cwd"] as? String == Self.root)
        #expect(claude["session_id"] as? String == "c1")
        #expect(claude["transcript_path"] as? String == "/t.txt")
    }

    @Test func aWriteThisCannotReadIsNotTranslated() {
        let variants: [[String: Any]] = [
            ["hook_event_name": "preToolUse"], ["tool_name": "Read"], ["tool_input": ["file_path": "/a", "old_string": "x"]],
            ["tool_input": ["file_path": ""]], ["workspace_roots": ["app"]],
        ]
        for extra in variants {
            #expect(CursorPostToolUse.claudePayload(from: write(extra)) == nil, "\(extra)")
        }
        var noSession = write()
        noSession["conversation_id"] = nil

        #expect(CursorPostToolUse.claudePayload(from: noSession) == nil)
    }

    private func shellResult(_ extra: [String: Any]) -> [String: Any] {
        var payload: [String: Any] = [
            "hook_event_name": "postToolUse", "tool_name": "Shell", "tool_input": ["command": "make"], "workspace_roots": [Self.root],
            "conversation_id": "c1", "tool_use_id": "t1", "cwd": "",
        ]
        payload.merge(extra) { $1 }
        return payload
    }

    @Test func aShellResultsTextIsItsOutputOrItsErrorMessage() throws {
        let success = try #require(CursorPostToolUse.shellPayload(from: shellResult(["tool_output": #"{"output":"built\n","exitCode":0}"#])))
        let failure = try #require(CursorPostToolUse.shellPayload(from: shellResult(["hook_event_name": "postToolUseFailure", "error_message": "exit 1", "is_interrupt": false])))
        let raw = try #require(CursorPostToolUse.shellPayload(from: shellResult(["tool_output": "plain"])))

        #expect(success["tool_response"] as? String == "built\n")
        #expect(success["tool_name"] as? String == "Bash")
        #expect(success["cwd"] as? String == Self.root)
        #expect(failure["tool_response"] as? String == "exit 1")
        #expect(raw["tool_response"] as? String == "plain")
        #expect(try #require(CursorPostToolUse.shellPayload(from: shellResult(["tool_output": "x", "cwd": "/work/app/sub"])))["cwd"] as? String == "/work/app/sub")
    }

    @Test func aPayloadThatIsNoShellResultOrHasNoTextOrDirectoryHasNoShellPayload() {
        #expect(CursorPostToolUse.shellPayload(from: shellResult(["tool_name": "Write", "tool_output": "x"])) == nil)
        #expect(CursorPostToolUse.shellPayload(from: shellResult(["hook_event_name": "preToolUse", "tool_output": "x"])) == nil)
        #expect(CursorPostToolUse.shellPayload(from: shellResult([:])) == nil)
        #expect(CursorPostToolUse.shellPayload(from: shellResult(["tool_output": "x", "workspace_roots": []])) == nil)
        #expect(CursorPostToolUse.isShellResult(shellResult(["hook_event_name": "postToolUseFailure"])))
    }

    @Test func aRewriteNoticeIsTakenByTheSessionAndCallAShellResultNames() {
        var asked: [String] = []
        let notice = CursorPostToolUse.rewriteNotice(for: shellResult([:])) { session, call in
            asked.append("\(session)/\(call)")
            return "noted"
        }
        let none = CursorPostToolUse.rewriteNotice(for: shellResult(["tool_name": "Write"])) { _, _ in "never" }
        var withoutCall = shellResult([:])
        withoutCall["tool_use_id"] = nil
        let noCall = CursorPostToolUse.rewriteNotice(for: withoutCall) { _, _ in "never" }

        #expect(notice == "noted")
        #expect(asked == ["c1/t1"])
        #expect(none == nil)
        #expect(noCall == nil)
    }

    @Test func aBlockReasonAndANudgeBothReachTheModelAsAdditionalContext() throws {
        let block = try object(CursorPostToolUse.response(to: #"{"decision":"block","reason":"does not parse"}"#))
        let nudge = try object(CursorPostToolUse.response(to: #"{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"reuse this/one"}}"#))

        #expect(block["additional_context"] as? String == "does not parse")
        #expect(nudge["additional_context"] as? String == "reuse this/one")
        #expect(CursorPostToolUse.response(to: #"{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"x"}}"#) == nil)
        #expect(CursorPostToolUse.response(to: "not json") == nil)
    }

    // MARK: sessionStart and output

    @Test func aSessionStartIsAClaudeSessionStartInTheFirstWorkspaceRoot() throws {
        let claude = try #require(CursorSessionStart.claudePayload(from: ["hook_event_name": "sessionStart", "workspace_roots": [Self.root, "/other"]]))

        #expect(claude as NSDictionary == ["hook_event_name": "SessionStart", "cwd": Self.root] as NSDictionary)
    }

    @Test func aSessionStartWithoutAnAbsoluteRootIsNotTranslated() {
        #expect(CursorSessionStart.claudePayload(from: ["hook_event_name": "sessionStart"]) == nil)
        #expect(CursorSessionStart.claudePayload(from: ["hook_event_name": "sessionStart", "workspace_roots": ["app"]]) == nil)
        #expect(CursorSessionStart.claudePayload(from: ["hook_event_name": "sessionStart", "workspace_roots": [1]]) == nil)
        #expect(CursorSessionStart.claudePayload(from: ["hook_event_name": "preToolUse", "workspace_roots": [Self.root]]) == nil)
    }

    @Test func cursorsOutputIsSortedKeysWithBareSlashes() {
        #expect(CursorHookOutput.additionalContext("a/b") == #"{"additional_context":"a/b"}"#)
        #expect(CursorHookOutput.preToolUseDenial(message: "no") == #"{"agent_message":"no","permission":"deny","user_message":"no"}"#)
        #expect(CursorHookOutput.preToolUseAmendment(input: ["command": "x"]) == #"{"updated_input":{"command":"x"}}"#)
        #expect(CursorHookOutput.preToolUseAmendment(input: ["bad": Double.nan]) == nil)
    }
}
