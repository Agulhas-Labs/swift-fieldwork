// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The Claude Code MCP registration a tool's install makes: decided from `.claude.json`, made through `claude mcp` with exact arguments, and never over a foreign server.
struct ClaudeMcpInstallTests {
    private static let binary = "/opt/tools/bin/gizmo"
    private static let install = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")))

    private static func config(in directory: TemporaryDirectory, holding gizmo: [String: Any]?) throws -> URL {
        let config = directory.url.appendingPathComponent(".claude.json")
        var servers: [String: Any] = ["other": ["type": "stdio", "command": "/bin/other", "args": []]]
        servers["gizmo"] = gizmo
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers, "theme": "dark"]).write(to: config)
        return config
    }

    @Test
    func anAbsentServerIsAddedAtUserScopeWithExactArgumentsAndReadBack() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, holding: nil)
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls == [["mcp", "add", "--transport", "stdio", "--scope", "user", "gizmo", "--", Self.binary, "mcp"]])
        #expect(outcome.lines == ["mcp: registered gizmo — \(Self.binary) mcp"])
        #expect(outcome.written == [config.path])
        #expect(outcome.failures.isEmpty)
        #expect(Self.install.plan(config: config, binary: Self.binary) == .current)
    }

    @Test
    func aSecondRunRunsNothingAndSaysItIsThere() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, holding: ["type": "stdio", "command": Self.binary, "args": ["mcp"]])
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.isEmpty)
        #expect(outcome.lines == ["mcp: already registered — \(Self.binary) mcp"])
        #expect(!outcome.changed)
    }

    @Test
    func aForeignServerWithTheNameIsLeftAloneAndNamed() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, holding: ["type": "stdio", "command": "/opt/other/server", "args": ["serve"]])
        let before = try Data(contentsOf: config)
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.isEmpty)
        #expect(outcome.lines == ["mcp: left alone — a server named gizmo runs something else (/opt/other/server serve)"])
        #expect(outcome.failures.isEmpty)
        #expect(try Data(contentsOf: config) == before)
    }

    @Test
    func oursAtAnotherPathIsRemovedThenAdded() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, holding: ["type": "stdio", "command": "/old/bin/gizmo", "args": ["mcp"]])
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls == [
            ["mcp", "remove", "gizmo", "--scope", "user"],
            ["mcp", "add", "--transport", "stdio", "--scope", "user", "gizmo", "--", Self.binary, "mcp"],
        ])
        #expect(outcome.lines == ["mcp: replaced stale registration (/old/bin/gizmo mcp)", "mcp: registered gizmo — \(Self.binary) mcp"])
    }

    @Test
    func withoutClaudeTheManualLineIsPrintedAndNothingFails() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, holding: nil)
        let claude = FakeClaude(config: config, present: false)

        let outcome = try Self.install.install(config: config, binary: "/opt/my tools/gizmo", runner: claude)

        #expect(outcome.lines == ["mcp: `claude` is not on PATH — register the server with: claude mcp add --transport stdio --scope user gizmo -- '/opt/my tools/gizmo' mcp"])
        #expect(outcome.failures.isEmpty)
        #expect(!outcome.changed)
    }

    @Test
    func aFailedAddOrOneTheConfigDoesNotShowIsAFailure() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let refused = try Self.config(in: directory, holding: nil)
        let failing = try Self.install.install(config: refused, binary: Self.binary, runner: FakeClaude(config: refused, addSucceeds: false))
        #expect(failing.failures.first?.hasPrefix("mcp: not registered — `claude mcp add` failed: add refused; run: claude mcp add") == true)

        let silent = try Self.config(in: directory, holding: nil)
        let unconfirmed = try Self.install.install(config: silent, binary: Self.binary, runner: FakeClaude(config: silent, addWrites: false))
        #expect(unconfirmed.failures.first?.hasPrefix("mcp: not registered — `claude mcp add` succeeded but \(silent.path) does not name") == true)
        #expect(unconfirmed.written.isEmpty)
    }

    @Test
    func theConfigAndTheRuleFollowClaudeConfigDir() {
        let moved = ["HOME": "/scratch/home", "CLAUDE_CONFIG_DIR": "/scratch/claude"]
        let rule = FieldworkTool(name: "gizmo").installedRuleName
        #expect(AgentPaths.claudeConfig(environment: moved).path == "/scratch/claude/.claude.json")
        #expect(AgentPaths.claudeRule(named: rule, environment: moved).path == "/scratch/claude/rules/gizmo.md")
        let plain = ["HOME": "/scratch/home"]
        #expect(AgentPaths.claudeConfig(environment: plain).path == "/scratch/home/.claude.json")
        #expect(AgentPaths.claudeRule(named: rule, environment: plain).path == "/scratch/home/.claude/rules/gizmo.md")
    }
}
