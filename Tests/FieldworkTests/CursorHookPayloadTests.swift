// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers telling a Cursor hook payload from a Claude Code one, against the representative Cursor payloads a probe of the Cursor CLI recorded in `Fixtures/cursor-hook-payloads.json`.
struct CursorHookPayloadTests {
    /// The fixture's common fields laid under the event's own, as Cursor sends them.
    static func payload(for event: Event, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "cursor-hook-payloads", withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        let fixture = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any], sourceLocation: sourceLocation)
        let common = try #require(fixture["common"] as? [String: Any], sourceLocation: sourceLocation)
        let events = try #require(fixture["events"] as? [String: Any], sourceLocation: sourceLocation)
        let own = try #require(events[event.rawValue] as? [String: Any], sourceLocation: sourceLocation)
        return common.merging(own) { $1 }
    }

    @Test(arguments: Event.allCases)
    func aRecordedCursorPayloadIsRecognised(event: Event) throws {
        #expect(try CursorHookPayload.recognises(Self.payload(for: event)))
    }

    /// Cursor's `cursor_version` is not established to reach an imported hook, so its other common fields identify it alone.
    @Test
    func aPayloadWithoutCursorVersionIsStillRecognisedByItsOtherCommonFields() throws {
        var payload = try Self.payload(for: .preToolUse)
        payload["cursor_version"] = nil
        payload["workspace_roots"] = nil

        #expect(payload["conversation_id"] != nil && payload["generation_id"] != nil)
        #expect(CursorHookPayload.recognises(payload))
        #expect(CursorHookPayload.recognises(["workspace_roots": ["/r"]]))
        #expect(CursorHookPayload.recognises(["cursor_version": "2.1.0"]))
    }

    @Test(arguments: Event.allCases)
    func theSamePayloadWithoutCursorsFieldsIsNotRecognised(event: Event) throws {
        var payload = try Self.payload(for: event)
        for field in ["cursor_version", "conversation_id", "generation_id", "workspace_roots"] {
            payload[field] = nil
        }

        #expect(!CursorHookPayload.recognises(payload))
    }

    @Test
    func theRecordedPayloadsSayWhichEventTheyAre() throws {
        for event in Event.allCases {
            #expect(try Self.payload(for: event)["hook_event_name"] as? String == event.rawValue)
        }
    }

    /// Claude Code's own payloads, one per event a hook is registered for, are never taken for Cursor's.
    @Test
    func noClaudeCodePayloadIsTakenForCursors() {
        let common: [String: Any] = ["session_id": "s1", "transcript_path": "/t.jsonl", "cwd": "/repo", "permission_mode": "default"]
        let events: [[String: Any]] = [
            ["hook_event_name": "SessionStart", "source": "startup", "model": "claude-opus-4-7"],
            ["hook_event_name": "SubagentStart", "agent_id": "a1", "agent_type": "general-purpose"],
            ["hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": ["command": "swift build"], "tool_use_id": "t1"],
            ["hook_event_name": "PostToolUse", "tool_name": "Write", "tool_input": ["file_path": "/repo/A.swift"], "tool_response": [:], "tool_use_id": "t2"],
            ["hook_event_name": "Stop", "stop_hook_active": false],
            ["hook_event_name": "SubagentStop", "stop_hook_active": false, "agent_id": "a1", "agent_transcript_path": "/a.jsonl"],
        ]

        for event in events {
            #expect(!CursorHookPayload.recognises(common.merging(event) { $1 }), "\(event)")
        }
    }
}

extension CursorHookPayloadTests {
    /// Every event a tool registers, by Cursor's name for it.
    enum Event: String, CaseIterable {
        case sessionStart, subagentStart, preToolUse, postToolUse, postToolUseFailure, stop, subagentStop
    }
}
