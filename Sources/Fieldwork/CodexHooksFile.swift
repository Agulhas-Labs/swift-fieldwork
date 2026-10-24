// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The hooks a tool registers in Codex's `hooks.json`, and the merge that adds them to or takes them out of that file.
///
/// Codex's file is `{"hooks": {"<Event>": [{"matcher": …, "hooks": [{"type": "command", "command": …}, …]}, …]}}`: per event, groups of handlers. Codex speaks Claude Code's hook protocol, so each command is the plain `<binary> <subcommand>` with no agent flag, and a handler is the tool's by ``FieldworkTool/runs(_:subcommand:)``, in whichever group it sits. Every foreign handler, group and key is carried through verbatim. Codex keys a hook's trust by its group's and handler's positions, so a new group is always appended after the foreign ones, never inserted ahead of them.
///
/// The tool's identity arrives as values: ``tool`` says which commands are its own and ``hooks`` what it registers.
public struct CodexHooksFile: Equatable, Sendable {
    /// The tool whose handlers this writes and removes.
    public let tool: FieldworkTool
    /// Every event registered, the subcommand it runs and the matcher its group carries, in the order an answer lists them.
    public let hooks: [Hook]

    public init(tool: FieldworkTool, hooks: [Hook]) {
        self.tool = tool
        self.hooks = hooks
    }

    /// The file's name inside the Codex directory.
    public static var fileName: String {
        AgentPaths.codexHooksFileName
    }

    /// The command registered for `hook`: the binary, already shell-quoted where it needs to be, then the subcommand.
    public func command(for hook: Hook, binaryWord: String) -> String {
        "\(binaryWord) \(hook.subcommand)"
    }

    /// Every command the tool's `hook` is registered with in `data`, in file order; none for a file that is not there or does not parse.
    public func commands(in data: Data?, for hook: Hook) -> [String] {
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let groups = (file?["hooks"] as? [String: Any])?[hook.event] as? [Any] ?? []
        return groups.flatMap { ($0 as? [String: Any])?["hooks"] as? [Any] ?? [] }.compactMap { handler in
            (handler as? [String: Any])?["command"] as? String
        }
        .filter { tool.runs($0, subcommand: hook.subcommand) }
    }

    /// Merges the tool's hooks into `data` (nil or empty meaning no file yet), repointing a handler of ours that names another binary and dropping any second one, and leaving everything else as it is.
    ///
    /// A handler of `others`' hooks for the same event counts as ours too and is rewritten where it sits, so a switch between two sets of a tool's hooks moves no group or handler.
    public func apply(to data: Data?, binaryWord: String, replacing others: [Hook] = []) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName, harness: Self.harness)
        var events = try CursorConfigJSON.object(file["hooks"], key: "hooks", file: Self.fileName, harness: Self.harness)
        var changed = false
        var replaced: [String] = []
        for hook in hooks {
            let wanted = command(for: hook, binaryWord: binaryWord)
            var found = false
            var groups: [Any] = []
            for group in try CursorConfigJSON.array(events[hook.event], key: hook.event, file: Self.fileName, harness: Self.harness) {
                let pass = try Self.handlers(of: group, event: hook.event) { handler in
                    guard let previous = handler["command"] as? String else { return .keep }
                    let direct = tool.runs(previous, subcommand: hook.subcommand)
                    let switched = !direct && others.contains { $0.event == hook.event && tool.runs(previous, subcommand: $0.subcommand) }
                    guard direct || switched else { return .keep }
                    // A second handler of ours runs the hook twice per event, so only the first survives.
                    guard !found else { return .drop }
                    found = true
                    guard previous != wanted else { return .keep }
                    if !switched, !replaced.contains(previous) {
                        replaced.append(previous)
                    }
                    var repointed = handler
                    repointed["command"] = wanted
                    return .replace(repointed)
                }
                changed = changed || pass.changed
                if let kept = pass.group {
                    groups.append(kept)
                }
            }
            if !found {
                var group: [String: Any] = ["hooks": [["type": "command", "command": wanted]]]
                group["matcher"] = hook.matcher
                groups.append(group)
                changed = true
            }
            events[hook.event] = groups
        }
        guard changed else {
            return Change(data: data ?? Data(), changed: false, replaced: [], removed: [])
        }
        file["hooks"] = events
        return try Change(data: CursorConfigJSON.encode(file), changed: true, replaced: replaced, removed: [])
    }

    /// The events whose groups sit at other positions in `after` than in `before`, which is a group dropped with another following it.
    ///
    /// Codex keys a hook's trust by position, so it asks about those hooks again.
    public static func movedEvents(from before: Data?, to after: Data) -> [String] {
        func events(_ data: Data?) -> [String: [Any]] {
            let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            return (file?["hooks"] as? [String: Any])?.compactMapValues { $0 as? [Any] } ?? [:]
        }
        let now = events(after)
        return events(before).compactMap { (event: String, groups: [Any]) -> String? in
            let remaining = now[event] ?? []
            guard remaining.count < groups.count else { return nil }
            let first = remaining.indices.first { !NSArray(array: [groups[$0]]).isEqual(to: [remaining[$0]]) } ?? remaining.count
            return first < remaining.count ? event : nil
        }
        .sorted()
    }

    /// Takes the tool's handlers of ``hooks`` out of `data`, dropping a group they leave empty, an event with no group left and the `hooks` object when nothing is left in it; every foreign handler, group and key stays.
    public func remove(from data: Data?) throws -> Change {
        var file = try CursorConfigJSON.parse(data, file: Self.fileName, harness: Self.harness)
        var events = try CursorConfigJSON.object(file["hooks"], key: "hooks", file: Self.fileName, harness: Self.harness)
        var removed: [String] = []
        for hook in hooks where events[hook.event] != nil {
            var groups: [Any] = []
            var changed = false
            for group in try CursorConfigJSON.array(events[hook.event], key: hook.event, file: Self.fileName, harness: Self.harness) {
                let pass = try Self.handlers(of: group, event: hook.event) { handler in
                    guard let command = handler["command"] as? String, tool.runs(command, subcommand: hook.subcommand) else {
                        return .keep
                    }
                    removed.append("\(hook.event) — \(command)")
                    return .drop
                }
                changed = changed || pass.changed
                if let kept = pass.group {
                    groups.append(kept)
                }
            }
            guard changed else { continue }
            events[hook.event] = groups.isEmpty ? nil : groups
        }
        guard !removed.isEmpty else {
            return Change(data: data ?? Data(), changed: false, replaced: [], removed: [])
        }
        file["hooks"] = events.isEmpty ? nil : events
        return try Change(data: CursorConfigJSON.encode(file), changed: true, replaced: [], removed: removed)
    }

    /// The harness a refusal of the file's shape names.
    private static var harness: String {
        "Codex"
    }

    /// Runs `decide` over each handler in `group`: the group as it should be written (`nil` when a handler of ours was all it held) and whether it changed.
    ///
    /// Anything that is not a group of handlers is kept as it is.
    private static func handlers(of group: Any, event: String, _ decide: ([String: Any]) -> Verdict) throws -> (group: Any?, changed: Bool) {
        guard var object = group as? [String: Any], object["hooks"] != nil else { return (group, false) }
        let entries = try CursorConfigJSON.array(object["hooks"], key: event, file: fileName, harness: harness)
        var kept: [Any] = []
        var changed = false
        for entry in entries {
            guard let handler = entry as? [String: Any] else {
                kept.append(entry)
                continue
            }
            switch decide(handler) {
            case .keep:
                kept.append(entry)
                continue
            case .drop:
                changed = true
            case let .replace(repointed):
                kept.append(repointed)
                changed = true
            }
        }
        guard changed else { return (group, false) }
        guard !kept.isEmpty else { return (nil, true) }
        object["hooks"] = kept
        return (object, true)
    }
}

extension CodexHooksFile {
    /// What becomes of one handler.
    private enum Verdict {
        case keep
        case drop
        case replace([String: Any])
    }
}

public extension CodexHooksFile {
    /// What a merge did to the file.
    typealias Change = CursorHooksFile.Change

    /// One Codex hook event, the subcommand it runs and its group's matcher.
    struct Hook: Equatable, Sendable {
        /// Codex's name for the event, the key in `hooks.json`.
        public let event: String
        /// The subcommand the handler runs, which is also what ownership is judged on.
        public let subcommand: String
        /// The group's `matcher`, or `nil` for an event that takes none.
        public let matcher: String?

        public init(event: String, subcommand: String, matcher: String?) {
            self.event = event
            self.subcommand = subcommand
            self.matcher = matcher
        }
    }
}
