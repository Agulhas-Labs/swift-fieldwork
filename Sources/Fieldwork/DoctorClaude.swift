// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Claude Code half of a tool's `doctor`: reads the registration from the files the tool's install writes, resolved from the same environment, then runs what Claude Code would run.
///
/// The tool's identity arrives as values: its hooks, its MCP server, its rule and the tools the server must list.
public struct DoctorClaude {
    public let environment: [String: String]
    public let probe: DoctorProbe
    /// The hooks the install registers.
    public let hooks: HookRegistration
    /// The MCP server the install registers.
    public let server: ClaudeMcpServer
    /// The tools the server must list.
    public let expectedTools: [String]
    /// The rule the install copies, or `nil` where the tool ships none.
    public var rule: ClaudeRuleInstall?
    /// Where `claude` is not on PATH, the command that registers the running binary's server by hand, which the install cannot run; `nil` where it is.
    public var manualRegistration: String?

    public init(
        environment: [String: String],
        probe: DoctorProbe,
        hooks: HookRegistration,
        server: ClaudeMcpServer,
        expectedTools: [String],
        rule: ClaudeRuleInstall? = nil,
        manualRegistration: String? = nil
    ) {
        self.environment = environment
        self.probe = probe
        self.hooks = hooks
        self.server = server
        self.expectedTools = expectedTools
        self.rule = rule
        self.manualRegistration = manualRegistration
    }

    private var agent: Agent {
        .claude
    }

    private var install: String {
        "`\(hooks.tool.name) install --agent claude`"
    }

    /// Every check, in the order the answer lists them.
    public func checks() -> [DoctorCheck] {
        let settings = AgentPaths.claudeSettings(environment: environment)
        let registered: [(event: String, command: String)]
        var checks: [DoctorCheck] = []
        do {
            let data = try Self.read(settings)
            registered = registeredHooks(in: data)
            let missing = hooks.events.map(\.name).filter { name in !registered.contains { $0.event == name } }
            checks.append(hooksCheck(missing: missing, found: registered.map(\.event), data: data, settings: settings))
        } catch {
            registered = []
            checks.append(.fail(agent, "hooks", String(describing: error)))
        }
        let config = AgentPaths.claudeConfig(environment: environment)
        guard let found = registeredServer(in: config) else {
            let remedy = manualRegistration.map { "claude is not on PATH, so \(install) cannot register the server: run `\($0)` where claude is" } ?? "run \(install)"
            return checks + [.fail(agent, "server", "no MCP server named \(server.name) of this tool's in \(config.path); \(remedy)")]
        }
        checks.append(.pass(agent, "server", "\(server.name) — \(found.command) \(found.arguments.joined(separator: " "))"))
        let run = DoctorRun(agent: agent, probe: probe, expectedTools: expectedTools)
        checks += run.binaryChecks(found.command)
        for hook in registered {
            checks.append(run.hook(hook.event, command: hook.command, payload: payload(for: hook.event), jsonOnly: hook.event != "SessionStart" && hook.event != "SubagentStart"))
        }
        checks.append(run.server(([found.command] + found.arguments).map(ShellWord.quoted).joined(separator: " ")))
        if let rule {
            checks.append(ruleCheck(rule))
        }
        return checks
    }

    /// The settings file's bytes, `nil` where there is none; an unreadable file throws.
    private static func read(_ settings: URL) throws -> Data? {
        guard PathKind.of(settings) != .absent else { return nil }
        let target = try SettingsFile.target(of: settings)
        do {
            return try Data(contentsOf: target)
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            throw Unreadable(path: settings.path, reason: error.localizedDescription)
        }
    }

    /// Passes only where the registration is also the one the tool writes, so an upgrade that changed a matcher does not read as healthy.
    private func hooksCheck(missing: [String], found: [String], data: Data?, settings: URL) -> DoctorCheck {
        guard missing.isEmpty else {
            return .fail(agent, "hooks", "not registered for \(missing.joined(separator: ", ")) in \(settings.path); run \(install)")
        }
        guard hooks.fingerprint(of: data) == hooks.fingerprint else {
            return .fail(agent, "hooks", "registered for \(found.joined(separator: ", ")) in \(settings.path), but not as this version registers them; run \(install)")
        }
        return .pass(agent, "hooks", "registered for \(found.joined(separator: ", "))")
    }

    /// The first command of this tool's registered for each of its events, in the order ``HookRegistration/events`` lists them.
    func registeredHooks(in data: Data?) -> [(event: String, command: String)] {
        let settings = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let registered = settings?["hooks"] as? [String: Any] ?? [:]
        return hooks.events.compactMap { event in
            let entries = registered[event.name] as? [[String: Any]] ?? []
            let commands = entries.flatMap { $0["hooks"] as? [[String: Any]] ?? [] }.compactMap { $0["command"] as? String }
            return commands.first { hooks.isOurs($0, subcommand: event.subcommand) }.map { (event.name, $0) }
        }
    }

    /// The user-scope server named as the install names it in `config`, where it runs this tool's binary with the server's arguments.
    ///
    /// An `npx` registration is the install's too, but not one this check passes: its command is not the binary the later checks run, and running it can fetch the package.
    func registeredServer(in config: URL) -> (command: String, arguments: [String])? {
        let object = (try? Data(contentsOf: config)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        guard let entry = (object?["mcpServers"] as? [String: Any])?[server.name] as? [String: Any],
              let command = entry["command"] as? String
        else { return nil }
        let arguments = entry["args"] as? [String] ?? []
        guard URL(fileURLWithPath: command).lastPathComponent == server.tool.name, arguments == server.arguments else { return nil }
        return (command, arguments)
    }

    private func ruleCheck(_ rule: ClaudeRuleInstall) -> DoctorCheck {
        let path = AgentPaths.claudeRule(named: rule.tool.installedRuleName, environment: environment)
        return switch PathKind.of(path) {
        case .file, .symlink:
            .pass(agent, "rule", "installed at \(path.path)")
        case .absent, .directory, .other:
            .fail(agent, "rule", "no rule at \(path.path); run \(install)")
        }
    }

    /// The payload Claude Code hands the hook for `event`: a call the hook lets through without a word, in the scratch workspace.
    public func payload(for event: String) -> [String: Any] {
        let name = "\(hooks.tool.name)-doctor"
        var payload: [String: Any] = ["session_id": name, "cwd": probe.workspace.path, "hook_event_name": event, "transcript_path": ""]
        switch event {
        case "SessionStart":
            payload["source"] = "startup"
        case "SubagentStart":
            payload["agent_id"] = "\(name)-agent"
            payload["agent_type"] = "general-purpose"
        case "PreToolUse":
            payload["permission_mode"] = "default"
            payload["tool_name"] = "Bash"
            payload["tool_input"] = ["command": "true"]
        case "PostToolUse":
            payload["tool_name"] = "Write"
            payload["tool_input"] = ["file_path": probe.workspace.appendingPathComponent("notes.txt").path, "content": "notes\n"]
            payload["tool_response"] = [String: Any]()
        default:
            payload["stop_hook_active"] = false
        }
        return payload
    }
}

extension DoctorClaude {
    /// A settings file that is there and cannot be read, as the hooks check's line says it.
    struct Unreadable: Error, CustomStringConvertible {
        let path: String
        let reason: String

        var description: String {
            "claude: nothing written — \(path) could not be read: \(reason)"
        }
    }
}
