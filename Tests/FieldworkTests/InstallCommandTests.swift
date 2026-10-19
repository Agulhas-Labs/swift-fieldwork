// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// A tool whose install verb is not `install`, over a made-up tool, `gizmo`: every remedy names the tool's own command and none falls back to the default spelling.
struct InstallCommandTests {
    private static let tool = FieldworkTool(name: "gizmo", hookSubcommands: ["stop"], installCommand: "gizmo install-hook")
    private static let command = "gizmo install-hook"
    private static let defaultSpelling = "gizmo install --"

    private static func detection(_ agents: Set<Agent>) -> AgentDetection {
        let binaries: [Agent: String] = [.claude: "claude", .cursor: "agent", .codex: "codex"]
        let found = Set(agents.compactMap { binaries[$0] })
        return AgentDetection.detect(AgentDetection.Machine(
            environment: ["HOME": "/scratch/home", "PATH": "/scratch/bin"],
            applications: URL(fileURLWithPath: "/scratch/Applications", isDirectory: true),
            pathLookup: { found.contains($0) ? URL(fileURLWithPath: "/scratch/bin/\($0)") : nil },
            fileExists: { _ in false }
        ), tool: tool)
    }

    @Test
    func theInstallCommandIsTheNamePlusInstallUnlessTheToolSaysOtherwise() {
        #expect(FieldworkTool(name: "gizmo").installCommand == "gizmo install")
        #expect(Self.tool.installCommand == Self.command)
    }

    @Test
    func theNothingInstalledVerdictNamesTheToolsCommand() {
        let report = DoctorReport(tool: Self.tool, checks: [], skipped: [], notInstalled: [.claude])

        let line = report.lines.joined(separator: "\n")

        #expect(line.contains("`\(Self.command)` adds it"))
        #expect(!line.contains("gizmo install `"))
    }

    @Test
    func aNotInstalledLineNamesTheToolsCommandForThatAgent() {
        let report = DoctorReport(tool: Self.tool, checks: [.pass(.claude, "binary", "ok")], skipped: [], notInstalled: [.cursor])

        let text = report.lines.joined(separator: "\n")

        #expect(text.contains("cursor: found, gizmo not installed — \(Self.command) --agent cursor adds it"))
        #expect(!text.contains(Self.defaultSpelling))
    }

    @Test
    func nothingDetectedNamesTheToolsCommandPerAgentAndForAll() {
        let text = AgentSelection.nothingDetectedText(Self.detection([]), tool: Self.tool)

        #expect(text.contains("\(Self.command) --agent claude"))
        #expect(text.contains("Or all three: \(Self.command) --all"))
        #expect(!text.contains(Self.defaultSpelling))
    }

    @Test
    func needsFlagsNamesTheToolsCommandForYesAndForEachAgent() {
        let text = AgentSelection.needsFlagsText(detected: Self.detection([.claude, .codex]), tool: Self.tool)

        #expect(text.contains("\(Self.command) --yes"))
        #expect(text.contains("\(Self.command) --agent claude --agent codex"))
        #expect(!text.contains(Self.defaultSpelling))
    }

    @Test
    func theClaudeDoctorsHooksServerAndRuleRemediesNameTheToolsCommand() throws {
        let home = try TemporaryDirectory()
        defer { home.remove() }
        let environment = ["HOME": home.url.path, "PATH": "/usr/bin:/bin"]
        let probe = try DoctorProbe(tool: Self.tool, version: "gizmo 1.0", environment: environment)
        defer { probe.close() }
        let doctor = DoctorClaude(
            environment: environment,
            probe: probe,
            hooks: HookRegistration(tool: Self.tool, events: GizmoHooks.events),
            server: ClaudeMcpServer(tool: Self.tool),
            expectedTools: ["look"],
            rule: ClaudeRuleInstall(tool: Self.tool, shippedFileName: "gizmo.md", loadsOn: "**/*.swift")
        )

        let withoutServer = doctor.checks()
        let entry: [String: Any] = ["mcpServers": ["gizmo": ["command": "/nonexistent/gizmo", "args": ["mcp"]]]]
        try JSONSerialization.data(withJSONObject: entry).write(to: AgentPaths.claudeConfig(environment: environment))
        let withServer = doctor.checks()

        for (name, checks) in [("hooks", withoutServer), ("server", withoutServer), ("rule", withServer)] {
            let check = try #require(checks.first { $0.name == name })
            #expect(check.status == .fail)
            #expect(check.detail.contains("run `\(Self.command) --agent claude`"))
            #expect(!check.detail.contains(Self.defaultSpelling))
        }
    }

    @Test
    func aBinaryThatDoesNotRunNamesTheToolsCommand() throws {
        let probe = try DoctorProbe(tool: Self.tool, version: "gizmo 1.0", environment: ["PATH": "/usr/bin:/bin"])
        defer { probe.close() }

        let checks = DoctorRun(agent: .claude, probe: probe, expectedTools: []).binaryChecks("/nonexistent/gizmo")

        let check = try #require(checks.first)
        #expect(check.status == .fail)
        #expect(check.detail.contains("run `\(Self.command) --agent claude`"))
        #expect(!check.detail.contains(Self.defaultSpelling))
    }

    @Test
    func theRuleInstallsDefaultCommandIsTheToolsOwn() {
        let rule = ClaudeRuleInstall(tool: Self.tool, shippedFileName: "gizmo.md", loadsOn: "**/*.swift")
        let explicit = ClaudeRuleInstall(tool: Self.tool, shippedFileName: "gizmo.md", loadsOn: "**/*.swift", installCommand: "gizmo copy-rule")

        #expect(rule.installCommand == Self.command)
        #expect(explicit.installCommand == "gizmo copy-rule")
    }
}
