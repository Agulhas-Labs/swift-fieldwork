// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the uninstall — the merge run backwards, where the risk is the mirror image: not corrupting `settings.json`, but taking out of it something this tool never put there.
struct HookRemovalTests {
    private static func settings(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private static func object(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    private static func hooks(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any]? {
        try object(data, sourceLocation: sourceLocation)["hooks"] as? [String: Any]
    }

    private static func commands(
        _ data: Data,
        event: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> [String] {
        let entries = try hooks(data, sourceLocation: sourceLocation)?[event] as? [[String: Any]] ?? []
        return entries.flatMap { entry in
            (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
        }
    }

    /// A full installation, plus a hook this project did not write sharing the `PreToolUse` event with it, plus a setting that has nothing to do with either.
    private static func installedAlongsideAForeignHook() throws -> Data {
        try settings([
            "theme": "dark",
            "statusLine": ["type": "command", "command": "/bin/other statusline"],
            "hooks": [
                "SessionStart": [
                    ["matcher": "startup", "hooks": [["type": "command", "command": "/bin/gizmo session-start"]]],
                    ["matcher": "resume", "hooks": [["type": "command", "command": "/bin/gizmo session-start"]]],
                ],
                "SubagentStart": [["hooks": [["type": "command", "command": "/bin/gizmo session-start"]]]],
                "PreToolUse": [
                    [
                        "matcher": "Bash|Read|Grep|Glob|mcp__xcode__Xcode(Read|Grep|Glob)",
                        "hooks": [
                            ["type": "command", "command": "/bin/gizmo pre-tool-use"],
                            ["type": "command", "command": "~/.claude/hooks/audit-bash.sh"],
                        ],
                    ],
                    ["matcher": "Write", "hooks": [["type": "command", "command": "~/.claude/hooks/protect.sh"]]],
                ],
            ],
        ])
    }

    private static func removingEveryEvent(from data: Data) throws -> (data: Data, removed: [String]) {
        var current = data
        var removed: [String] = []
        for event in GizmoHooks.registration.events {
            let removal = try GizmoHooks.registration.remove(from: current, event: event)
            current = removal.data
            removed.append(contentsOf: removal.removed)
        }
        return (current, removed)
    }

    @Test
    func oursGoesAndTheForeignHookSharingTheEventStays() throws {
        let result = try Self.removingEveryEvent(from: Self.installedAlongsideAForeignHook())

        #expect(try Self.commands(result.data, event: "PreToolUse") == [
            "~/.claude/hooks/audit-bash.sh",
            "~/.claude/hooks/protect.sh",
        ])
        #expect(result.removed.contains("/bin/gizmo pre-tool-use"))
        #expect(result.removed.contains("/bin/gizmo session-start"))
    }

    /// Nothing this tool did not register may be disturbed, including keys it has no opinion about at all.
    @Test
    func unrelatedSettingsSurviveTheRemoval() throws {
        let result = try Self.removingEveryEvent(from: Self.installedAlongsideAForeignHook())

        #expect(try Self.object(result.data)["theme"] as? String == "dark")
        let statusLine = try Self.object(result.data)["statusLine"] as? [String: Any]
        #expect(statusLine?["command"] as? String == "/bin/other statusline")
    }

    /// An event array emptied by the removal is deleted, not left as a `"SessionStart": []` husk that says a hook is configured when none is.
    @Test
    func anEmptiedEventArrayIsPrunedAndSoIsTheEntryThatHeldIt() throws {
        let result = try Self.removingEveryEvent(from: Self.installedAlongsideAForeignHook())
        let hooks = try #require(try Self.hooks(result.data))

        #expect(hooks["SessionStart"] == nil)
        #expect(hooks["SubagentStart"] == nil)
        // The `PreToolUse` entry that held both hooks keeps only the foreign one; ours leaves no empty entry.
        let entries = try #require(hooks["PreToolUse"] as? [[String: Any]])
        #expect(entries.count == 2)
        #expect((entries[0]["hooks"] as? [[String: Any]])?.count == 1)
    }

    /// With the last of our events gone and nothing else registered, the `hooks` object itself goes too.
    @Test
    func anEmptiedHooksObjectIsPruned() throws {
        let installed = try Self.settings([
            "theme": "dark",
            "hooks": [
                "SessionStart": [["matcher": "startup", "hooks": [["type": "command", "command": "/bin/gizmo session-start"]]]],
            ],
        ])

        let result = try Self.removingEveryEvent(from: installed)

        #expect(try Self.object(result.data)["hooks"] == nil)
        #expect(try Self.object(result.data)["theme"] as? String == "dark")
    }

    /// One binary registered against three matchers is one thing removed, not three lines claiming three registrations.
    @Test
    func theSameCommandAcrossEveryMatcherIsReportedOnce() throws {
        let installed = try GizmoHooks.registration.apply(to: nil, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        let removal = try GizmoHooks.registration.remove(from: installed.data, event: GizmoHooks.sessionStart)

        #expect(removal.removed == ["/bin/gizmo session-start"])
    }

    @Test
    func anEventThatCarriesOnlyForeignHooksIsLeftExactlyAsItWas() throws {
        let foreign = try Self.settings([
            "hooks": ["SessionStart": [["matcher": "startup", "hooks": [["type": "command", "command": "~/.claude/hooks/mine.sh"]]]]],
        ])

        let removal = try GizmoHooks.registration.remove(from: foreign, event: GizmoHooks.sessionStart)

        #expect(removal.removed.isEmpty)
        // Unchanged means the input's own bytes, not a re-serialisation that happens to mean the same.
        #expect(removal.data == foreign)
    }

    /// One element of an unexpected shape makes a whole-array cast fail, and the failure is silent: the removal finds nothing, reports nothing registered, and leaves the hook running.
    @Test
    func aStrayElementBesideARealEntryDoesNotBlindTheRemoval() throws {
        let installed = try Self.settings([
            "hooks": [
                "SessionStart": [
                    "a stray string nothing here wrote",
                    ["matcher": "startup", "hooks": [["type": "command", "command": "/bin/gizmo session-start"]]],
                ],
            ],
        ])

        let removal = try GizmoHooks.registration.remove(from: installed, event: GizmoHooks.sessionStart)

        #expect(removal.removed == ["/bin/gizmo session-start"])
        let entries = try #require(try Self.hooks(removal.data)?["SessionStart"] as? [Any])
        #expect(entries.count == 1)
        #expect(entries.first as? String == "a stray string nothing here wrote")
    }

    /// The same hazard one level down, where junk sits in the array our own hook is in.
    @Test
    func junkBesideOurHookInsideAnEntryIsPreservedWhileOursGoes() throws {
        let installed = try Self.settings([
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [
                        ["type": "command", "command": "/bin/gizmo pre-tool-use"],
                        42,
                        ["type": "command", "command": "~/.claude/hooks/audit.sh"],
                    ],
                ]],
            ],
        ])

        let removal = try GizmoHooks.registration.remove(from: installed, event: GizmoHooks.preToolUse)

        #expect(removal.removed == ["/bin/gizmo pre-tool-use"])
        let entries = try #require(try Self.hooks(removal.data)?["PreToolUse"] as? [Any])
        let inner = try #require((entries.first as? [String: Any])?["hooks"] as? [Any])
        #expect(inner.count == 2)
        #expect(inner.first as? Int == 42)
        #expect((inner.last as? [String: Any])?["command"] as? String == "~/.claude/hooks/audit.sh")
    }

    @Test
    func aSecondRunFindsNothingLeftToRemove() throws {
        let first = try Self.removingEveryEvent(from: Self.installedAlongsideAForeignHook())

        let second = try Self.removingEveryEvent(from: first.data)

        #expect(second.removed.isEmpty)
        #expect(second.data == first.data)
    }

    @Test
    func anAbsentSettingsFileHasNothingRegistered() throws {
        let removal = try GizmoHooks.registration.remove(from: nil, event: GizmoHooks.sessionStart)

        #expect(removal.removed.isEmpty)
        #expect(removal.data.isEmpty)
    }

    @Test
    func unreadableSettingsStopTheRemovalRatherThanBeingRewritten() {
        let notAnObject = Data("[1, 2, 3]".utf8)

        #expect(throws: HookRegistrationError.self) {
            try GizmoHooks.registration.remove(from: notAnObject, event: GizmoHooks.sessionStart)
        }
    }

    // MARK: - Partial uninstall

    /// The switch for someone who wants the nudges gone after a week and the rest kept.
    @Test
    func aPartialUninstallNarrowsTheRemovalToThePreToolUseHook() {
        let events = GizmoHooks.registration.eventsToRemove(only: ["pre-tool-use"])

        #expect(events.map(\.name) == ["PreToolUse"])
        #expect(GizmoHooks.registration.eventsToRemove() == GizmoHooks.registration.events)
    }

    @Test
    func aPartialUninstallLeavesThePrimerRegistered() throws {
        var current = try Self.installedAlongsideAForeignHook()
        for event in GizmoHooks.registration.eventsToRemove(only: ["pre-tool-use"]) {
            current = try GizmoHooks.registration.remove(from: current, event: event).data
        }

        #expect(try Self.commands(current, event: "PreToolUse") == [
            "~/.claude/hooks/audit-bash.sh",
            "~/.claude/hooks/protect.sh",
        ])
        #expect(try Self.commands(current, event: "SessionStart") == [
            "/bin/gizmo session-start",
            "/bin/gizmo session-start",
        ])
        #expect(try Self.commands(current, event: "SubagentStart") == ["/bin/gizmo session-start"])
    }
}
