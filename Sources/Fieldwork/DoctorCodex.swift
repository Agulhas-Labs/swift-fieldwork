// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Codex half of a tool's `doctor`: the hooks in the Codex home's `hooks.json`, their trust in its `config.toml`, and the server `codex mcp get` shows, then what Codex would run, fed Claude Code's payloads, which Codex speaks.
///
/// The home is resolved as the install resolves it (``AgentPaths/codexHome(flag:environment:)``). Without a `codex` to ask, the server is unknown and the binary, version and server run are not checked; the hooks still run, since each carries its own command. The tool's identity arrives as values: its Codex hooks, its server and the tools the server must list.
public struct DoctorCodex {
    public let home: AgentPaths.CodexHome
    public let runner: any CodexMcpRunner
    public let probe: DoctorProbe
    /// The hooks the install registers in Codex.
    public let hooks: HookRegistration
    /// The MCP server the install registers in Codex.
    public let server: CodexMcpServer
    /// The tools the server must list.
    public let expectedTools: [String]

    public init(home: AgentPaths.CodexHome, runner: any CodexMcpRunner, probe: DoctorProbe, hooks: HookRegistration, server: CodexMcpServer, expectedTools: [String]) {
        self.home = home
        self.runner = runner
        self.probe = probe
        self.hooks = hooks
        self.server = server
        self.expectedTools = expectedTools
    }

    private var agent: Agent {
        .codex
    }

    /// Whether nothing of the tool's is in Codex: a Codex home that does not exist, or no hook registered and `codex` itself finds no server of the tool's name, read the way ``checks()`` reads them; a file or an answer that cannot be had is not nothing.
    ///
    /// A missing home is nothing without asking `codex`, which can only fail there.
    public var hasNothingInstalled: Bool {
        guard FileManager.default.fileExists(atPath: home.directory.path) else {
            return true
        }
        let data: Data?
        do {
            data = try SettingsFile.read(home.directory.appendingPathComponent(AgentPaths.codexHooksFileName), agent: "codex", flag: "--codex-dir")
        } catch {
            return false
        }
        guard DoctorTraces.hooksHoldNothing(data, tool: hooks.tool, subcommands: hooks.events.map(\.subcommand)), case .absent? = try? server.find(runner: runner, home: home.directory) else { return false }
        return true
    }

    /// Every check, in the order the answer lists them.
    public func checks() -> [DoctorCheck] {
        let file = home.directory.appendingPathComponent(AgentPaths.codexHooksFileName)
        let registered: [Registered]
        var checks: [DoctorCheck] = []
        do {
            registered = try registeredHooks(in: SettingsFile.read(file, agent: "codex", flag: "--codex-dir"))
            let missing = hooks.events.map(\.name).filter { event in !registered.contains { $0.event == event } }
            checks.append(hooksCheck(missing: missing, found: registered.map(\.event), file: file))
        } catch {
            registered = []
            checks.append(.fail(agent, "hooks", DoctorTraces.describe(error)))
        }
        if !registered.isEmpty {
            checks.append(DoctorCodexTrust.check(config: home.directory.appendingPathComponent(AgentPaths.codexConfigFileName), hooks: file, positions: registered.map(\.position), tool: server.server.name))
        }
        let found = registeredServer()
        checks.append(found.check)
        let run = DoctorRun(agent: agent, probe: probe, expectedTools: expectedTools)
        if let binary = found.binary {
            checks += run.binaryChecks(binary)
        }
        let payloads = DoctorClaude(environment: [:], probe: probe, hooks: hooks, server: server.server, expectedTools: expectedTools)
        for hook in registered {
            checks.append(run.hook(hook.event, command: hook.command, payload: payloads.payload(for: hook.event), jsonOnly: hook.event != "SessionStart"))
        }
        if let binary = found.binary {
            checks.append(run.server(([binary] + server.server.arguments).map(ShellWord.quoted).joined(separator: " ")))
        }
        return checks
    }

    /// The first handler of the tool's registered for each of its events, where it sits, in the order ``hooks`` lists them.
    func registeredHooks(in data: Data?) -> [Registered] {
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let events = file?["hooks"] as? [String: Any] ?? [:]
        return hooks.events.compactMap { event in
            for (group, entry) in (events[event.name] as? [Any] ?? []).enumerated() {
                let handlers = (entry as? [String: Any])?["hooks"] as? [Any] ?? []
                for (index, handler) in handlers.enumerated() {
                    guard let command = (handler as? [String: Any])?["command"] as? String, hooks.isOurs(command, subcommand: event.subcommand) else { continue }
                    return Registered(event: event.name, command: command, position: DoctorCodexTrust.Position(event: DoctorCodexTrust.snakeCase(event.name), group: group, handler: index))
                }
            }
            return nil
        }
    }

    /// The command that registers what is missing, naming the home when it came from `--codex-dir`, where the plain install would not look.
    private var installHint: String {
        let install = hooks.tool.installCommand
        guard home.source == "--codex-dir" else { return "run `\(install) --agent codex`" }
        return "run `\(install) --agent codex --codex-dir \(ShellWord.quoted(home.directory.path))`"
    }

    private func hooksCheck(missing: [String], found: [String], file: URL) -> DoctorCheck {
        guard missing.isEmpty else {
            return .fail(agent, "hooks", "not registered for \(missing.joined(separator: ", ")) in \(file.path) (Codex home from \(home.source)); \(installHint)")
        }
        return .pass(agent, "hooks", "registered for \(found.joined(separator: ", ")) in \(file.path) (Codex home from \(home.source))")
    }

    /// The server check, and the binary it runs where it is this tool's.
    private func registeredServer() -> (check: DoctorCheck, binary: String?) {
        let asked = "`codex \(server.getArguments.joined(separator: " "))`"
        let name = server.server.name
        let found: CodexMcpServer.Found
        do {
            found = try server.find(runner: runner, home: home.directory)
        } catch {
            return (.unknown(agent, "server", "\(asked) did not answer: \(DoctorTraces.describe(error)); binary, version and mcp server not checked"), nil)
        }
        return switch found {
        case let .ours(binary):
            (.pass(agent, "server", "\(name) — \(binary) \(server.server.arguments.joined(separator: " "))"), binary)
        case .absent:
            (.fail(agent, "server", "no MCP server named \(name) in \(home.directory.path); \(installHint)"), nil)
        case let .foreign(existing):
            (.fail(agent, "server", "the MCP server named \(name) in \(home.directory.path) runs something else (\(existing)); \(installHint)"), nil)
        case .noCodex:
            (.unknown(agent, "server", "`codex` is not on PATH to ask \(asked); binary, version and mcp server not checked"), nil)
        }
    }
}

extension DoctorCodex {
    /// One handler of the tool's in `hooks.json`: the event, the command it runs and where it sits.
    struct Registered {
        let event: String
        let command: String
        let position: DoctorCodexTrust.Position
    }
}
