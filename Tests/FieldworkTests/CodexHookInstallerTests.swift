// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The install and uninstall for Codex as a consumer prints them, over a real home and a recording `codex`, with a made-up tool, `gizmo`.
struct CodexHookInstallerTests {
    private static let installer = CodexHookInstaller(
        codex: CodexInstall(hooks: CodexTools.gizmo.file, server: CodexMcpServer(server: ClaudeMcpServer(tool: CodexTools.gizmo.tool))),
        unsupported: ["unsupported on Codex: gizmo audit — no documented transcript format"],
        experimental: "experimental: not verified in a live Codex"
    )
    private static var binary: String {
        "/opt/My Tools/gizmo"
    }

    private static var restart: String {
        "restart Codex: it asks you to trust the gizmo hooks the first time it opens; approve them (again after a repoint; /hooks is where to review them)"
    }

    private static var restartAfterRemoval: String {
        "restart Codex to unload the hooks; removing gizmo's hooks moves any hook after them, so Codex asks you to trust those again when it next opens"
    }

    private static func home(_ root: TemporaryDirectory) -> AgentPaths.CodexHome {
        AgentPaths.codexHome(flag: root.url.appendingPathComponent(".codex").path, environment: [:])
    }

    @Test
    func anInstallPrintsTheHomeTheLinesTheWrittenFileTheRestartAndTheClosingNotes() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let hooks = home.directory.appendingPathComponent("hooks.json").path

        let result = try Self.installer.install(home: home, binary: Self.binary, runner: FakeCodex())

        #expect(result.printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "hooks: registered SessionStart — '/opt/My Tools/gizmo' session-start",
            "hooks: registered PreToolUse — '/opt/My Tools/gizmo' pre-tool-use",
            "hooks: registered PostToolUse — '/opt/My Tools/gizmo' post-tool-use",
            "mcp: registered gizmo — /opt/My Tools/gizmo mcp",
            "      \(hooks)",
            Self.restart,
            "unsupported on Codex: gizmo audit — no documented transcript format",
            "experimental: not verified in a live Codex",
        ])
        #expect(result.outcome.written == [hooks])
    }

    @Test
    func aSecondInstallWritesNothingAndStillEndsWithTheRestartAndTheClosingNotes() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex()
        try Self.installer.install(home: home, binary: Self.binary, runner: codex)

        let result = try Self.installer.install(home: home, binary: Self.binary, runner: codex)

        #expect(result.outcome.written.isEmpty)
        #expect(result.printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "hooks: already registered — SessionStart, PreToolUse, PostToolUse",
            "mcp: already registered — /opt/My Tools/gizmo mcp",
            Self.restart,
            "unsupported on Codex: gizmo audit — no documented transcript format",
            "experimental: not verified in a live Codex",
        ])
    }

    @Test
    func theUninstallOfAnEmptyHomeSaysNothingIsRegisteredAndAsksForNoRestart() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)

        let result = try Self.installer.uninstall(home: home, runner: FakeCodex())

        #expect(result.printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "codex: nothing registered in \(home.directory.path)",
        ])
    }

    @Test
    func theUninstallAfterAnInstallPrintsTheRemovalsThenTheRestart() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex()
        try Self.installer.install(home: home, binary: Self.binary, runner: codex)

        let result = try Self.installer.uninstall(home: home, runner: codex)

        #expect(result.printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "hooks: removed SessionStart — '/opt/My Tools/gizmo' session-start",
            "hooks: removed PreToolUse — '/opt/My Tools/gizmo' pre-tool-use",
            "hooks: removed PostToolUse — '/opt/My Tools/gizmo' post-tool-use",
            "mcp: removed gizmo — /opt/My Tools/gizmo mcp",
            "      \(home.directory.appendingPathComponent("hooks.json").path)",
            Self.restartAfterRemoval,
        ])
    }

    @Test
    func aServerAloneStillAsksForTheRestartBecauseARemovalLineSaysItWasTaken() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        let codex = FakeCodex(server: (Self.binary, ["mcp"]))

        let result = try Self.installer.uninstall(home: home, runner: codex)

        #expect(result.printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "mcp: removed gizmo — /opt/My Tools/gizmo mcp",
            Self.restartAfterRemoval,
        ])
        #expect(!result.outcome.changed)
        #expect(codex.server == nil)
    }

    @Test
    func theStepReportsThePrintedLinesAndWhetherTheServerWasRegistered() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let flag = root.url.appendingPathComponent(".codex").path
        let step = CodexInstallStep(installer: Self.installer)
        let codex = FakeCodex()

        let first = try step.run(binary: Self.binary, environment: [:], directory: flag, runner: codex)
        let second = try step.run(binary: Self.binary, environment: [:], directory: flag, runner: codex)

        #expect(first.agent == .codex)
        #expect(first.lines.first == "codex home: \(flag) (--codex-dir)")
        #expect(first.lines.last == "experimental: not verified in a live Codex")
        #expect(first.written == [flag + "/hooks.json"])
        #expect(first.registered)
        #expect(first.failures.isEmpty)
        #expect(!second.registered)
        #expect(second.written.isEmpty)
    }

    @Test
    func theStepCarriesAFailedRegistration() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let flag = root.url.appendingPathComponent(".codex").path

        let report = try CodexInstallStep(installer: Self.installer).run(binary: Self.binary, environment: [:], directory: flag, runner: FakeCodex(addError: "boom"))

        #expect(report.failures == ["mcp: not registered — `codex mcp add gizmo` failed: boom; run: CODEX_HOME=\(flag) codex mcp add gizmo -- '/opt/My Tools/gizmo' mcp"])
        #expect(!report.registered)
        #expect(report.lines.contains(report.failures[0]), "\(report.lines)")
    }

    @Test
    func aComposedOutcomeIsPrintedInTheInstallOrder() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let outcome = InstallOutcome(lines: ["a line"], notes: ["a note"], written: ["/w/one"], failures: ["a failure"])

        let printed = Self.installer.printed(installing: outcome, home: home)

        #expect(printed == [
            "codex home: \(home.directory.path) (--codex-dir)",
            "a line",
            "      /w/one",
            "a note",
            "a failure",
            Self.restart,
            "unsupported on Codex: gizmo audit — no documented transcript format",
            "experimental: not verified in a live Codex",
        ])
    }
}
