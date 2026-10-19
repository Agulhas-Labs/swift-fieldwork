// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The MCP server half of the Claude Code install: registers the binary as the user-scope server through `claude mcp`, deciding what is there by reading `.claude.json` with the tool's own recognition, never by parsing `claude mcp get`.
///
/// A server of that name that runs something else is left alone and named; one of this tool's at another path is removed and registered again; without a `claude` to run, the answer is the command to paste.
public struct ClaudeMcpInstall: Equatable, Sendable {
    /// The server this install registers.
    public let server: ClaudeMcpServer

    public init(server: ClaudeMcpServer) {
        self.server = server
    }

    /// Reads what the user-scope server in `config` is, for `binary`; writes nothing and runs nothing.
    public func plan(config: URL, binary: String) -> Plan {
        if let reason = Self.unreadable(config) {
            return .unreadable(reason)
        }
        guard let entry = server.userEntry(in: config) else { return .absent }
        guard entry.ours else { return .foreign(entry.command) }
        return entry.command == server.registered(binary: binary) ? .current : .stale(entry.command)
    }

    /// Registers `binary` in `config` through `runner`, unless it is already there or a foreign server holds the name, and reads the config back to confirm it.
    public func install(config: URL, binary: String, runner: any ClaudeMcpRunner) throws -> InstallOutcome {
        var outcome = InstallOutcome()
        let manual = server.manual(binary: binary)
        let registered = server.registered(binary: binary)
        let name = server.name
        switch plan(config: config, binary: binary) {
        case let .unreadable(reason):
            outcome.failures.append("mcp: not registered — \(config.path) \(reason); repair it, then run: \(manual)")
            return outcome
        case .current:
            outcome.lines.append("mcp: already registered — \(registered)")
            return outcome
        case let .foreign(existing):
            outcome.lines.append("mcp: left alone — a server named \(name) runs something else (\(existing))")
            return outcome
        case let .stale(previous):
            guard let removed = try remove(runner: runner) else {
                outcome.lines.append("mcp: `claude` is not on PATH — replace the stale registration (\(previous)) with: \(server.removalCommand); \(manual)")
                return outcome
            }
            guard removed.succeeded else {
                outcome.failures.append("mcp: not replaced — `\(server.removalCommand)` failed: \(removed.failureReason); run it, then: \(manual)")
                return outcome
            }
            outcome.lines.append("mcp: replaced stale registration (\(previous))")
        case .absent:
            if server.removal == .userScopeAndUnscoped {
                // A registration with no scope is not in the user-scope entry the plan read, and would shadow the new one.
                _ = try remove(runner: runner)
            }
        }
        guard let added = try runner.run(server.addArguments(binary: binary)) else {
            outcome.lines.append("mcp: `claude` is not on PATH — register the server with: \(manual)")
            return outcome
        }
        guard added.succeeded else {
            outcome.failures.append("mcp: not registered — `claude mcp add` failed: \(added.failureReason); run: \(manual)")
            return outcome
        }
        guard plan(config: config, binary: binary) == .current else {
            outcome.failures.append("mcp: not registered — `claude mcp add` succeeded but \(config.path) does not name \(registered); run: \(manual)")
            return outcome
        }
        outcome.lines.append("mcp: registered \(name) — \(registered)")
        outcome.written.append(config.path)
        return outcome
    }

    /// Takes the server's registration out through `runner`: every removal the server lists runs, in order, whatever the one before did, and the removal succeeded if any did.
    ///
    /// The answer is the first success, else the last failure; `nil` when there is no `claude`.
    private func remove(runner: any ClaudeMcpRunner) throws -> Subprocess.Output? {
        var succeeded: Subprocess.Output?
        var last: Subprocess.Output?
        for arguments in server.removalArguments {
            guard let output = try runner.run(arguments) else { return nil }
            last = output
            if output.succeeded, succeeded == nil {
                succeeded = output
            }
        }
        return succeeded ?? last
    }

    /// Removes the server named by this install, by name and without reading the config, through `runner`: reports what happened and never throws for a `claude` failure.
    ///
    /// Every removal the server lists runs; the line says it was removed when any did, and a failure is reported only when all failed.
    public func uninstall(runner: any ClaudeMcpRunner) -> InstallOutcome {
        var outcome = InstallOutcome()
        let command = server.removalCommand
        let removed: Subprocess.Output?
        do {
            removed = try remove(runner: runner)
        } catch {
            outcome.failures.append("mcp: not removed — `\(command)` could not run: \(error.localizedDescription)")
            return outcome
        }
        guard let removed else {
            outcome.lines.append("mcp: `claude` is not on PATH — remove the registration with: \(command)")
            return outcome
        }
        if removed.succeeded {
            outcome.lines.append("mcp: removed \(server.name)")
        } else {
            outcome.failures.append("mcp: not removed — `\(command)` failed: \(removed.failureReason)")
        }
        return outcome
    }

    /// Why `config` is there and cannot be read as the JSON object Claude Code keeps, or `nil` where it can or is not there at all: read as absent, it would send `claude mcp add` at a file nothing checked.
    ///
    /// A file holding nothing but whitespace holds nothing to lose, so it reads as absent; everything else that is not a JSON object is refused.
    private static func unreadable(_ config: URL) -> String? {
        guard PathKind.of(config) != .absent else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: config)
        } catch {
            return "could not be read: \(error.localizedDescription)"
        }
        guard !data.allSatisfy([0x20, 0x09, 0x0A, 0x0D].contains) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any] ? nil : "could not be read as a JSON object"
    }
}

public extension ClaudeMcpInstall {
    /// What the user-scope server is, as the config holds it.
    enum Plan: Equatable, Sendable {
        /// Nothing is registered under the name.
        case absent
        /// This tool's server, running this binary.
        case current
        /// This tool's server running another binary, spelled as the config holds it.
        case stale(String)
        /// Something else, spelled as the config holds it.
        case foreign(String)
        /// A config that is there and cannot be read as a JSON object, with why: nothing about the server is known, so nothing is run.
        case unreadable(String)
    }
}
