// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The merge a tool makes in Codex's `hooks.json`, and its inverse.
struct CodexHooksFileTests {
    private static let gizmo = CodexTools.gizmo.file
    private static var binary: String {
        "/opt/tools/bin/gizmo"
    }

    /// A `hooks.json` holding someone else's handlers: a group of its own on an event the tool registers for, and an event it never touches.
    private static var foreignHooks: String {
        #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/usr/local/bin/audit-log.sh","timeout":5,"type":"command"}],"matcher":"Bash"}],"Stop":[{"hooks":[{"command":"/usr/local/bin/notify.sh","type":"command"}]}]},"telemetry":false}"#
    }

    private static func groups(_ data: Data, _ event: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [[String: Any]] {
        try #require((CodexTools.object(data, sourceLocation: sourceLocation)["hooks"] as? [String: Any])?[event] as? [[String: Any]], sourceLocation: sourceLocation)
    }

    private static func commands(_ group: [String: Any]?) -> [String] {
        (group?["hooks"] as? [[String: Any]])?.compactMap { $0["command"] as? String } ?? []
    }

    @Test func anEmptyFileGetsTheThreeEventsInCodexsShapeWithThePlainSubcommands() throws {
        let change = try Self.gizmo.apply(to: nil, binaryWord: Self.binary)

        #expect(change.changed)
        let written = try CodexTools.object(change.data)
        let expected = try CodexTools.object(Data(#"""
        {"hooks":{
          "SessionStart":[{"hooks":[{"type":"command","command":"/opt/tools/bin/gizmo session-start"}]}],
          "PreToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/opt/tools/bin/gizmo pre-tool-use"}]}],
          "PostToolUse":[{"matcher":"*","hooks":[{"type":"command","command":"/opt/tools/bin/gizmo post-tool-use"}]}]
        }}
        """#.utf8))
        #expect(NSDictionary(dictionary: written).isEqual(to: expected))
    }

    @Test func aSecondApplyChangesNothingAndRemovalRestoresTheForeignFileByteForByte() throws {
        let original = try CodexTools.canonical(Self.foreignHooks)
        let installed = try Self.gizmo.apply(to: original, binaryWord: Self.binary)
        let again = try Self.gizmo.apply(to: installed.data, binaryWord: Self.binary)
        let removed = try Self.gizmo.remove(from: installed.data)
        let removedAgain = try Self.gizmo.remove(from: removed.data)

        #expect(installed.changed)
        #expect(!again.changed)
        #expect(again.data == installed.data)
        #expect(removed.changed)
        #expect(removed.data == original)
        #expect(removed.removed.count == 3)
        #expect(!removedAgain.changed)
    }

    @Test func aForeignGroupKeepsItsPlaceAndOursIsAppendedAfterIt() throws {
        let installed = try Self.gizmo.apply(to: Data(Self.foreignHooks.utf8), binaryWord: Self.binary)
        let events = try #require(CodexTools.object(installed.data)["hooks"] as? [String: Any])
        let groups = try Self.groups(installed.data, "PreToolUse")

        #expect(groups.count == 2)
        #expect(groups.first?["matcher"] as? String == "Bash")
        #expect(Self.commands(groups.first) == ["/usr/local/bin/audit-log.sh"])
        #expect(Self.commands(groups.last) == ["/opt/tools/bin/gizmo pre-tool-use"])
        #expect(events["Stop"] != nil)
    }

    @Test func removingOursFromAMixedGroupKeepsTheForeignHandlerAndTheMatcher() throws {
        let mixed = #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/opt/tools/bin/gizmo pre-tool-use","type":"command"},{"command":"/usr/local/bin/audit-log.sh","type":"command"}],"matcher":"*"}]}}"#
        let removed = try Self.gizmo.remove(from: Data(mixed.utf8))
        let groups = try Self.groups(removed.data, "PreToolUse")

        #expect(removed.removed == ["PreToolUse — /opt/tools/bin/gizmo pre-tool-use"])
        #expect(groups.count == 1)
        #expect(groups.first?["matcher"] as? String == "*")
        #expect(Self.commands(groups.first) == ["/usr/local/bin/audit-log.sh"])
    }

    @Test func aMovedBinaryIsRepointedInPlaceAndADuplicateDropped() throws {
        let stale = #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/old/bin/gizmo pre-tool-use","type":"command"}],"matcher":"*"},{"hooks":[{"command":"/other/bin/gizmo pre-tool-use","type":"command"}],"matcher":"*"}]}}"#
        let change = try Self.gizmo.apply(to: Data(stale.utf8), binaryWord: Self.binary)
        let groups = try Self.groups(change.data, "PreToolUse")

        #expect(change.replaced == ["/old/bin/gizmo pre-tool-use"])
        #expect(groups.count == 1)
        #expect(Self.commands(groups.first) == ["/opt/tools/bin/gizmo pre-tool-use"])
    }

    @Test func anotherAgentsRegistrationAndALookalikeAreNeverClaimed() throws {
        let others = #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/opt/tools/bin/gizmo pre-tool-use --agent other","type":"command"},{"command":"/opt/tools/bin/gizmoworks pre-tool-use","type":"command"}]}]}}"#

        #expect(try !Self.gizmo.remove(from: Data(others.utf8)).changed)
    }

    @Test(arguments: [#"[1,2]"#, #"{"hooks":[]}"#, #"{"hooks":{"PreToolUse":{"hooks":[]}}}"#, #"{"hooks":{"PreToolUse":[{"hooks":{"command":"x"}}]}}"#])
    func aFileOfAnotherShapeIsRefusedNamingCodex(text: String) throws {
        let error = try #require(throws: CursorConfigJSON.Unmergeable.self) { try Self.gizmo.apply(to: Data(text.utf8), binaryWord: Self.binary) }

        #expect(error.harness == "Codex")
        #expect(!error.description.contains("Cursor"))
    }

    @Test func aSwitchBetweenTwoSetsRewritesInPlaceAndKeepsEveryGroupsPosition() throws {
        let seed = #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/usr/local/bin/before.sh","type":"command"}],"matcher":"Bash"},{"hooks":[{"command":"/opt/tools/bin/gizmo pre-tool-use","type":"command"}],"matcher":"*"},{"hooks":[{"command":"/usr/local/bin/after.sh","type":"command"}],"matcher":"Edit"}],"PostToolUse":[{"hooks":[{"command":"/opt/tools/bin/gizmo post-tool-use","type":"command"}],"matcher":"*"}]}}"#
        let other = CodexTools.gizmoOther.file
        let switched = try other.apply(to: Data(seed.utf8), binaryWord: Self.binary, replacing: Self.gizmo.hooks)
        let pre = try Self.groups(switched.data, "PreToolUse")
        let post = try Self.groups(switched.data, "PostToolUse")

        #expect(switched.changed)
        #expect(pre.count == 3)
        #expect(Self.commands(pre[0]) == ["/usr/local/bin/before.sh"])
        #expect(Self.commands(pre[1]) == ["/opt/tools/bin/gizmo before-tool"])
        #expect(Self.commands(pre[2]) == ["/usr/local/bin/after.sh"])
        #expect(post.count == 1)
        #expect(Self.commands(post[0]) == ["/opt/tools/bin/gizmo after-tool"])
        #expect(switched.replaced.isEmpty)
        #expect(CodexHooksFile.movedEvents(from: Data(seed.utf8), to: switched.data).isEmpty)
    }
}
