// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Taking a tool's server out through `claude mcp remove`: every removal the server lists runs, in order, and the removal worked if any did.
struct ClaudeMcpRemovalTests {
    private static var binary: String {
        "/opt/tools/bin/gizmo"
    }

    private static let user = ["mcp", "remove", "gizmo", "--scope", "user"]
    private static let unscoped = ["mcp", "remove", "gizmo"]
    private static let both = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo"), removal: .userScopeAndUnscoped))
    private static let single = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")))

    private static func config(in directory: TemporaryDirectory, command: String?) throws -> URL {
        let config = directory.url.appendingPathComponent(".claude.json")
        var servers: [String: Any] = [:]
        if let command {
            servers["gizmo"] = ["type": "stdio", "command": command, "args": ["mcp"]]
        }
        try JSONSerialization.data(withJSONObject: ["mcpServers": servers]).write(to: config)
        return config
    }

    @Test
    func bothRemovalsRunWhenTheFirstSucceeds() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: "/old/bin/gizmo")
        let claude = FakeClaude(config: config)

        let outcome = try Self.both.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.prefix(2) == [Self.user, Self.unscoped])
        #expect(claude.calls.count == 3)
        #expect(outcome.failures.isEmpty)
    }

    @Test
    func theSecondRemovalRunsWhenTheFirstFailsAndOneSuccessIsEnough() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: "/old/bin/gizmo")
        let claude = FakeClaude(config: config, removeResults: [false, true])

        let outcome = try Self.both.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.prefix(2) == [Self.user, Self.unscoped])
        #expect(outcome.failures.isEmpty)
        #expect(outcome.lines.first == "mcp: replaced stale registration (/old/bin/gizmo mcp)")
    }

    @Test
    func aFailureIsReportedOnlyWhenEveryRemovalFailed() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: "/old/bin/gizmo")
        let claude = FakeClaude(config: config, removeResults: [false, false])

        let outcome = try Self.both.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls == [Self.user, Self.unscoped])
        #expect(outcome.failures == ["mcp: not replaced — `claude mcp remove gizmo --scope user; claude mcp remove gizmo` failed: remove refused; run it, then: \(ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")).manual(binary: Self.binary))"])
        #expect(!outcome.changed)
    }

    @Test
    func theUnscopedRemovalRunsBeforeAddEvenWhenNothingIsRegisteredAtUserScope() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: nil)
        let claude = FakeClaude(config: config, removeResults: [false, false])

        let outcome = try Self.both.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.map { Array($0.prefix(2)) } == [["mcp", "remove"], ["mcp", "remove"], ["mcp", "add"]])
        #expect(outcome.failures.isEmpty)
        #expect(outcome.written == [config.path])
    }

    @Test
    func theSingleRemovalModeRunsNothingWhereNothingIsRegistered() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: nil)
        let claude = FakeClaude(config: config)

        _ = try Self.single.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.map { Array($0.prefix(2)) } == [["mcp", "add"]])
    }

    @Test
    func aStaleReplacementReportsNoFailureWhenTheUserScopeRemovalWorkedAndTheUnscopedOneFoundNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: "/old/bin/gizmo")
        let claude = FakeClaude(config: config, removeResults: [true, false])

        let outcome = try Self.both.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.prefix(2) == [Self.user, Self.unscoped])
        #expect(outcome.failures.isEmpty)
        #expect(outcome.lines.first == "mcp: replaced stale registration (/old/bin/gizmo mcp)")
    }

    @Test
    func uninstallReportsNoFailureWhenTheUserScopeRemovalWorkedAndTheUnscopedOneFoundNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: Self.binary)
        let claude = FakeClaude(config: config, removeResults: [true, false])

        let outcome = Self.both.uninstall(runner: claude)

        #expect(claude.calls == [Self.user, Self.unscoped])
        #expect(outcome.lines == ["mcp: removed gizmo"])
        #expect(outcome.failures.isEmpty)
    }

    @Test
    func uninstallRunsEveryRemovalAndSaysItRemovedWhenAnyDid() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: Self.binary)
        let claude = FakeClaude(config: config, removeResults: [false, true])

        let outcome = Self.both.uninstall(runner: claude)

        #expect(claude.calls == [Self.user, Self.unscoped])
        #expect(outcome.lines == ["mcp: removed gizmo"])
        #expect(outcome.failures.isEmpty)
    }

    @Test
    func uninstallReportsOneFailureWhenAllFailedAndTheCommandWhenThereIsNoClaude() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = try Self.config(in: directory, command: Self.binary)

        let failed = Self.both.uninstall(runner: FakeClaude(config: config, removeResults: [false, false]))
        #expect(failed.failures == ["mcp: not removed — `claude mcp remove gizmo --scope user; claude mcp remove gizmo` failed: remove refused"])
        #expect(failed.lines.isEmpty)

        let missing = Self.single.uninstall(runner: FakeClaude(config: config, present: false))
        #expect(missing.lines == ["mcp: `claude` is not on PATH — remove the registration with: claude mcp remove gizmo --scope user"])
        #expect(missing.failures.isEmpty)
    }
}
