// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The server a tool keeps in Codex's `config.toml`, as `codex mcp` shows it, over a made-up tool, `gizmo`.
struct CodexMcpServerTests {
    private static let gizmo = CodexMcpServer(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")))
    private static let widget = CodexMcpServer(server: ClaudeMcpServer(tool: FieldworkTool(name: "widget")))
    private static let home = URL(fileURLWithPath: "/scratch/codex-home", isDirectory: true)

    @Test
    func theArgumentsSpellTheCodexCommandsForTheServer() {
        #expect(Self.gizmo.getArguments == ["mcp", "get", "gizmo", "--json"])
        #expect(Self.gizmo.addArguments(binary: "/opt/bin/gizmo") == ["mcp", "add", "gizmo", "--", "/opt/bin/gizmo", "mcp"])
        #expect(Self.gizmo.removeArguments == ["mcp", "remove", "gizmo"])
    }

    @Test
    func noCodexOnPathIsReportedAsSuch() throws {
        #expect(try Self.gizmo.find(runner: FakeCodex(present: false), home: Self.home) == .noCodex)
    }

    @Test
    func aServerCodexHasNoRecordOfIsAbsent() throws {
        let codex = FakeCodex()
        #expect(try Self.gizmo.find(runner: codex, home: Self.home) == .absent)
        #expect(codex.calls == [FakeCodex.Call(arguments: ["mcp", "get", "gizmo", "--json"], home: Self.home.path)])
    }

    @Test
    func theToolsBinaryRunWithMcpIsOursAtAnyPath() throws {
        let codex = FakeCodex(server: ("/opt/bin/gizmo", ["mcp"]))
        #expect(try Self.gizmo.find(runner: codex, home: Self.home) == .ours("/opt/bin/gizmo"))
    }

    @Test
    func anotherCommandIsForeignAndDescribedAsTyped() throws {
        let codex = FakeCodex(server: ("/usr/bin/other", ["serve", "--fast"]))
        #expect(try Self.gizmo.find(runner: codex, home: Self.home) == .foreign("/usr/bin/other serve --fast"))
    }

    @Test
    func aSecondToolsServerIsForeignToTheFirst() throws {
        let codex = FakeCodex(server: ("/opt/bin/widget", ["mcp"]))
        #expect(try Self.gizmo.find(runner: codex, home: Self.home) == .foreign("/opt/bin/widget mcp"))
        #expect(Self.widget.getArguments == ["mcp", "get", "widget", "--json"])
    }

    @Test
    func anotherFailureIsRefusedWithItsWholeCauseChain() {
        let codex = FakeCodex(getError: "Error: failed to load configuration\n\nCaused by:\n    login was revoked\n")
        let refusal = #expect(throws: SettingsFile.Refused.self) { try Self.gizmo.find(runner: codex, home: Self.home) }
        #expect(refusal?.path == "/scratch/codex-home/config.toml")
        #expect(refusal?.agent == "codex")
        #expect(refusal?.reason == "could not be read by `codex mcp get gizmo --json`: Error: failed to load configuration: login was revoked")
    }

    @Test
    func outputWithNoTransportIsRefused() {
        let codex = ShownOnly(output: "{\"name\":\"gizmo\"}")
        let refusal = #expect(throws: SettingsFile.Refused.self) { try Self.gizmo.find(runner: codex, home: Self.home) }
        #expect(refusal?.reason == "could not be read: `codex mcp get gizmo --json` printed no server transport")
    }
}

/// A `codex` whose `mcp get` succeeds and prints exactly `output`.
private struct ShownOnly: CodexMcpRunner {
    let output: String

    func run(_: [String], home _: URL) throws -> Subprocess.Output? {
        Subprocess.Output(succeeded: true, standardOutput: output)
    }
}
