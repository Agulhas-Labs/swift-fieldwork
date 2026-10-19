// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The hooks a tool registers in Cursor's `~/.cursor/hooks.json`, and the merge that adds them to or takes them out of that file.
///
/// Cursor's file is `{"version": 1, "hooks": {"<event>": [{"command": …}, …]}}`: one flat array of entries per event, each entry one command run through a shell. An entry is the tool's only when its command is an executable named for the tool running the event's subcommand with ``agentFlag`` and nothing else (``FieldworkTool/runs(_:subcommand:)``), so a foreign entry in the same array, another tool's included, and every key this tool does not write, is carried through verbatim. Each entry carries only `command`, the shape a live Cursor was seen to run; Cursor's fail-closed flag is never written, since a hook that fails must never make a call unavailable.
///
/// The tool's identity arrives as values: ``tool`` says which commands are its own, ``hooks`` what it registers and ``agentFlag`` how its handler is told it is answering Cursor.
public struct CursorHooksFile: Equatable, Sendable {
    /// The tool whose entries this writes and removes.
    public let tool: FieldworkTool
    /// The flag every registered command carries, so the handler answers in Cursor's protocol rather than guessing it from the payload.
    public let agentFlag: String
    /// Every event registered and the subcommand it runs, in the order an answer lists them.
    public let hooks: [Hook]

    public init(tool: FieldworkTool, agentFlag: String, hooks: [Hook]) {
        self.tool = tool
        self.agentFlag = agentFlag
        self.hooks = hooks
    }

    /// The file's name inside the Cursor directory.
    public static var fileName: String {
        AgentPaths.cursorHooksFileName
    }

    /// The command registered for `hook`: the binary, already shell-quoted where it needs to be, then the subcommand and the flag.
    public func command(for hook: Hook, binaryWord: String) -> String {
        "\(binaryWord) \(registeredSubcommand(for: hook))"
    }

    /// The subcommand of `hook` as registered: with the flag when there is one, which is also what ownership is judged on.
    public func registeredSubcommand(for hook: Hook) -> String {
        agentFlag.isEmpty ? hook.subcommand : "\(hook.subcommand) \(agentFlag)"
    }

    /// Merges this tool's hooks into `data` (nil or empty meaning no file yet), repointing an entry of ours that names another binary and dropping any second one, and leaving everything else as it is.
    public func apply(to data: Data?, binaryWord: String) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName)
        var events = try CursorConfigJSON.object(file["hooks"], key: "hooks", file: Self.fileName)
        var changed = false
        var replaced: [String] = []
        for hook in hooks {
            let wanted = command(for: hook, binaryWord: binaryWord)
            var entries = try CursorConfigJSON.array(events[hook.event], key: hook.event, file: Self.fileName)
            var kept: [Any] = []
            var found = false
            for element in entries {
                guard var entry = element as? [String: Any],
                      let previous = entry["command"] as? String,
                      tool.runs(previous, subcommand: registeredSubcommand(for: hook))
                else {
                    kept.append(element)
                    continue
                }
                // A second entry of ours runs the handler twice per event, so only the first survives.
                guard !found else {
                    changed = true
                    continue
                }
                found = true
                if previous != wanted {
                    entry["command"] = wanted
                    changed = true
                    if !replaced.contains(previous) {
                        replaced.append(previous)
                    }
                }
                kept.append(entry)
            }
            if !found {
                kept.append(["command": wanted])
                changed = true
            }
            entries = kept
            events[hook.event] = entries
        }
        guard changed else {
            return Change(data: data ?? Data(), changed: false, replaced: [], removed: [])
        }
        file["hooks"] = events
        if file["version"] == nil {
            file["version"] = 1
        }
        return try Change(data: CursorConfigJSON.encode(file), changed: true, replaced: replaced, removed: [])
    }

    /// Takes this tool's hooks out of `data`, dropping an event array it leaves empty and the `hooks` object when nothing is left in it; every foreign entry and key stays, `version` included.
    public func remove(from data: Data?) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName)
        var events = try CursorConfigJSON.object(file["hooks"], key: "hooks", file: Self.fileName)
        var removed: [String] = []
        for hook in hooks {
            guard events[hook.event] != nil else { continue }
            let entries = try CursorConfigJSON.array(events[hook.event], key: hook.event, file: Self.fileName)
            var kept: [Any] = []
            for element in entries {
                guard let entry = element as? [String: Any],
                      let command = entry["command"] as? String,
                      tool.runs(command, subcommand: registeredSubcommand(for: hook))
                else {
                    kept.append(element)
                    continue
                }
                removed.append("\(hook.event) — \(command)")
            }
            guard kept.count != entries.count else { continue }
            events[hook.event] = kept.isEmpty ? nil : kept
        }
        guard !removed.isEmpty else {
            return Change(data: data ?? Data(), changed: false, replaced: [], removed: [])
        }
        file["hooks"] = events.isEmpty ? nil : events
        return try Change(data: CursorConfigJSON.encode(file), changed: true, replaced: [], removed: removed)
    }
}

public extension CursorHooksFile {
    /// One Cursor hook event and the subcommand it runs.
    struct Hook: Equatable, Sendable {
        /// Cursor's name for the event, the key in `hooks.json`.
        public let event: String
        /// The subcommand the handler runs, without the flag.
        public let subcommand: String

        public init(event: String, subcommand: String) {
            self.event = event
            self.subcommand = subcommand
        }
    }

    /// What a merge did to the file.
    struct Change: Equatable, Sendable {
        /// The file as it should be written; the input unchanged when ``changed`` is false.
        public let data: Data
        /// Whether ``data`` differs from what was read.
        public let changed: Bool
        /// The commands of ours that named another binary and were repointed, each once.
        public let replaced: [String]
        /// One `<event> — <command>` per entry taken out.
        public let removed: [String]

        public init(data: Data, changed: Bool, replaced: [String], removed: [String]) {
            self.data = data
            self.changed = changed
            self.replaced = replaced
            self.removed = removed
        }
    }
}
