// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The merges behind a Cursor install: the exact shapes written into `hooks.json` and `mcp.json`, recognition by shape, foreign entries carried verbatim, and removal as the exact inverse.
struct CursorConfigMergeTests {
    private static let tool = CursorTools.gizmo
    private static var binary: String {
        "/opt/tools/bin/gizmo"
    }

    private static var foreignHooks: String {
        #"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh","failClosed":true}],"stop":[{"command":"/usr/local/bin/notify.sh"}]},"telemetry":false,"version":1}"#
    }

    private static var foreignServers: String {
        #"{"mcpServers":{"notes":{"args":["serve"],"command":"/opt/notes/bin/notes"}}}"#
    }

    @Test
    func anEmptyHooksFileGetsTheFourEventsWithTheAgentFlagAndNothingElse() throws {
        let change = try Self.tool.hooks.apply(to: nil, binaryWord: Self.binary)

        #expect(change.changed)
        let file = try CursorTools.object(change.data)
        #expect(file["version"] as? Int == 1)
        let hooks = try #require(file["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == ["sessionStart", "preToolUse", "postToolUse", "postToolUseFailure"])
        for (event, subcommand) in [("sessionStart", "session-start"), ("preToolUse", "pre-tool-use"), ("postToolUse", "post-tool-use"), ("postToolUseFailure", "post-tool-use")] {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.count == 1, "\(event)")
            #expect(entries.first?.keys.sorted() == ["command"], "\(event): only the command, never failClosed")
            #expect(entries.first?["command"] as? String == "\(Self.binary) \(subcommand) --agent cursor", "\(event)")
        }
    }

    @Test
    func anEmptyAgentFlagRegistersOneEntryPerHookWithNoTrailingSpaceAndAReinstallChangesNothing() throws {
        let bare = CursorTools(name: "gizmo", agentFlag: "").hooks
        let first = try bare.apply(to: nil, binaryWord: Self.binary)
        let second = try bare.apply(to: first.data, binaryWord: Self.binary)

        #expect(!second.changed)
        #expect(second.data == first.data)
        let hooks = try #require(try CursorTools.object(second.data)["hooks"] as? [String: Any])
        for (event, subcommand) in [("sessionStart", "session-start"), ("preToolUse", "pre-tool-use"), ("postToolUse", "post-tool-use"), ("postToolUseFailure", "post-tool-use")] {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.count == 1, "\(event)")
            #expect(entries.first?["command"] as? String == "\(Self.binary) \(subcommand)", "\(event)")
        }
    }

    @Test
    func aSecondApplyChangesNothingAndRemovalRestoresTheForeignFileByteForByte() throws {
        let foreign = try CursorTools.canonical(Self.foreignHooks)
        let installed = try Self.tool.hooks.apply(to: foreign, binaryWord: Self.binary)
        #expect(installed.changed)

        let again = try Self.tool.hooks.apply(to: installed.data, binaryWord: Self.binary)
        #expect(!again.changed)
        #expect(again.data == installed.data)

        let file = try CursorTools.object(installed.data)
        let preToolUse = try #require((file["hooks"] as? [String: Any])?["preToolUse"] as? [[String: Any]])
        #expect(preToolUse.count == 2)
        #expect(preToolUse.first?["command"] as? String == "/usr/local/bin/audit-log.sh")
        #expect(preToolUse.first?["failClosed"] as? Bool == true)
        #expect(file["telemetry"] as? Bool == false)

        let removed = try Self.tool.hooks.remove(from: installed.data)
        #expect(removed.removed.count == 4)
        #expect(removed.data == foreign)
        #expect(try !Self.tool.hooks.remove(from: removed.data).changed)
    }

    @Test
    func aClaudeCodeRegistrationAndALookalikeAreNeverClaimed() throws {
        let hooks = #"{"hooks":{"sessionStart":[{"command":"/opt/tools/bin/gizmo session-start"},{"command":"/opt/gizmoworks/gizmo-agent session-start --agent cursor"}]},"version":1}"#
        let foreign = try CursorTools.canonical(hooks)

        #expect(try !Self.tool.hooks.remove(from: foreign).changed)
        let installed = try Self.tool.hooks.apply(to: foreign, binaryWord: Self.binary)
        let sessionStart = try #require((CursorTools.object(installed.data)["hooks"] as? [String: Any])?["sessionStart"] as? [[String: Any]])
        #expect(sessionStart.compactMap { $0["command"] as? String } == [
            "/opt/tools/bin/gizmo session-start",
            "/opt/gizmoworks/gizmo-agent session-start --agent cursor",
            "\(Self.binary) session-start --agent cursor",
        ])
    }

    @Test
    func aMovedBinaryIsRepointedInPlaceAndADuplicateDropped() throws {
        let stale = #"{"hooks":{"sessionStart":[{"command":"/old/gizmo session-start --agent cursor","timeout":9},{"command":"/usr/local/bin/notify.sh"},{"command":"/old/gizmo session-start --agent cursor"}]},"version":1}"#

        let change = try Self.tool.hooks.apply(to: CursorTools.canonical(stale), binaryWord: Self.binary)

        #expect(change.replaced == ["/old/gizmo session-start --agent cursor"])
        let sessionStart = try #require((CursorTools.object(change.data)["hooks"] as? [String: Any])?["sessionStart"] as? [[String: Any]])
        #expect(sessionStart.compactMap { $0["command"] as? String } == ["\(Self.binary) session-start --agent cursor", "/usr/local/bin/notify.sh"])
        #expect(sessionStart.first?["timeout"] as? Int == 9)
    }

    @Test(arguments: [#"[1,2]"#, #"{"hooks":[]}"#, #"{"hooks":{"preToolUse":{"command":"x"}}}"#])
    func aHooksFileOfAnotherShapeIsRefused(text: String) {
        #expect(throws: CursorConfigJSON.Unmergeable.self) { try Self.tool.hooks.apply(to: Data(text.utf8), binaryWord: Self.binary) }
        #expect(throws: CursorConfigJSON.Unmergeable.self) { try Self.tool.hooks.remove(from: Data(text.utf8)) }
    }

    @Test
    func theServerIsRegisteredByAbsolutePathWithItsArgumentsAndRemovedToTheForeignFile() throws {
        let foreign = try CursorTools.canonical(Self.foreignServers)

        let installed = try Self.tool.mcp.apply(to: foreign, binary: Self.binary)

        #expect(installed.outcome == .registered)
        let servers = try #require(CursorTools.object(installed.data)["mcpServers"] as? [String: Any])
        let gizmo = try #require(servers["gizmo"] as? [String: Any])
        #expect(gizmo.keys.sorted() == ["args", "command"])
        #expect(gizmo["command"] as? String == Self.binary)
        #expect(gizmo["args"] as? [String] == ["mcp"])
        #expect(servers["notes"] != nil)

        let again = try Self.tool.mcp.apply(to: installed.data, binary: Self.binary)
        #expect(again.outcome == .unchanged)
        #expect(again.data == installed.data)

        let removed = try Self.tool.mcp.remove(from: installed.data)
        #expect(removed.outcome == .removed("\(Self.binary) mcp"))
        #expect(removed.data == foreign)
        #expect(try Self.tool.mcp.remove(from: removed.data).outcome == .unchanged)
    }

    @Test(arguments: [
        #"{"mcpServers":{"gizmo":{"args":["mcp","--root","/work/app"],"command":"/opt/tools/bin/gizmo"}}}"#,
        #"{"mcpServers":{"gizmo":{"args":["-y","gizmo","mcp"],"command":"npx"}}}"#,
        #"{"mcpServers":{"gizmo":{"args":["mcp"],"command":"/opt/gizmoworks/gizmo-agent"}}}"#,
    ])
    func aServerOfTheSameNameAndAnotherShapeIsReportedAndLeftAlone(text: String) throws {
        let foreign = try CursorTools.canonical(text)

        let installed = try Self.tool.mcp.apply(to: foreign, binary: Self.binary)
        let removed = try Self.tool.mcp.remove(from: foreign)

        guard case .foreign = installed.outcome else {
            Issue.record("\(installed.outcome)")
            return
        }
        #expect(installed.data == foreign)
        #expect(!installed.changed)
        guard case .foreign = removed.outcome else {
            Issue.record("\(removed.outcome)")
            return
        }
        #expect(removed.data == foreign)
    }

    @Test
    func aMovedServerIsRepointedKeepingWhatElseItsEntryHolds() throws {
        let stale = #"{"mcpServers":{"gizmo":{"args":["mcp"],"command":"/old/gizmo","env":{"GIZMO_LOG":"1"}}}}"#

        let change = try Self.tool.mcp.apply(to: CursorTools.canonical(stale), binary: Self.binary)

        #expect(change.outcome == .replaced(previous: "/old/gizmo mcp"))
        let gizmo = try #require((CursorTools.object(change.data)["mcpServers"] as? [String: Any])?["gizmo"] as? [String: Any])
        #expect(gizmo["command"] as? String == Self.binary)
        #expect((gizmo["env"] as? [String: String]) == ["GIZMO_LOG": "1"])
    }
}
