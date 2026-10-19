// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Whether Claude Code's and Cursor's files hold nothing of a tool's, over a made-up tool, `gizmo`, beside another, `widget`.
struct DoctorNothingInstalledTests {
    private static let gizmo = CursorTools.gizmo
    private static let widget = CursorTools.widget

    // MARK: Claude Code

    @Test
    func claudeWithNoFilesHasNothing() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }

        #expect(try Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithTheToolsHookHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        let command = "/x/gizmo \(GizmoHooks.sessionStart.subcommand)"
        let data = try GizmoHooks.registration.apply(to: nil, command: command, event: GizmoHooks.sessionStart).data
        try Self.putSettings(data, in: Self.environment(home))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithTheToolsServerHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try Self.write(["mcpServers": ["gizmo": ["command": "/x/gizmo", "args": ["mcp"]]]], at: AgentPaths.claudeConfig(environment: Self.environment(home)))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithAServerOfTheToolsUnderAnotherNameHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try Self.write(["mcpServers": ["index": ["command": "/x/gizmo", "args": ["mcp"]]]], at: AgentPaths.claudeConfig(environment: Self.environment(home)))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithAServerNamedAsTheToolsThatIsNotOursHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try Self.write(["mcpServers": ["gizmo": ["command": "npx", "args": ["-y", "@example/gizmo", "mcp"]]]], at: AgentPaths.claudeConfig(environment: Self.environment(home)))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithOnlyAnotherToolsHooksAndServerHasNothing() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        let environment = Self.environment(home)
        let data = try GizmoHooks.registration.apply(to: nil, command: "/x/widget session-start", event: GizmoHooks.sessionStart).data
        try Self.putSettings(data, in: environment)
        try Self.write(["mcpServers": ["widget": ["command": "/x/widget", "args": ["serve"]]]], at: AgentPaths.claudeConfig(environment: environment))

        #expect(try Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithSettingsThatAreNotJSONHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try Self.putSettings(Data("{ not json".utf8), in: Self.environment(home))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithAnUnreadableSettingsFileHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        let settings = AgentPaths.claudeSettings(environment: Self.environment(home))
        try Self.dangle(settings)

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    @Test
    func claudeWithAnUnreadableServerFileHasSomething() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        try Self.dangle(AgentPaths.claudeConfig(environment: Self.environment(home)))

        #expect(try !Self.claude(home).hasNothingInstalled)
    }

    // MARK: Cursor

    @Test
    func cursorWithNoFilesHasNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        #expect(try Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithTheToolsHookHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.write(["version": 1, "hooks": ["sessionStart": [["command": "/x/gizmo session-start --agent cursor"]]]], at: directory.url.appendingPathComponent("hooks.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithTheToolsServerHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.write(["mcpServers": ["gizmo": ["command": "/x/gizmo", "args": ["mcp"]]]], at: directory.url.appendingPathComponent("mcp.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithAForeignHookMentioningTheToolHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.write(["version": 1, "hooks": ["sessionStart": [["command": "npx -y @example/gizmo session-start"]]]], at: directory.url.appendingPathComponent("hooks.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test(arguments: [["-y", "@example/gizmo", "mcp"], ["mcp", "--root", "/x"]])
    func cursorWithAServerNamedAsTheToolsThatIsNotOursHasSomething(arguments: [String]) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let command = arguments.first == "-y" ? "npx" : "/x/gizmo"
        try Self.write(["mcpServers": ["gizmo": ["command": command, "args": arguments]]], at: directory.url.appendingPathComponent("mcp.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithAServerOfTheToolsUnderAnotherNameHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.write(["mcpServers": ["index": ["command": "/x/gizmo", "args": ["mcp"]]]], at: directory.url.appendingPathComponent("mcp.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithOnlyAnotherToolsHooksAndServerHasNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.write(["version": 1, "hooks": ["sessionStart": [["command": "/x/widget session-start --agent cursor"]]]], at: directory.url.appendingPathComponent("hooks.json"))
        try Self.write(["mcpServers": ["widget": ["command": "/x/widget", "args": ["serve"]]]], at: directory.url.appendingPathComponent("mcp.json"))

        #expect(try Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithHooksThatAreNotJSONHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Data("{\"hooks\": {\"sessionStart\": [{\"command\": \"/x/gizmo hook\"}]".utf8).write(to: directory.url.appendingPathComponent("hooks.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithAnUnreadableHooksFileHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.dangle(directory.url.appendingPathComponent("hooks.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    @Test
    func cursorWithAnUnreadableServerFileHasSomething() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try Self.dangle(directory.url.appendingPathComponent("mcp.json"))

        #expect(try !Self.cursor(directory).hasNothingInstalled)
    }

    // MARK: A tool that lists no hook subcommands of its own

    @Test
    func claudeFindsTheHookThatItsRegistrationRecognisesWithoutTheToolListingSubcommands() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        let environment = Self.environment(home)
        let tool = FieldworkTool(name: "gizmo")
        let hooks = HookRegistration(tool: tool, events: [GizmoHooks.sessionStart])
        let data = try hooks.apply(to: nil, command: "/x/gizmo session-start", event: GizmoHooks.sessionStart).data
        try Self.putSettings(data, in: environment)
        let doctor = try DoctorClaude(environment: environment, probe: Self.spentProbe(environment), hooks: hooks, server: ClaudeMcpServer(tool: tool), expectedTools: ["look"])

        #expect(doctor.registeredHooks(in: data).map(\.event) == ["SessionStart"])
        #expect(!doctor.hasNothingInstalled)
    }

    @Test
    func cursorFindsTheHookThatItsRegistrationRecognisesWithoutTheToolListingSubcommands() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let tool = FieldworkTool(name: "gizmo")
        let hooks = CursorHooksFile(tool: tool, agentFlag: "--agent cursor", hooks: [CursorHooksFile.Hook(event: "sessionStart", subcommand: "session-start")])
        let install = CursorInstall(mcp: CursorMcpFile(server: ClaudeMcpServer(tool: tool)), hooks: hooks, directoryFlag: "--cursor-dir")
        let file = directory.url.appendingPathComponent("hooks.json")
        try Self.write(["version": 1, "hooks": ["sessionStart": [["command": "/x/gizmo session-start --agent cursor"]]]], at: file)
        let doctor = try DoctorCursor(directory: directory.url, probe: Self.spentProbe([:]), install: install, expectedTools: ["look"])

        #expect(try doctor.registeredHooks(in: Data(contentsOf: file)).map(\.event) == ["sessionStart"])
        #expect(!doctor.hasNothingInstalled)
    }
}

private extension DoctorNothingInstalledTests {
    static func environment(_ home: TemporaryDirectory) -> [String: String] {
        ["HOME": home.url.path, "PATH": "/usr/bin:/bin"]
    }

    /// A probe already closed: `hasNothingInstalled` runs nothing, and the scratch the probe made is gone.
    static func spentProbe(_ environment: [String: String]) throws -> DoctorProbe {
        let probe = try DoctorProbe(tool: gizmo.tool, version: "gizmo 1.0", environment: environment)
        probe.close()
        return probe
    }

    static func claude(_ home: TemporaryDirectory) throws -> DoctorClaude {
        let environment = environment(home)
        return try DoctorClaude(
            environment: environment,
            probe: spentProbe(environment),
            hooks: GizmoHooks.registration,
            server: gizmo.mcp.server,
            expectedTools: ["look"]
        )
    }

    static func cursor(_ directory: TemporaryDirectory) throws -> DoctorCursor {
        try DoctorCursor(directory: directory.url, probe: spentProbe([:]), install: gizmo.install, expectedTools: ["look"])
    }

    static func write(_ object: [String: Any], at file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: file)
    }

    static func putSettings(_ data: Data?, in environment: [String: String]) throws {
        let url = AgentPaths.claudeSettings(environment: environment)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data?.write(to: url)
    }

    /// A link that leads nowhere, which reading refuses rather than treating as empty.
    static func dangle(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: file.deletingLastPathComponent().appendingPathComponent("nowhere").path)
    }
}
