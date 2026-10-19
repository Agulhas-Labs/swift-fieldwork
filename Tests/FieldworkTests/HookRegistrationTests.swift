// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the `settings.json` merge — the part of the install that can break every session on the machine if it gets it wrong.
struct HookRegistrationTests {
    private static func object(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
    }

    private static func sessionStart(_ data: Data, sourceLocation: SourceLocation = #_sourceLocation) throws -> [[String: Any]] {
        let hooks = try #require(try object(data, sourceLocation: sourceLocation)["hooks"] as? [String: Any], sourceLocation: sourceLocation)
        return try #require(hooks["SessionStart"] as? [[String: Any]], sourceLocation: sourceLocation)
    }

    private static func commands(_ data: Data, matcher: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let entry = try #require(
            try sessionStart(data, sourceLocation: sourceLocation).first { $0["matcher"] as? String == matcher },
            sourceLocation: sourceLocation
        )
        let inner = try #require(entry["hooks"] as? [[String: Any]], sourceLocation: sourceLocation)
        return inner.compactMap { $0["command"] as? String }
    }

    @Test
    func registersEveryMatcherInAnAbsentSettingsFile() throws {
        let result = try GizmoHooks.registration.apply(to: nil, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(result.changed)
        #expect(result.replaced.isEmpty)
        for matcher in GizmoHooks.sessionStart.matchers {
            #expect(try Self.commands(result.data, matcher: matcher) == ["/bin/gizmo session-start"])
        }
    }

    /// `/clear` discards the context, and with it the primer — a cleared session still does the Swift work.
    @Test
    func clearIsAmongTheMatchers() {
        #expect(GizmoHooks.sessionStart.matchers.contains("clear"))
    }

    /// A compaction discards the context mid-task, and the primer survives it only if the summary happens to keep it.
    @Test
    func compactIsAmongTheMatchers() {
        #expect(GizmoHooks.sessionStart.matchers.contains("compact"))
    }

    /// A registration written before `compact` was a matcher is the upgrade case: re-running the install adds it beside the three already there, and duplicates none of them.
    @Test
    func reRunningOverAnOlderRegistrationAddsCompact() throws {
        let older = try GizmoHooks.registration.apply(
            to: nil,
            command: "/bin/gizmo session-start",
            event: HookRegistration.Event(name: "SessionStart", subcommand: "session-start", matchers: ["startup", "resume", "clear"])
        )
        let upgraded = try GizmoHooks.registration.apply(to: older.data, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(upgraded.changed)
        for matcher in ["startup", "resume", "clear", "compact"] {
            #expect(try Self.commands(upgraded.data, matcher: matcher) == ["/bin/gizmo session-start"])
        }
    }

    /// Subagents get neither a session start nor the path-scoped rule, which would leave the contexts doing the heaviest whole-file reading as the only ones with no guidance at all.
    @Test
    func subagentStartIsAmongTheEventsRegistered() {
        #expect(GizmoHooks.registration.events.contains { $0.name == "SubagentStart" })
    }

    /// `SubagentStart` has no matcher concept, so the entry must carry no `matcher` key — one with a matcher of `"startup"` copied across from the session hook would simply never fire.
    @Test
    func theSubagentEntryCarriesNoMatcher() throws {
        let result = try GizmoHooks.registration.apply(
            to: nil,
            command: "/bin/gizmo session-start",
            event: GizmoHooks.subagentStart
        )
        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["SubagentStart"] as? [[String: Any]])

        #expect(entries.count == 1)
        #expect(entries[0]["matcher"] == nil)
        let inner = try #require(entries[0]["hooks"] as? [[String: Any]])
        #expect(inner.compactMap { $0["command"] as? String } == ["/bin/gizmo session-start"])
    }

    /// Re-running the installer is the upgrade path for both events, not just the one.
    @Test
    func aSecondRunOfTheSubagentRegistrationChangesNothing() throws {
        let first = try GizmoHooks.registration.apply(
            to: nil,
            command: "/bin/gizmo session-start",
            event: GizmoHooks.subagentStart
        )
        let second = try GizmoHooks.registration.apply(
            to: first.data,
            command: "/bin/gizmo session-start",
            event: GizmoHooks.subagentStart
        )

        #expect(second.changed == false)
    }

    /// A moved binary must be repointed for the subagent event too, or an upgrade leaves subagents calling the old path.
    @Test
    func aMovedBinaryIsRepointedForTheSubagentEventAsWell() throws {
        let first = try GizmoHooks.registration.apply(
            to: nil,
            command: "/old/gizmo session-start",
            event: GizmoHooks.subagentStart
        )
        let second = try GizmoHooks.registration.apply(
            to: first.data,
            command: "/new/gizmo session-start",
            event: GizmoHooks.subagentStart
        )
        let hooks = try #require(try Self.object(second.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["SubagentStart"] as? [[String: Any]])
        let inner = try #require(entries[0]["hooks"] as? [[String: Any]])

        #expect(second.replaced == ["/old/gizmo session-start"])
        #expect(inner.compactMap { $0["command"] as? String } == ["/new/gizmo session-start"])
    }

    /// Registering each event must leave the others exactly as they were — they share one file, and the installer applies them in sequence over the same bytes.
    @Test
    func registeringEveryEventLeavesEachIntact() throws {
        var merged: Data?
        for event in GizmoHooks.registration.events {
            merged = try GizmoHooks.registration.apply(
                to: merged,
                command: "/bin/gizmo \(event.subcommand)",
                event: event
            ).data
        }
        let data = try #require(merged)
        let hooks = try #require(try Self.object(data)["hooks"] as? [String: Any])

        #expect(hooks["SubagentStart"] != nil)
        #expect(hooks["PreToolUse"] != nil)
        for matcher in GizmoHooks.sessionStart.matchers {
            #expect(try Self.commands(data, matcher: matcher) == ["/bin/gizmo session-start"])
        }
    }

    /// Bash and Read carry nearly every lookup that goes around the index between them — shell lookups first, whole-file reads second — and Grep and Glob are here to close the doors beside them, so a refused shell lookup cannot simply be re-asked through a tool.
    @Test
    func preToolUseIsRegisteredForTheToolsThatCarryTheMiss() throws {
        let event = try #require(GizmoHooks.registration.events.first { $0.name == "PreToolUse" })
        #expect(event.subcommand == "pre-tool-use")
        // Named rather than left off: a PreToolUse hook without a matcher runs on every tool call, which
        // is a per-call cost paid on things this would never have an opinion about.
        // Every alternative is spelled out because matchers are anchored, not substring: verified live,
        // a matcher of `ash` does not fire for `Bash`, so `Read` would never have caught `XcodeRead`.
        #expect(event.matchers == ["Bash|Read|Grep|Glob|mcp__gizmo__.*|Write|Edit|MultiEdit"])

        let result = try GizmoHooks.registration.apply(
            to: nil,
            command: "/bin/gizmo pre-tool-use",
            event: GizmoHooks.preToolUse
        )
        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["PreToolUse"] as? [[String: Any]])

        #expect(entries.count == 1)
        #expect(entries[0]["matcher"] as? String == "Bash|Read|Grep|Glob|mcp__gizmo__.*|Write|Edit|MultiEdit")
    }

    /// Widening a matcher must move the registration, not add a second one — otherwise the upgrade that adds a tool makes the hook fire twice on every call of the tools it already covered.
    @Test
    func wideningAMatcherLeavesNoRegistrationBehindOnTheOldOne() throws {
        let first = try GizmoHooks.registration.apply(
            to: nil,
            command: "/bin/gizmo pre-tool-use",
            event: HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["Bash|Read"])
        )
        let second = try GizmoHooks.registration.apply(
            to: first.data,
            command: "/bin/gizmo pre-tool-use",
            event: HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["Bash|Read|Grep"])
        )
        let hooks = try #require(try Self.object(second.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["PreToolUse"] as? [[String: Any]])

        #expect(second.changed)
        #expect(entries.count == 1)
        #expect(entries[0]["matcher"] as? String == "Bash|Read|Grep")
    }

    /// The sweep that does it must take only *our* hook with it: another tool's `PreToolUse` entry on the abandoned matcher is not ours to delete.
    @Test
    func aForeignHookOnTheAbandonedMatcherSurvives() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "Bash",
                    "hooks": [
                        ["type": "command", "command": "/opt/guard.sh"],
                        ["type": "command", "command": "/bin/gizmo pre-tool-use"],
                    ],
                ]],
            ],
        ])

        let result = try GizmoHooks.registration.apply(
            to: existing,
            command: "/bin/gizmo pre-tool-use",
            event: HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["Bash|Read|Grep"])
        )
        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["PreToolUse"] as? [[String: Any]])
        let onBash = try #require(entries.first { $0["matcher"] as? String == "Bash" })
        let inner = try #require(onBash["hooks"] as? [[String: Any]])

        #expect(inner.compactMap { $0["command"] as? String } == ["/opt/guard.sh"])
        #expect(entries.contains { $0["matcher"] as? String == "Bash|Read|Grep" })
    }

    /// The two hooks run different subcommands, so identifying "ours" by the binary name alone would let one be repointed onto the other's entry.
    @Test
    func theTwoHooksAreToldApartBySubcommand() {
        #expect(GizmoHooks.registration.isOurs("/bin/gizmo session-start", subcommand: "session-start"))
        #expect(!GizmoHooks.registration.isOurs("/bin/gizmo session-start", subcommand: "pre-tool-use"))
        #expect(GizmoHooks.registration.isOurs("/bin/gizmo pre-tool-use", subcommand: "pre-tool-use"))
        #expect(!GizmoHooks.registration.isOurs("/bin/gizmo pre-tool-use", subcommand: "session-start"))
    }

    /// Re-running the installer is the upgrade path, so a second identical run must be a no-op.
    @Test
    func aSecondRunChangesNothing() throws {
        let first = try GizmoHooks.registration.apply(to: nil, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        let second = try GizmoHooks.registration.apply(to: first.data, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(second.changed == false)
        #expect(second.data == first.data)
    }

    /// A moved binary must be repointed, not registered twice.
    @Test
    func aRegistrationAtAnOldPathIsReplacedRatherThanDuplicated() throws {
        let first = try GizmoHooks.registration.apply(to: nil, command: "/old/gizmo session-start", event: GizmoHooks.sessionStart)
        let second = try GizmoHooks.registration.apply(to: first.data, command: "/new/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(second.changed)
        // One moved binary is one fact, however many matchers carried it.
        #expect(second.replaced == ["/old/gizmo session-start"])
        for matcher in GizmoHooks.sessionStart.matchers {
            #expect(try Self.commands(second.data, matcher: matcher) == ["/new/gizmo session-start"])
        }
    }

    /// The file is shared: another tool's startup hook sits on the same matchers and must survive untouched.
    @Test
    func anUnrelatedHookOnTheSameMatcherIsPreserved() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "theme": "dark",
            "hooks": [
                "SessionStart": [
                    ["matcher": "startup", "hooks": [["type": "command", "command": "/opt/another-tool-hook.sh", "timeout": 10]]],
                ],
            ],
        ])

        let result = try GizmoHooks.registration.apply(to: existing, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(try Self.commands(result.data, matcher: "startup")
            == ["/opt/another-tool-hook.sh", "/bin/gizmo session-start"])
        #expect(try Self.object(result.data)["theme"] as? String == "dark")
    }

    @Test
    func unrelatedSettingsKeysSurviveTheMerge() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "permissions": ["allow": ["Bash(git status)"]],
            "effortLevel": "high",
        ])

        let result = try GizmoHooks.registration.apply(to: existing, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        let merged = try Self.object(result.data)

        #expect(merged["effortLevel"] as? String == "high")
        let permissions = try #require(merged["permissions"] as? [String: Any])
        #expect(permissions["allow"] as? [String] == ["Bash(git status)"])
    }

    /// Other hook events (PreToolUse and friends) live in the same dictionary and are none of this tool's business.
    @Test
    func otherHookEventsAreUntouched() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "/opt/guard.sh"]]]]],
        ])

        let result = try GizmoHooks.registration.apply(to: existing, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])

        #expect(hooks["PreToolUse"] != nil)
        #expect(hooks["SessionStart"] != nil)
    }

    /// Overwriting a settings file that will not parse would destroy a configuration this tool did not author.
    @Test
    func anUnparseableSettingsFileStopsTheInstall() throws {
        #expect(throws: (any Error).self) {
            try GizmoHooks.registration.apply(to: Data("not json".utf8), command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        }
    }

    @Test
    func aJSONArrayIsRejectedAsWell() throws {
        #expect(throws: HookRegistrationError.settingsNotAnObject) {
            try GizmoHooks.registration.apply(to: Data("[1,2,3]".utf8), command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        }
    }

    @Test
    func anEmptyFileIsTreatedAsAbsentRatherThanCorrupt() throws {
        let result = try GizmoHooks.registration.apply(to: Data(), command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)

        #expect(result.changed)
    }

    @Test
    func registeredPathsAreNotSlashEscaped() throws {
        let result = try GizmoHooks.registration.apply(to: nil, command: "/Users/me/.local/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        let text = try #require(String(data: result.data, encoding: .utf8))

        #expect(text.contains("/Users/me/.local/bin/gizmo session-start"))
        #expect(!text.contains("\\/"))
    }

    @Test
    func ourCommandIsRecognisedAtAnyPathAndOthersAreNot() {
        #expect(GizmoHooks.registration.isOurs("/anywhere/gizmo session-start", subcommand: "session-start"))
        #expect(GizmoHooks.registration.isOurs("/opt/another-tool-hook.sh", subcommand: "session-start") == false)
        #expect(GizmoHooks.registration.isOurs("/anywhere/gizmo mcp", subcommand: "session-start") == false)
        #expect(GizmoHooks.registration.isOurs(nil, subcommand: "session-start") == false)
    }

    // MARK: - Elements the merge cannot read

    /// The worst outcome this file can produce, and it is reachable from one stray array element.
    ///
    /// Casting the event's array to `[[String: Any]]` fails on the stray, `?? []` hands the merge an empty array to build on, and writing that back deletes every hook the event had — someone else's, in a file this tool did not author. Registering ours must cost the neighbours nothing.
    @Test
    func aStrayElementInAnEventArrayDoesNotCostTheEventItsExistingHooks() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": [
                "SessionStart": [
                    "a stray element nothing here wrote",
                    ["matcher": "startup", "hooks": [["type": "command", "command": "~/.claude/hooks/mine.sh"]]],
                ],
            ],
        ])

        let result = try GizmoHooks.registration.apply(
            to: existing,
            command: "/bin/gizmo session-start",
            event: HookRegistration.Event(name: "SessionStart", subcommand: "session-start", matchers: ["startup"])
        )

        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["SessionStart"] as? [Any])
        #expect(entries.count == 2)
        #expect(entries.first as? String == "a stray element nothing here wrote")
        let entry = try #require(entries.last as? [String: Any])
        let inner = try #require(entry["hooks"] as? [Any])
        #expect(inner.compactMap { ($0 as? [String: Any])?["command"] as? String } == [
            "~/.claude/hooks/mine.sh",
            "/bin/gizmo session-start",
        ])
    }

    /// The same hazard one level down, where the empty fallback empties a single entry rather than the event.
    @Test
    func junkInsideAnEntryDoesNotCostThatEntryItsExistingHooks() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": [
                "SessionStart": [[
                    "matcher": "startup",
                    "hooks": [42, ["type": "command", "command": "~/.claude/hooks/mine.sh"]],
                ]],
            ],
        ])

        let result = try GizmoHooks.registration.apply(
            to: existing,
            command: "/bin/gizmo session-start",
            event: HookRegistration.Event(name: "SessionStart", subcommand: "session-start", matchers: ["startup"])
        )

        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["SessionStart"] as? [Any])
        let inner = try #require((entries.first as? [String: Any])?["hooks"] as? [Any])

        #expect(inner.count == 3)
        #expect(inner.first as? Int == 42)
        #expect(inner.compactMap { ($0 as? [String: Any])?["command"] as? String } == [
            "~/.claude/hooks/mine.sh",
            "/bin/gizmo session-start",
        ])
    }

    /// A stray element must not be mistaken for the matcher-less entry and merged into.
    ///
    /// `(element as? [String: Any])?["matcher"]` is nil for a stray *and* for the `SubagentStart` entry that legitimately carries no matcher, so a lookup that compares those two nils treats the first stray element it meets as the entry to write into.
    @Test
    func aStrayElementIsNotMistakenForTheMatcherlessEntry() throws {
        let existing = try JSONSerialization.data(withJSONObject: [
            "hooks": ["SubagentStart": ["a stray element nothing here wrote"]],
        ])

        let result = try GizmoHooks.registration.apply(
            to: existing,
            command: "/bin/gizmo session-start",
            event: GizmoHooks.subagentStart
        )

        let hooks = try #require(try Self.object(result.data)["hooks"] as? [String: Any])
        let entries = try #require(hooks["SubagentStart"] as? [Any])
        #expect(entries.count == 2)
        #expect(entries.first as? String == "a stray element nothing here wrote")
        let inner = try #require((entries.last as? [String: Any])?["hooks"] as? [Any])
        #expect(inner.compactMap { ($0 as? [String: Any])?["command"] as? String } == ["/bin/gizmo session-start"])
    }

    /// A container of the wrong shape entirely cannot be merged into, only replaced — so it is refused, the way an unparseable file is.
    @Test
    func aHooksKeyOfTheWrongShapeIsRefusedRatherThanReplaced() throws {
        let existing = try JSONSerialization.data(withJSONObject: ["hooks": "handled elsewhere"])

        #expect(throws: HookRegistrationError.hooksNotMergeable(key: "hooks")) {
            try GizmoHooks.registration.apply(to: existing, command: "/bin/gizmo session-start", event: GizmoHooks.sessionStart)
        }
    }

    /// The uninstall refuses the same shapes the install does, rather than reporting a clean sweep over a container it could not read.
    ///
    /// "Nothing registered" is a claim about the file, and it is the one an uninstaller must be right about: said over an unreadable `hooks`, it is indistinguishable from success while the registration is still sitting there.
    @Test
    func anUnreadableContainerStopsTheUninstallRatherThanReportingNothingRegistered() throws {
        let hooksIsAnArray = try JSONSerialization.data(withJSONObject: ["hooks": ["handled elsewhere"]])
        let eventIsAnObject = try JSONSerialization.data(withJSONObject: ["hooks": ["SessionStart": [:]]])

        #expect(throws: HookRegistrationError.hooksNotMergeable(key: "hooks")) {
            try GizmoHooks.registration.remove(from: hooksIsAnArray, event: GizmoHooks.sessionStart)
        }
        #expect(throws: HookRegistrationError.hooksNotMergeable(key: "SessionStart")) {
            try GizmoHooks.registration.remove(from: eventIsAnObject, event: GizmoHooks.sessionStart)
        }
    }

    /// A settings file with no hooks at all is the ordinary case, and still means what it says.
    @Test
    func anAbsentContainerStillReportsNothingRegistered() throws {
        let noHooks = try JSONSerialization.data(withJSONObject: ["model": "opus"])
        let otherEvents = try JSONSerialization.data(withJSONObject: ["hooks": ["Stop": []]])

        #expect(try GizmoHooks.registration.remove(from: noHooks, event: GizmoHooks.sessionStart).removed.isEmpty)
        #expect(try GizmoHooks.registration.remove(from: otherEvents, event: GizmoHooks.sessionStart).removed.isEmpty)
        #expect(try GizmoHooks.registration.remove(from: nil, event: GizmoHooks.sessionStart).removed.isEmpty)
    }
}
