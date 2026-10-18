// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Two tools set up through one library: what each builds, runs and writes for Claude Code never names the other.
struct TwoToolsClaudeMcpTests {
    private static let gizmo = ClaudeMcpServer(tool: FieldworkTool(name: "gizmo"))
    private static let widget = ClaudeMcpServer(tool: FieldworkTool(name: "widget"), removal: .userScopeThenUnscoped)

    @Test
    func theAddArgumentsAndRemovalCommandsOfTwoServersNeverMentionEachOther() {
        let gizmoText = (Self.gizmo.addArguments(binary: "/opt/bin/gizmo") + Self.gizmo.removalArguments.flatMap(\.self) + [Self.gizmo.removalCommand, Self.gizmo.manual(binary: "/opt/bin/gizmo")]).joined(separator: " ")
        let widgetText = (Self.widget.addArguments(binary: "/opt/bin/widget") + Self.widget.removalArguments.flatMap(\.self) + [Self.widget.removalCommand, Self.widget.manual(binary: "/opt/bin/widget")]).joined(separator: " ")

        #expect(!gizmoText.contains("widget"))
        #expect(!widgetText.contains("gizmo"))
        #expect(Self.gizmo.removalArguments == [["mcp", "remove", "gizmo", "--scope", "user"]])
        #expect(Self.gizmo.removalCommand == "claude mcp remove gizmo --scope user")
        #expect(Self.widget.removalArguments == [["mcp", "remove", "widget", "--scope", "user"], ["mcp", "remove", "widget"]])
        #expect(Self.widget.removalCommand == "claude mcp remove widget --scope user || claude mcp remove widget")
    }

    @Test
    func theStaleReplacementRunsOnlyTheToolsOwnRemovals() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = directory.url.appendingPathComponent(".claude.json")
        try JSONSerialization.data(withJSONObject: ["mcpServers": [
            "gizmo": ["type": "stdio", "command": "/old/gizmo", "args": ["mcp"]],
            "widget": ["type": "stdio", "command": "/old/widget", "args": ["mcp"]],
        ]]).write(to: config)
        let claude = FakeClaude(config: config, serverName: "widget")

        let outcome = try ClaudeMcpInstall(server: Self.widget).install(config: config, binary: "/new/widget", runner: claude)

        #expect(claude.calls == [
            ["mcp", "remove", "widget", "--scope", "user"],
            ["mcp", "add", "--transport", "stdio", "--scope", "user", "widget", "--", "/new/widget", "mcp"],
        ])
        #expect(outcome.failures.isEmpty)
        #expect(ClaudeMcpInstall(server: Self.gizmo).plan(config: config, binary: "/old/gizmo") == .current)
        #expect(ClaudeMcpInstall(server: Self.widget).plan(config: config, binary: "/new/widget") == .current)
    }

    @Test
    func twoRuleInstallsIntoOneDirectoryLeaveBothAndEachUninstallRemovesOnlyItsOwn() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let rules = directory.url.appendingPathComponent("rules")
        let gizmo = ClaudeRuleInstall(tool: FieldworkTool(name: "gizmo"), shippedFileName: "Gizmo.md", loadsOn: "**/*.swift")
        let widget = ClaudeRuleInstall(tool: FieldworkTool(name: "widget"), shippedFileName: "Widget.md", loadsOn: "**/*.swift")
        let gizmoSource = directory.url.appendingPathComponent("Gizmo.md")
        let widgetSource = directory.url.appendingPathComponent("Widget.md")
        try "gizmo rule".write(to: gizmoSource, atomically: true, encoding: .utf8)
        try "widget rule".write(to: widgetSource, atomically: true, encoding: .utf8)
        let gizmoRule = rules.appendingPathComponent("gizmo.md")
        let widgetRule = rules.appendingPathComponent("widget.md")

        _ = try gizmo.install(source: gizmoSource, destination: gizmoRule)
        _ = try widget.install(source: widgetSource, destination: widgetRule)
        #expect(try String(contentsOf: gizmoRule, encoding: .utf8) == "gizmo rule")
        #expect(try String(contentsOf: widgetRule, encoding: .utf8) == "widget rule")

        let removed = try gizmo.uninstall(destination: gizmoRule)
        #expect(removed.lines == ["rule: removed \(gizmoRule.path)"])
        #expect(PathKind.of(gizmoRule) == .absent)
        #expect(try String(contentsOf: widgetRule, encoding: .utf8) == "widget rule")

        _ = try widget.uninstall(destination: widgetRule)
        #expect(PathKind.of(widgetRule) == .absent)
    }
}
