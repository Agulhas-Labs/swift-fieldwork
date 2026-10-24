// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A tool's install and uninstall for Codex: the hooks in the Codex home's `hooks.json`, merged with the guarantees `settings.json` gets, and the MCP server, registered through `codex mcp` (``CodexMcpServer``).
///
/// The hooks file is read and merged, and the server looked up, before anything is written, so a refusal of either leaves both as they were. Codex runs a hook only once the user has trusted it, and nothing here trusts one on their behalf.
public struct CodexInstall: Equatable, Sendable {
    /// The hooks this registers in `hooks.json`.
    public let hooks: CodexHooksFile
    /// The server this registers through `codex mcp`.
    public let server: CodexMcpServer

    public init(hooks: CodexHooksFile, server: CodexMcpServer) {
        self.hooks = hooks
        self.server = server
    }

    /// The option that points the install at another Codex home, which a refusal names and a manual command spells as `CODEX_HOME`.
    public static var directoryFlag: String {
        "--codex-dir"
    }

    private static var agent: String {
        "codex"
    }

    /// Registers the hooks and the server in `home` for `binary`, an absolute path, the same path shell-quoted as the first word of each hook's command.
    public func install(home: AgentPaths.CodexHome, binary: String, binaryWord: String, runner: any CodexMcpRunner) throws -> InstallOutcome {
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: Self.agent, flag: Self.directoryFlag)
        let merged = try SettingsFile.merge(hooksURL, agent: Self.agent) { try hooks.apply(to: original, binaryWord: binaryWord) }
        // Codex refuses a CODEX_HOME that is not there, so the directory is made before it is asked anything.
        do {
            try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        } catch {
            throw SettingsFile.Refused(path: home.directory.path, reason: "could not be made: \(error.localizedDescription)", agent: Self.agent)
        }
        let found = try server.find(runner: runner, home: home.directory)

        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        let wanted = hooks.hooks
        if merged.changed {
            outcome.lines += merged.replaced.map { "hooks: replaced stale registration (\($0))" }
            outcome.lines += CodexHooksFile.movedEvents(from: original, to: merged.data).map { "hooks: \($0) groups after ours moved up; Codex will ask to trust them again" }
            outcome.lines += wanted.map { "hooks: registered \($0.event) — \(hooks.command(for: $0, binaryWord: binaryWord))" }
        } else {
            outcome.lines.append("hooks: already registered — \(wanted.map(\.event).joined(separator: ", "))")
        }
        try SettingsFile.write(&outcome, hooksURL, merged.data, original: original, if: merged.changed, tool: hooks.tool)
        try register(binary, found: found, home: home, runner: runner, into: &outcome)
        return outcome
    }

    /// Takes out what the install wrote, and nothing else: a foreign server of the name and every foreign hook stay, and a Codex home that is not there is not looked into.
    public func uninstall(home: AgentPaths.CodexHome, runner: any CodexMcpRunner) throws -> InstallOutcome {
        var outcome = InstallOutcome(lines: [], notes: [], written: [])
        guard PathKind.of(home.directory) != .absent else { return outcome }
        let hooksURL = home.directory.appendingPathComponent(CodexHooksFile.fileName)
        let original = try SettingsFile.read(hooksURL, agent: Self.agent, flag: Self.directoryFlag)
        let merged = try SettingsFile.merge(hooksURL, agent: Self.agent) { try hooks.remove(from: original) }
        let found = try server.find(runner: runner, home: home.directory)

        outcome.lines += merged.removed.map { "hooks: removed \($0)" }
        try SettingsFile.write(&outcome, hooksURL, merged.data, original: original, if: merged.changed, tool: hooks.tool)
        try removeServer(found: found, home: home, runner: runner, hooksRemoved: merged.changed, into: &outcome)
        return outcome
    }

    /// The uninstall's server step: takes out ours and notes a foreign one of the name, which stays; without `codex` to ask it notes the command to run when `hooksRemoved` says the tool was installed here.
    public func removeServer(found: CodexMcpServer.Found, home: AgentPaths.CodexHome, runner: any CodexMcpRunner, hooksRemoved: Bool, into outcome: inout InstallOutcome) throws {
        switch found {
        case let .ours(command):
            let removal = try runner.run(server.removeArguments, home: home.directory)
            if let removal, removal.succeeded {
                outcome.lines.append("mcp: removed \(server.server.name) — \(command) \(server.server.arguments.joined(separator: " "))")
            } else {
                let reason = removal.map(\.failureReason) ?? "`codex` is no longer on PATH"
                outcome.failures.append("mcp: not removed — `codex \(server.removeArguments.joined(separator: " "))` failed: \(reason); run: \(Self.manual(server.removeArguments, home: home))")
            }
        case let .foreign(existing):
            outcome.notes.append("mcp: not ours, left alone — a server named \(server.server.name) in \(home.directory.path) runs something else (\(existing))")
        case .noCodex where hooksRemoved:
            // The hooks say this tool was installed here, so the server most likely was too; without `codex` there is no asking.
            outcome.notes.append("mcp: not checked — `codex` is not on PATH; if Codex runs this tool's server, run: \(Self.manual(server.removeArguments, home: home))")
        case .absent, .noCodex:
            break
        }
    }

    /// Registers the server unless a foreign one holds the name or ours is already there, and says which.
    public func register(_ binary: String, found: CodexMcpServer.Found, home: AgentPaths.CodexHome, runner: any CodexMcpRunner, into outcome: inout InstallOutcome) throws {
        let name = server.server.name
        let registered = "\(binary) \(server.server.arguments.joined(separator: " "))"
        let arguments = server.addArguments(binary: binary)
        if case let .foreign(existing) = found {
            return outcome.lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
        }
        switch found {
        case .ours(binary):
            return outcome.lines.append("mcp: already registered — \(registered)")
        case let .ours(previous):
            outcome.lines.append("mcp: replaced stale registration (\(previous) \(server.server.arguments.joined(separator: " ")))")
        case .noCodex:
            return outcome.lines.append("mcp: `codex` is not on PATH — register the server with: \(Self.manual(arguments, home: home))")
        case .absent, .foreign:
            break
        }
        let added = try runner.run(arguments, home: home.directory)
        guard let added, added.succeeded else {
            let reason = added.map(\.failureReason) ?? "`codex` is no longer on PATH"
            return outcome.failures.append("mcp: not registered — `codex \(arguments.prefix(3).joined(separator: " "))` failed: \(reason); run: \(Self.manual(arguments, home: home))")
        }
        outcome.lines.append("mcp: registered \(name) — \(registered)")
    }

    /// Takes the server out: ours is removed, and a foreign one of the name is left, saying so.
    ///
    /// Without `codex` to ask, `noteWithoutCodex` adds the command to run as a note.
    public func unregister(found: CodexMcpServer.Found, home: AgentPaths.CodexHome, runner: any CodexMcpRunner, noteWithoutCodex: Bool, into outcome: inout InstallOutcome) throws {
        let name = server.server.name
        let remove = server.removeArguments
        switch found {
        case let .ours(command):
            let removal = try runner.run(remove, home: home.directory)
            if let removal, removal.succeeded {
                outcome.lines.append("mcp: removed \(name) — \(command) \(server.server.arguments.joined(separator: " "))")
            } else {
                let reason = removal.map(\.failureReason) ?? "`codex` is no longer on PATH"
                outcome.failures.append("mcp: not removed — `codex \(remove.joined(separator: " "))` failed: \(reason); run: \(Self.manual(remove, home: home))")
            }
        case let .foreign(existing):
            outcome.lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
        case .noCodex where noteWithoutCodex:
            outcome.notes.append("mcp: not checked — `codex` is not on PATH; if Codex runs this tool's server, run: \(Self.manual(remove, home: home))")
        case .absent, .noCodex:
            break
        }
    }

    /// `codex` with `arguments` as a person pastes it, naming the home in `CODEX_HOME` when it came from `--codex-dir`, where a plain `codex` would not look.
    public static func manual(_ arguments: [String], home: AgentPaths.CodexHome) -> String {
        let command = (["codex"] + arguments.map(ShellWord.quoted)).joined(separator: " ")
        guard home.source == directoryFlag else { return command }
        return "CODEX_HOME=\(ShellWord.quoted(home.directory.path)) \(command)"
    }
}
