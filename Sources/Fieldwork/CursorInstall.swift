// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A tool's install and uninstall for Cursor: the MCP server in the Cursor directory's `mcp.json` and the hooks in its `hooks.json`, with the guarantees `settings.json` gets.
///
/// Both files are read and merged before either is written, so a refusal of one leaves both as they were. A file that is there and cannot be read, or leads nowhere, is refused rather than read as empty; a rewrite keeps a `.bak-<name>` copy beside the file it changes and writes through a symlink, keeping the link (``SettingsFile``). A run with nothing to change writes nothing. Two tools can share both files: each touches only its own entries and keeps its own backup.
public struct CursorInstall: Equatable, Sendable {
    /// The server this registers in `mcp.json`.
    public let mcp: CursorMcpFile
    /// The hooks this registers in `hooks.json`.
    public let hooks: CursorHooksFile
    /// The option a refusal names as pointing the install at another directory.
    public let directoryFlag: String

    public init(mcp: CursorMcpFile, hooks: CursorHooksFile, directoryFlag: String) {
        self.mcp = mcp
        self.hooks = hooks
        self.directoryFlag = directoryFlag
    }

    private static var agent: String {
        "cursor"
    }

    /// Registers the server and the hooks in `directory`: the absolute path `mcp.json` names, and the same path as the first word of each hook's shell command.
    public func install(directory: URL, binary: String, binaryWord: String) throws -> InstallOutcome {
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        let mcpOriginal = try SettingsFile.read(mcpURL, agent: Self.agent, flag: directoryFlag)
        let hooksOriginal = try SettingsFile.read(hooksURL, agent: Self.agent, flag: directoryFlag)
        let server = try SettingsFile.merge(mcpURL, agent: Self.agent) { try mcp.apply(to: mcpOriginal, binary: binary) }
        let merged = try SettingsFile.merge(hooksURL, agent: Self.agent) { try hooks.apply(to: hooksOriginal, binaryWord: binaryWord) }

        var lines: [String] = []
        let registered = mcp.server.registered(binary: binary)
        let name = mcp.server.name
        switch server.outcome {
        case .registered:
            lines.append("mcp: registered \(name) — \(registered)")
        case let .replaced(previous):
            lines.append("mcp: replaced stale registration (\(previous))")
            lines.append("mcp: registered \(name) — \(registered)")
        case .unchanged, .removed:
            lines.append("mcp: already registered — \(registered)")
        case let .foreign(existing):
            lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
        }
        if merged.changed {
            lines += merged.replaced.map { "hooks: replaced stale registration (\($0))" }
            lines += hooks.hooks.map { "hooks: registered \($0.event) — \(hooks.command(for: $0, binaryWord: binaryWord))" }
        } else {
            lines.append("hooks: already registered — \(hooks.hooks.map(\.event).joined(separator: ", "))")
        }

        var outcome = InstallOutcome(lines: lines)
        try SettingsFile.write(&outcome, mcpURL, server.data, original: mcpOriginal, if: server.changed, tool: mcp.server.tool)
        try SettingsFile.write(&outcome, hooksURL, merged.data, original: hooksOriginal, if: merged.changed, tool: hooks.tool)
        return outcome
    }

    /// Takes out what the install wrote, and nothing else: a foreign server of the same name and every foreign hook stay, and a file with nothing of ours in it is not rewritten.
    public func uninstall(directory: URL) throws -> InstallOutcome {
        let mcpURL = directory.appendingPathComponent(CursorMcpFile.fileName)
        let hooksURL = directory.appendingPathComponent(CursorHooksFile.fileName)
        let mcpOriginal = try SettingsFile.read(mcpURL, agent: Self.agent, flag: directoryFlag)
        let hooksOriginal = try SettingsFile.read(hooksURL, agent: Self.agent, flag: directoryFlag)
        let server = try SettingsFile.merge(mcpURL, agent: Self.agent) { try mcp.remove(from: mcpOriginal) }
        let merged = try SettingsFile.merge(hooksURL, agent: Self.agent) { try hooks.remove(from: hooksOriginal) }

        var lines: [String] = []
        var notes: [String] = []
        let name = mcp.server.name
        switch server.outcome {
        case let .removed(existing):
            lines.append("mcp: removed \(name) — \(existing)")
        case let .foreign(existing):
            notes.append("mcp: not ours, left alone — a server named \(name) in \(mcpURL.path) runs something else (\(existing))")
        case .registered, .replaced, .unchanged:
            break
        }
        lines += merged.removed.map { "hooks: removed \($0)" }

        var outcome = InstallOutcome(lines: lines, notes: notes)
        try SettingsFile.write(&outcome, mcpURL, server.data, original: mcpOriginal, if: server.changed, tool: mcp.server.tool)
        try SettingsFile.write(&outcome, hooksURL, merged.data, original: hooksOriginal, if: merged.changed, tool: hooks.tool)
        return outcome
    }
}
