// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Registers a tool's hooks in a Claude Code `settings.json`, as a pure transform over the file's bytes.
///
/// Deliberately not shell: `settings.json` configures the whole of Claude Code, it is shared with hooks the tool does not own, and a corrupt write breaks every session on the machine. Doing the merge in Swift means no dependency on `python3` or `jq` being present, and merge rules covered by tests rather than by hoping `sed` held.
///
/// The tool's identity arrives as values: ``tool`` says which commands are its own, and ``events`` says what it registers. Two tools can share one settings file, because each registration touches only the entries whose command runs its own binary.
public struct HookRegistration: Sendable {
    /// The tool whose entries this registration writes and removes: an entry belongs to it when its command is this tool's binary running the entry's subcommand.
    public let tool: FieldworkTool

    /// Every event the tool registers for, the subcommand each one runs, and the matchers each one needs.
    ///
    /// Claude Code matchers are anchored, not substring: a matcher of `ash` does not fire for `Bash`. An event with no matcher concept lists no matchers and is written as an entry without the `matcher` key, which fires for every occurrence.
    public let events: [Event]

    public init(tool: FieldworkTool, events: [Event]) {
        self.tool = tool
        self.events = events
    }

    /// A fingerprint of everything the tool registers: every event, the subcommand it runs, and the matchers it needs.
    ///
    /// Compared against ``fingerprint(of:)`` of a settings file so a binary can tell whether the registration firing into it is its own. Derived from ``events`` rather than being a version number, which has to be remembered.
    public var fingerprint: String {
        fingerprint(events)
    }

    /// The same fingerprint of everything except the events that run one of `subcommands`: what a settings file holds after a partial uninstall that removed them.
    ///
    /// A partial uninstall is a decision, not a discrepancy, and it needs a name because it does not compare equal to ``fingerprint``. Derived by removing exactly what ``eventsToRemove(only:)`` removes, so an event added to ``events`` is covered without anyone remembering that this exists.
    public func fingerprint(without subcommands: Set<String>) -> String {
        let removed = eventsToRemove(only: subcommands)
        return fingerprint(events.filter { !removed.contains($0) })
    }

    /// A set of events reduced to one comparable value: the only place the ordering and the join are decided, so the properties above cannot spell the same identity differently.
    ///
    /// Sorted, so the order the events happen to be written in is not part of the identity. Joined on newlines because the value is compared and never parsed, and a matcher is a regex that may hold any punctuation a separator could be mistaken for.
    private func fingerprint(_ events: [Event]) -> String {
        events
            .map { Self.line(event: $0.name, subcommand: $0.subcommand, matchers: $0.matchers) }
            .sorted()
            .joined(separator: "\n\n")
    }

    /// The same fingerprint, taken of what a settings file actually registers for this tool: empty when it registers nothing.
    ///
    /// The half that makes the comparison mean anything. A fingerprint of ``events`` alone describes what the tool would write, which is a fact about the tool and not about the machine; this reads the file at the moment of asking, so an entry the tool would not write is seen: a duplicate registration under a second matcher, an event a previous version registered and this one does not. Anything it cannot read is skipped rather than refused, because this is a check, not a merge.
    ///
    /// It cannot see whether the registered command runs: a registration naming a binary that has since been deleted fingerprints identically to one that works.
    public func fingerprint(of data: Data?) -> String {
        guard let settings = try? Self.parse(data), let hooks = settings["hooks"] as? [String: Any] else {
            return ""
        }
        let subcommands = Set(events.map(\.subcommand))
        // event → subcommand → the matchers that event registers that subcommand against. Two levels
        // because both are part of the identity and neither alone identifies a registration: one event
        // can run two subcommands, and one subcommand can be registered for two events.
        var found: [String: [String: [String]]] = [:]
        for (event, value) in hooks {
            for element in value as? [Any] ?? [] {
                guard let entry = element as? [String: Any] else { continue }
                // Absent is how an event with no matcher concept is written, and it is a matcher list of
                // none rather than a missing one — the same reading `apply` writes with.
                let matcher = entry["matcher"] as? String
                for hook in entry["hooks"] as? [Any] ?? [] {
                    let command = (hook as? [String: Any])?["command"] as? String
                    for subcommand in subcommands where isOurs(command, subcommand: subcommand) {
                        var matchers = found[event]?[subcommand] ?? []
                        if let matcher {
                            matchers.append(matcher)
                        }
                        found[event, default: [:]][subcommand] = matchers
                    }
                }
            }
        }
        return found
            .flatMap { event, bySubcommand in
                bySubcommand.map { Self.line(event: event, subcommand: $0.key, matchers: $0.value) }
            }
            .sorted()
            .joined(separator: "\n\n")
    }

    /// One registration reduced to a fingerprint line: the event, the subcommand it runs, and the matchers it fires on.
    ///
    /// Matchers sorted for the same reason the lines are. The order they are listed in is not part of what is registered, and the two sides of the comparison are written by different things — one by ``events``, the other by whatever last wrote the settings file.
    private static func line(event: String, subcommand: String, matchers: [String]) -> String {
        ([event, subcommand] + matchers.sorted()).joined(separator: "\n")
    }

    /// Merges the hook into `data` (nil or empty meaning "no settings file yet"), leaving everything else untouched.
    ///
    /// Every array is walked as `[Any]` and judged element by element, for a reason that costs more here than it does in `remove`. Casting a whole array to `[[String: Any]]` fails outright on one element of an unexpected shape; a `?? []` fallback would then hand the merge an *empty* array to build on, and writing that back would delete every hook the event already had — silently, on a file this tool did not author. So anything unreadable is carried through verbatim, and a container of the wrong shape entirely is refused rather than replaced.
    public func apply(to data: Data?, command: String, event registering: Event) throws -> Result {
        let event = registering.name
        let subcommand = registering.subcommand
        let matchers = registering.matchers
        let timeout = registering.timeout
        var settings = try Self.parse(data)
        var hooks = try Self.object(settings["hooks"], key: "hooks")
        var registered = try Self.array(hooks[event], key: event)
        var changed = false
        var replaced: [String] = []

        // A matcher is part of the registration, not a key it can be looked up by. Widening `Bash|Read` to
        // `Bash|Read|Grep` finds no entry to update, appends a second one, and the hook then runs *twice* on
        // every Bash call — the same duplicate-registration bug as a moved binary, wearing different clothes.
        // So drop ourselves from every entry this install is not about to write to, before writing any.
        let wanted = Set(matchers.isEmpty ? [nil] : matchers.map(Optional.init))
        for index in registered.indices.reversed() {
            guard let entry = registered[index] as? [String: Any],
                  !wanted.contains(entry["matcher"] as? String)
            else { continue }

            var kept: [Any] = []
            var tookSomething = false
            for hook in try Self.array(entry["hooks"], key: "\(event) hooks") {
                guard let ours = hook as? [String: Any],
                      isOurs(ours["command"] as? String, subcommand: subcommand)
                else {
                    kept.append(hook)
                    continue
                }
                tookSomething = true
            }

            guard tookSomething else { continue }
            changed = true
            if kept.isEmpty {
                registered.remove(at: index)
            } else {
                var trimmed = entry
                trimmed["hooks"] = kept
                registered[index] = trimmed
            }
        }

        // No matchers means one entry that matches everything, which is how an event without a matcher
        // concept is written: the key is simply absent.
        for matcher in matchers.isEmpty ? [nil] : matchers.map(Optional.init) {
            let ours: [String: Any] = ["type": "command", "command": command, "timeout": timeout]

            // Both halves check the element is a dictionary, and the second is the one that has to.
            // `($0 as? [String: Any])?["matcher"] as? String` is nil for a stray element *and* for the
            // matcher-less entry `SubagentStart` legitimately uses, so on that event the lookup alone
            // would select the first stray it met; the re-bind below then fails and appends a fresh entry
            // instead of merging into it. The predicate's own check keeps the search honest — it looks for
            // an entry, not for anything whose absent matcher reads as a match.
            let match = registered.indices.first { index in
                guard let entry = registered[index] as? [String: Any] else { return false }
                return entry["matcher"] as? String == matcher
            }
            guard let index = match, var entry = registered[index] as? [String: Any] else {
                var fresh: [String: Any] = ["hooks": [ours]]
                if let matcher {
                    fresh["matcher"] = matcher
                }
                registered.append(fresh)
                changed = true
                continue
            }

            var inner = try Self.array(entry["hooks"], key: "\(event) hooks")

            // Identify a previous install by shape, not by exact path: the whole point of re-running the
            // installer is that the binary may have moved, and matching on the old path would leave the
            // stale registration in place beside the new one.
            let existing = inner.firstIndex { hook in
                guard let hook = hook as? [String: Any] else { return false }
                return isOurs(hook["command"] as? String, subcommand: subcommand)
            }
            if let existing {
                let previous = (inner[existing] as? [String: Any])?["command"] as? String ?? ""
                guard previous != command else { continue }
                // Distinct, not per-matcher: one moved binary is one fact to report, not three.
                if !replaced.contains(previous) {
                    replaced.append(previous)
                }
                inner[existing] = ours
            } else {
                inner.append(ours)
            }

            entry["hooks"] = inner
            registered[index] = entry
            changed = true
        }

        guard changed else {
            return Result(data: data ?? Data(), changed: false, replaced: [])
        }

        hooks[event] = registered
        settings["hooks"] = hooks
        let encoded = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return Result(data: encoded, changed: true, replaced: replaced)
    }

    /// The events an uninstall covers: all of them, or only those that run one of `subcommands`.
    ///
    /// Named here rather than filtered at the call site so what a partial uninstall means is one fact the test suite can pin.
    public func eventsToRemove(only subcommands: Set<String>? = nil) -> [Event] {
        guard let subcommands else { return events }
        return events.filter { subcommands.contains($0.subcommand) }
    }

    /// Removes this tool's registration for one event, leaving every hook it did not write untouched.
    ///
    /// The exact inverse of `apply`, and it has to be as careful: `settings.json` is shared with hooks this project does not own, so a foreign entry in the same event array survives, and so does a foreign hook sitting beside ours inside one entry. Removal prunes what it empties — an entry that existed only for us, an event array left with nothing in it, and the `hooks` object itself — because a file that accumulates `"SessionStart": []` husks is one an uninstall did not really finish.
    ///
    /// Reports the commands it took out rather than a bare flag: an uninstaller that cannot say which registration it found is asking to be trusted about the one thing worth checking.
    ///
    /// Every array is walked as `[Any]` and judged element by element. Casting a whole array to `[[String: Any]]` fails outright on one element of an unexpected shape, and the failure is silent: the removal would find nothing, report nothing registered, and leave the registration in place. Anything this cannot read is carried through verbatim — it is certainly not something this tool wrote.
    ///
    /// It reads its two containers through the same ``object(_:key:)`` and ``array(_:key:)`` that `apply` does, so an unreadable one refuses here exactly as it does there. The distinction they draw is the whole point: absent means nothing is registered, and *present but the wrong shape* means this could not tell — reporting "nothing registered" for the second is the one answer an uninstaller must never give, since it is indistinguishable from a clean sweep over a registration that is still sitting in the file.
    public func remove(from data: Data?, event removing: Event) throws -> Removal {
        let event = removing.name
        let subcommand = removing.subcommand
        var settings = try Self.parse(data)
        var hooks = try Self.object(settings["hooks"], key: "hooks")
        let registered = try Self.array(hooks[event], key: event)
        guard !registered.isEmpty else {
            return Removal(data: data ?? Data(), removed: [])
        }

        var kept: [Any] = []
        var removed: [String] = []
        for element in registered {
            guard let entry = element as? [String: Any] else {
                kept.append(element)
                continue
            }

            var survivors: [Any] = []
            var tookSomething = false
            for hook in entry["hooks"] as? [Any] ?? [] {
                guard let ours = hook as? [String: Any],
                      isOurs(ours["command"] as? String, subcommand: subcommand)
                else {
                    survivors.append(hook)
                    continue
                }
                tookSomething = true
                // Distinct: one binary registered against three matchers is one thing removed, not three.
                let command = ours["command"] as? String ?? ""
                if !removed.contains(command) {
                    removed.append(command)
                }
            }

            guard tookSomething else {
                kept.append(entry)
                continue
            }
            guard !survivors.isEmpty else { continue }
            var trimmed = entry
            trimmed["hooks"] = survivors
            kept.append(trimmed)
        }

        guard !removed.isEmpty else {
            return Removal(data: data ?? Data(), removed: [])
        }

        if kept.isEmpty {
            hooks.removeValue(forKey: event)
        } else {
            hooks[event] = kept
        }
        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        let encoded = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return Removal(data: encoded, removed: removed)
    }

    /// Whether a registered command is this tool's hook for `subcommand`, at any path.
    ///
    /// Matched on shape rather than exact path, because the whole point of re-running the installer is that the binary may have moved, and on the subcommand as well as the binary, so the hooks a tool registers can never be mistaken for one another. The shape is exact (``FieldworkTool/runs(_:subcommand:)``): an executable named for the tool running this subcommand alone, so another tool's hook in the same file is never touched.
    public func isOurs(_ command: String?, subcommand: String) -> Bool {
        guard let command else { return false }
        return tool.runs(command, subcommand: subcommand)
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookRegistrationError.settingsNotAnObject
        }
        return object
    }

    /// Reads a container that a merge is about to build on, refusing anything it would have to replace.
    ///
    /// Absent is the ordinary case and means "start from empty". Present but the wrong shape is the case that must not silently become empty: whatever is there is someone's configuration, and a merge that treats it as nothing writes over it. This is the whole difference between a missing key and an unreadable one, and conflating them is how a stray array element costs an event every hook it has.
    private static func object(_ value: Any?, key: String) throws -> [String: Any] {
        guard let value else { return [:] }
        guard let object = value as? [String: Any] else {
            throw HookRegistrationError.hooksNotMergeable(key: key)
        }
        return object
    }

    private static func array(_ value: Any?, key: String) throws -> [Any] {
        guard let value else { return [] }
        guard let array = value as? [Any] else {
            throw HookRegistrationError.hooksNotMergeable(key: key)
        }
        return array
    }
}

public extension HookRegistration {
    /// One hook event, the subcommand it runs, and what it matches on.
    struct Event: Equatable, Sendable {
        public let name: String
        public let subcommand: String
        /// Empty for an event with no matcher concept, which is written as an entry with no `matcher` key.
        public let matchers: [String]
        /// Seconds Claude Code waits for this hook before moving on; each event picks its own.
        public let timeout: Int

        public init(name: String, subcommand: String, matchers: [String] = [], timeout: Int = 5) {
            self.name = name
            self.subcommand = subcommand
            self.matchers = matchers
            self.timeout = timeout
        }
    }

    /// What a removal took out, for an uninstaller that should name the registration it found rather than claim success blandly.
    struct Removal: Equatable, Sendable {
        public let data: Data
        /// The commands removed, distinct; empty means this event carried no registration of ours and `data` is the input unchanged.
        public let removed: [String]
    }

    /// The outcome of a merge, for an installer that should say what it did rather than claim success blandly.
    struct Result: Equatable, Sendable {
        public let data: Data
        /// False when the file already had exactly this registration — the re-run and upgrade case.
        public let changed: Bool
        /// Commands this replaced, i.e. a previous install at a different path.
        public let replaced: [String]
    }
}
