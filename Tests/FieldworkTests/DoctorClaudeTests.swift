// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The Claude Code checks of a tool's doctor, over a made-up tool, `gizmo`, installed into a scratch home.
struct DoctorClaudeTests {
    private static let server = ClaudeMcpServer(tool: GizmoHooks.tool)
    private static let rule = ClaudeRuleInstall(tool: GizmoHooks.tool, shippedFileName: "gizmo.md", loadsOn: "**/*.swift")
    private static let tools = ["look", "find"]

    private static func checks(_ install: Install, server: ClaudeMcpServer = server, limit: TimeInterval = 20, version: String = "gizmo 1.0") throws -> [DoctorCheck] {
        let probe = try DoctorProbe(tool: GizmoHooks.tool, version: version, environment: install.environment, limit: limit)
        defer { probe.close() }
        return DoctorClaude(
            environment: install.environment,
            probe: probe,
            hooks: GizmoHooks.registration,
            server: server,
            expectedTools: tools,
            rule: rule
        ).checks()
    }

    private static func check(_ name: String, in checks: [DoctorCheck]) -> DoctorCheck? {
        checks.first { $0.name == name }
    }

    @Test
    func aWholeInstallPassesWithOneLinePerCheck() throws {
        let install = try Install()
        defer { install.directory.remove() }

        let checks = try Self.checks(install)

        #expect(checks.filter { $0.status != .pass }.isEmpty)
        #expect(checks.map(\.name) == ["hooks", "server", "binary", "version"] + GizmoHooks.events.map { "hook \($0.name)" } + ["mcp server", "rule"])
    }

    @Test
    func aHookMissingFromSettingsFailsAndNamesIt() throws {
        let install = try Install(hooks: GizmoHooks.events.filter { $0.name != "PostToolUse" })
        defer { install.directory.remove() }

        let hooks = try #require(Self.check("hooks", in: Self.checks(install)))

        #expect(hooks.status == .fail)
        #expect(hooks.detail.contains("PostToolUse"))
        #expect(hooks.detail.contains("gizmo install --agent claude"))
    }

    @Test
    func aRegistrationWithAnOlderMatcherDoesNotPass() throws {
        let older = HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["Bash"], timeout: 5)
        let install = try Install(hooks: GizmoHooks.events.map { $0.name == "PreToolUse" ? older : $0 })
        defer { install.directory.remove() }

        let hooks = try #require(Self.check("hooks", in: Self.checks(install)))

        #expect(hooks.status == .fail)
        #expect(hooks.detail.contains("not as this version registers them"))
    }

    @Test
    func aMissingSettingsFileFailsTheHooksCheckForEveryEvent() throws {
        let install = try Install(hooks: [])
        defer { install.directory.remove() }

        let hooks = try #require(Self.check("hooks", in: Self.checks(install)))

        #expect(hooks.status == .fail)
        #expect(hooks.detail.contains("SessionStart"))
    }

    @Test
    func anUnregisteredServerFailsAndStopsTheRunningChecks() throws {
        let install = try Install(registersServer: false)
        defer { install.directory.remove() }

        let checks = try Self.checks(install)

        #expect(Self.check("server", in: checks)?.status == .fail)
        #expect(Self.check("binary", in: checks) == nil)
    }

    /// The install's `npx` registration is not the binary the later checks run, and running it could fetch the package, so the check stops there.
    @Test
    func anNpxRegistrationFailsTheServerCheckAndRunsNothing() throws {
        let install = try Install()
        defer { install.directory.remove() }
        let config = AgentPaths.claudeConfig(environment: install.environment)
        let entry: [String: Any] = ["mcpServers": ["gizmo": ["command": "npx", "args": ["-y", "@x/gizmo", "mcp"]]]]
        try JSONSerialization.data(withJSONObject: entry).write(to: config)

        let checks = try Self.checks(install, server: ClaudeMcpServer(tool: GizmoHooks.tool, npmPackage: "@x/gizmo"))

        #expect(checks.map(\.name) == ["hooks", "server"])
        let server = try #require(Self.check("server", in: checks))
        #expect(server.status == .fail)
        #expect(server.detail == "no MCP server named gizmo of this tool's in \(config.path); run `gizmo install --agent claude`")
    }

    @Test
    func anUnreadableSettingsFileFailsTheHooksCheckAndSaysSo() throws {
        let install = try Install()
        defer { install.directory.remove() }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: install.settings.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: install.settings.path) }

        let hooks = try #require(Self.check("hooks", in: Self.checks(install)))

        #expect(hooks.status == .fail)
        #expect(hooks.detail.hasPrefix("claude: nothing written — \(install.settings.path) could not be read: "))
    }

    @Test
    func aServerMissingAToolFailsTheServerCheck() throws {
        let install = try Install(listing: ["look"])
        defer { install.directory.remove() }

        let server = try #require(Self.check("mcp server", in: Self.checks(install)))

        #expect(server.status == .fail)
        #expect(server.detail.contains("lists no find"))
    }

    @Test
    func aHookThatExitsNonZeroFailsItsOwnLine() throws {
        let install = try Install(hookBody: "cat > /dev/null; exit 3")
        defer { install.directory.remove() }

        let checks = try Self.checks(install)

        #expect(Self.check("hook Stop", in: checks)?.detail.hasPrefix("exited 3") == true)
        #expect(Self.check("mcp server", in: checks)?.status == .pass)
    }

    @Test
    func aDifferingVersionIsSaidAndNeverAFailure() throws {
        let install = try Install()
        defer { install.directory.remove() }

        let checks = try Self.checks(install, version: "gizmo 2.0")

        #expect(Self.check("version", in: checks)?.status == .differs)
        #expect(!DoctorReport(tool: GizmoHooks.tool, checks: checks).failsTheRun)
    }

    @Test
    func aMissingRuleFailsTheRuleCheck() throws {
        let install = try Install(installsRule: false)
        defer { install.directory.remove() }

        let rule = try #require(Self.check("rule", in: Self.checks(install)))

        #expect(rule.status == .fail)
    }

    @Test
    func aHookThatOutrunsTheLimitFailsInsteadOfWaiting() throws {
        let install = try Install(hookBody: "sleep 30")
        defer { install.directory.remove() }

        let started = Date()
        let hook = try #require(Self.check("hook Stop", in: Self.checks(install, limit: 1)))

        #expect(hook.status == .fail)
        #expect(hook.detail.hasPrefix("did not start, or did not finish"))
        #expect(Date().timeIntervalSince(started) < 20)
    }

    @Test
    func theProbeRunsEverythingThroughTheInjectedLauncher() throws {
        let seen = LaunchLog()
        let probe = try DoctorProbe(
            tool: GizmoHooks.tool,
            version: "1",
            environment: ["GIZMO_X": "1", "KEEP": "1"],
            scrubbing: ["GIZMO_"],
            pointing: { ["GIZMO_HOME": $0.path] },
            launcher: { binary, arguments, _, environment, limit in
                seen.record(binary: binary.path, arguments: arguments, environment: environment, limit: limit)
                return (0, Data("gizmo 9\n".utf8))
            }
        )
        defer { probe.close() }

        let output = probe.run(shell: "true")

        #expect(output?.status == 0)
        let call = try #require(seen.calls.first)
        #expect(call.binary == "/bin/sh")
        #expect(call.limit == 20)
        #expect(call.arguments.last?.hasSuffix("&& true") == true)
        #expect(call.environment["GIZMO_X"] == nil)
        #expect(call.environment["KEEP"] == "1")
        #expect(call.environment["GIZMO_HOME"] == call.environment["HOME"])
        #expect(probe.scratch.lastPathComponent.hasPrefix("gizmo-doctor-"))
    }
}

extension DoctorClaudeTests {
    /// A scratch home holding a `gizmo` that answers like the real thing, and what an install writes about it.
    private struct Install {
        let directory: TemporaryDirectory
        let binary: String

        var home: URL {
            directory.url
        }

        var environment: [String: String] {
            ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        }

        var settings: URL {
            AgentPaths.claudeSettings(environment: environment)
        }

        init(
            hooks: [HookRegistration.Event] = GizmoHooks.events,
            hookBody: String = "cat > /dev/null",
            listing: [String] = DoctorClaudeTests.tools,
            registersServer: Bool = true,
            installsRule: Bool = true
        ) throws {
            directory = try TemporaryDirectory()
            let bin = directory.url.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            binary = bin.appendingPathComponent("gizmo").path
            let names = listing.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
            let script = """
            #!/bin/sh
            case "$1" in
            --version) echo "gizmo 1.0" ;;
            mcp) cat > /dev/null
                 printf '%s\\n%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}' '{"jsonrpc":"2.0","id":2,"result":{"tools":[\(names)]}}' ;;
            *) \(hookBody) ;;
            esac
            """
            try Data(script.utf8).write(to: URL(fileURLWithPath: binary))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
            var data: Data?
            for event in hooks {
                data = try GizmoHooks.registration.apply(to: data, command: "\(binary) \(event.subcommand)", event: event).data
            }
            try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data?.write(to: settings)
            if registersServer {
                let entry: [String: Any] = ["mcpServers": ["gizmo": ["command": binary, "args": ["mcp"]]]]
                try JSONSerialization.data(withJSONObject: entry).write(to: AgentPaths.claudeConfig(environment: environment))
            }
            if installsRule {
                let path = AgentPaths.claudeRule(named: "gizmo.md", environment: environment)
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("rule\n".utf8).write(to: path)
            }
        }
    }
}
