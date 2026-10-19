// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The Cursor half of a tool's `doctor`: reads the registration from the `mcp.json` and `hooks.json` the tool's install writes in the Cursor directory, then runs what Cursor would run.
///
/// The tool's identity arrives as values: its Cursor install and the tools its server must list.
public struct DoctorCursor {
    /// The Cursor directory the install writes to.
    public let directory: URL
    public let probe: DoctorProbe
    /// The Cursor install the tool makes.
    public let install: CursorInstall
    /// The tools the server must list.
    public let expectedTools: [String]

    public init(directory: URL, probe: DoctorProbe, install: CursorInstall, expectedTools: [String]) {
        self.directory = directory
        self.probe = probe
        self.install = install
        self.expectedTools = expectedTools
    }

    private var agent: Agent {
        .cursor
    }

    private var installRemedy: String {
        "`\(install.hooks.tool.installCommand) --agent cursor`"
    }

    /// Whether nothing of the tool's is in Cursor: no hook registered and no server named as the tool's or that is the tool's, read the way ``checks()`` reads them; a file that cannot be read or parsed is not nothing.
    public var hasNothingInstalled: Bool {
        let data: Data?
        do {
            data = try read(directory.appendingPathComponent(CursorHooksFile.fileName))
        } catch {
            return false
        }
        return DoctorTraces.hooksHoldNothing(data, tool: install.hooks.tool)
            && DoctorTraces.serversHoldNothing(in: directory.appendingPathComponent(CursorMcpFile.fileName), mcp: install.mcp)
    }

    /// Every check, in the order the answer lists them.
    public func checks() -> [DoctorCheck] {
        let hooksFile = directory.appendingPathComponent(CursorHooksFile.fileName)
        let hooks: [(event: String, command: String)]
        var checks: [DoctorCheck] = []
        do {
            hooks = try registeredHooks(in: read(hooksFile))
            let missing = install.hooks.hooks.map(\.event).filter { name in !hooks.contains { $0.event == name } }
            checks.append(hooksCheck(missing: missing, found: hooks.map(\.event), file: hooksFile))
        } catch {
            hooks = []
            checks.append(.fail(agent, "hooks", String(describing: error)))
        }
        let config = directory.appendingPathComponent(CursorMcpFile.fileName)
        let name = install.mcp.server.name
        guard let server = registeredServer(in: config) else {
            return checks + [.fail(agent, "server", "no MCP server named \(name) of this tool's in \(config.path); run \(installRemedy)")]
        }
        let run = DoctorRun(agent: agent, probe: probe, expectedTools: expectedTools)
        checks.append(.pass(agent, "server", "\(name) — \(server.command) \(server.arguments.joined(separator: " "))"))
        checks += run.binaryChecks(server.command)
        for hook in hooks {
            checks.append(run.hook(hook.event, command: hook.command, payload: payload(for: hook.event), jsonOnly: true))
        }
        checks.append(run.server(([server.command] + server.arguments).map(ShellWord.quoted).joined(separator: " ")))
        return checks
    }

    private func read(_ url: URL) throws -> Data? {
        try SettingsFile.read(url, agent: "cursor", flag: install.directoryFlag)
    }

    private func hooksCheck(missing: [String], found: [String], file: URL) -> DoctorCheck {
        guard missing.isEmpty else {
            return .fail(agent, "hooks", "not registered for \(missing.joined(separator: ", ")) in \(file.path); run \(installRemedy)")
        }
        return .pass(agent, "hooks", "registered for \(found.joined(separator: ", "))")
    }

    /// The first command of this tool's registered for each of its events, in the order ``CursorHooksFile/hooks`` lists them.
    func registeredHooks(in data: Data?) -> [(event: String, command: String)] {
        let file = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let events = file?["hooks"] as? [String: Any] ?? [:]
        let tool = install.hooks.tool
        return install.hooks.hooks.compactMap { hook in
            let entries = events[hook.event] as? [[String: Any]] ?? []
            let commands = entries.compactMap { $0["command"] as? String }
            let subcommand = install.hooks.registeredSubcommand(for: hook)
            return commands.first { tool.runs($0, subcommand: subcommand) }.map { (hook.event, $0) }
        }
    }

    /// The server named as the install names it in `config`, where it is the tool's.
    func registeredServer(in config: URL) -> (command: String, arguments: [String])? {
        let object = (try? Data(contentsOf: config)).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        let entry = (object?["mcpServers"] as? [String: Any])?[install.mcp.server.name]
        guard install.mcp.isOurs(entry), let entry = entry as? [String: Any], let command = entry["command"] as? String else { return nil }
        return (command, entry["args"] as? [String] ?? [])
    }

    /// The payload Cursor hands the hook for `event`, in the shape a live Cursor sends: a call the hook lets through without a word, with the probe's workspace as the one workspace root.
    public func payload(for event: String) -> [String: Any] {
        let name = "\(install.hooks.tool.name)-doctor"
        let workspace = probe.workspace
        var payload: [String: Any] = [
            "conversation_id": name,
            "generation_id": name,
            "cursor_version": name,
            "workspace_roots": [workspace.path],
            "transcript_path": NSNull(),
            "hook_event_name": event,
        ]
        switch event {
        case "sessionStart":
            payload["session_id"] = name
            payload["is_background_agent"] = false
            payload["composer_mode"] = "agent"
        case "preToolUse":
            payload["tool_name"] = "Shell"
            payload["tool_input"] = ["command": "true"]
            payload["tool_use_id"] = name
            payload["cwd"] = workspace.path
        case "postToolUseFailure":
            payload["tool_name"] = "Shell"
            payload["tool_input"] = ["command": "true"]
            payload["tool_use_id"] = name
            payload["cwd"] = workspace.path
            payload["error_message"] = ""
            payload["failure_type"] = "error"
            payload["is_interrupt"] = false
        default:
            payload["tool_name"] = "Write"
            payload["tool_input"] = ["file_path": workspace.appendingPathComponent("notes.txt").path, "content": "notes\n"]
            payload["tool_output"] = "{\"success\":true}"
            payload["tool_use_id"] = name
            payload["cwd"] = workspace.path
        }
        return payload
    }
}
