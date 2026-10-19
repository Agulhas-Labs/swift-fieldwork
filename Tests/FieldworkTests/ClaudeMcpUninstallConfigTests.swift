// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Uninstalling reads Claude Code's config first: a server registered nowhere answers "nothing registered" and runs no `claude`.
struct ClaudeMcpUninstallConfigTests {
    private static let both = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo"), removal: .userScopeAndUnscoped))
    private static let single = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")))
    private static let nothing = ["mcp: nothing registered"]

    private static func write(_ object: Any, in directory: TemporaryDirectory) throws -> URL {
        let config = directory.url.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: object).write(to: config)
        return config
    }

    private static func localOnly(in directory: TemporaryDirectory) throws -> URL {
        let server = ["type": "stdio", "command": "/opt/tools/bin/gizmo", "args": ["mcp"]] as [String: Any]
        return try write(["mcpServers": [String: Any](), "projects": ["/work/app": ["mcpServers": ["gizmo": server]]]], in: directory)
    }

    @Test
    func nothingRegisteredAtUserScopeRunsNoRemoval() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.write(["mcpServers": [String: Any]()], in: directory)
        let claude = FakeClaude(config: config)

        let outcome = Self.single.uninstall(config: config, runner: claude)

        #expect(outcome.lines == Self.nothing)
        #expect(outcome.failures.isEmpty)
        #expect(claude.calls.isEmpty)
    }

    @Test
    func nothingRegisteredAnswersTheSameWithNoClaude() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.write(["mcpServers": [String: Any]()], in: directory)
        let claude = FakeClaude(config: config, present: false)

        let outcome = Self.single.uninstall(config: config, runner: claude)

        #expect(outcome.lines == Self.nothing)
        #expect(outcome.failures.isEmpty)
        #expect(claude.calls.isEmpty)
    }

    @Test
    func noConfigFileMeansNothingRegistered() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = directory.url.appendingPathComponent(".claude.json")
        let claude = FakeClaude(config: config)

        let outcome = Self.both.uninstall(config: config, runner: claude)

        #expect(outcome.lines == Self.nothing)
        #expect(outcome.failures.isEmpty)
        #expect(claude.calls.isEmpty)
    }

    @Test
    func aLocalScopeEntryRunsBothRemovalsWhereTheServerRemovesUnscoped() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.localOnly(in: directory)
        let claude = FakeClaude(config: config)

        let outcome = Self.both.uninstall(config: config, runner: claude)

        #expect(claude.calls == [["mcp", "remove", "gizmo", "--scope", "user"], ["mcp", "remove", "gizmo"]])
        #expect(outcome.lines == ["mcp: removed gizmo"])
        #expect(outcome.failures.isEmpty)
    }

    @Test
    func aLocalScopeEntryIsNothingToTheUserScopeOnlyServer() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.localOnly(in: directory)
        let claude = FakeClaude(config: config)

        let outcome = Self.single.uninstall(config: config, runner: claude)

        #expect(outcome.lines == Self.nothing)
        #expect(outcome.failures.isEmpty)
        #expect(claude.calls.isEmpty)
    }

    @Test
    func anUnreadableConfigIsAFailureThatRunsNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.write([1, 2], in: directory)
        let claude = FakeClaude(config: config)

        let outcome = Self.both.uninstall(config: config, runner: claude)

        #expect(outcome.failures.count == 1)
        let failure = outcome.failures.first ?? ""
        #expect(failure.hasPrefix("mcp: not checked — "))
        #expect(failure.contains(config.path))
        #expect(failure.contains("claude mcp remove gizmo --scope user; claude mcp remove gizmo"))
        #expect(outcome.lines.isEmpty)
        #expect(claude.calls.isEmpty)
    }
}
