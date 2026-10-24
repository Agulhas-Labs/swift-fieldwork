// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The install and uninstall for Codex over a real home and a recording `codex`, with a made-up tool, `gizmo`.
struct CodexInstallTests {
    private static let install = CodexInstall(
        hooks: CodexTools.gizmo.file,
        server: CodexMcpServer(server: ClaudeMcpServer(tool: CodexTools.gizmo.tool))
    )
    private static var binary: String {
        "/opt/My Tools/gizmo"
    }

    private static var word: String {
        "'/opt/My Tools/gizmo'"
    }

    private static func home(_ root: TemporaryDirectory) -> AgentPaths.CodexHome {
        AgentPaths.codexHome(flag: root.url.appendingPathComponent(".codex").path, environment: [:])
    }

    private static func hooksURL(_ home: AgentPaths.CodexHome) -> URL {
        home.directory.appendingPathComponent("hooks.json")
    }

    private func run(_ home: AgentPaths.CodexHome, _ codex: FakeCodex) throws -> InstallOutcome {
        try Self.install.install(home: home, binary: Self.binary, binaryWord: Self.word, runner: codex)
    }

    @Test
    func anEmptyHomeGetsTheHooksAndTheServer() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex()

        let outcome = try run(home, codex)

        let file = try CodexTools.object(Data(contentsOf: Self.hooksURL(home)))
        let events = try Set(#require(file["hooks"] as? [String: Any]).keys)

        #expect(events == ["SessionStart", "PreToolUse", "PostToolUse"])
        #expect(codex.calls.last == FakeCodex.Call(arguments: ["mcp", "add", "gizmo", "--", "/opt/My Tools/gizmo", "mcp"], home: home.directory.path))
        #expect(outcome.lines == [
            "hooks: registered SessionStart — '/opt/My Tools/gizmo' session-start",
            "hooks: registered PreToolUse — '/opt/My Tools/gizmo' pre-tool-use",
            "hooks: registered PostToolUse — '/opt/My Tools/gizmo' post-tool-use",
            "mcp: registered gizmo — /opt/My Tools/gizmo mcp",
        ])
        #expect(outcome.written == [Self.hooksURL(home).path])
        #expect(outcome.failures.isEmpty)
    }

    @Test
    func aSecondInstallWritesNothingAndAddsNothing() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex()
        _ = try run(home, codex)
        let before = try Data(contentsOf: Self.hooksURL(home))
        let callsBefore = codex.calls.count

        let outcome = try run(home, codex)

        #expect(outcome.lines == [
            "hooks: already registered — SessionStart, PreToolUse, PostToolUse",
            "mcp: already registered — /opt/My Tools/gizmo mcp",
        ])
        #expect(outcome.written.isEmpty)
        #expect(try Data(contentsOf: Self.hooksURL(home)) == before)
        #expect(codex.calls.dropFirst(callsBefore).allSatisfy { $0.arguments.prefix(2) == ["mcp", "get"] })
    }

    @Test
    func aMovedBinaryIsReplacedInTheHooksAndTheServer() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex()
        _ = try Self.install.install(home: home, binary: "/old/gizmo", binaryWord: "/old/gizmo", runner: codex)

        let outcome = try run(home, codex)

        #expect(outcome.lines.contains("hooks: replaced stale registration (/old/gizmo session-start)"), "\(outcome.lines)")
        let mcp = outcome.lines.drop { !$0.hasPrefix("mcp:") }
        #expect(Array(mcp) == [
            "mcp: replaced stale registration (/old/gizmo mcp)",
            "mcp: registered gizmo — /opt/My Tools/gizmo mcp",
        ])
        #expect(codex.server?.command == Self.binary)
    }

    @Test
    func aForeignServerOfTheNameIsLeftAloneWhileTheHooksGoIn() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let codex = FakeCodex(server: ("/bin/other", ["serve"]))

        let outcome = try run(home, codex)

        #expect(outcome.lines.last == "mcp: left alone — a server named gizmo runs something else (/bin/other serve)")
        #expect(!codex.calls.contains { $0.arguments.prefix(2) == ["mcp", "add"] })
        #expect(outcome.lines.contains("hooks: registered SessionStart — '/opt/My Tools/gizmo' session-start"), "\(outcome.lines)")
        #expect(FileManager.default.fileExists(atPath: Self.hooksURL(home).path))
    }

    @Test
    func withoutCodexTheManualLineNamesTheHomeOnlyWhenItCameFromTheFlag() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let flagged = Self.home(root)

        let fromFlag = try run(flagged, FakeCodex(present: false))

        let path = flagged.directory.path
        #expect(fromFlag.lines.last == "mcp: `codex` is not on PATH — register the server with: CODEX_HOME=\(path) codex mcp add gizmo -- '/opt/My Tools/gizmo' mcp")

        let environment = AgentPaths.codexHome(flag: nil, environment: ["CODEX_HOME": root.url.appendingPathComponent("env").path])
        let fromEnvironment = try run(environment, FakeCodex(present: false))
        #expect(fromEnvironment.lines.last == "mcp: `codex` is not on PATH — register the server with: codex mcp add gizmo -- '/opt/My Tools/gizmo' mcp")
    }

    @Test
    func aHooksFileOfAnotherShapeIsRefusedBeforeCodexIsAsked() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        let bytes = Data(#"{"hooks": []}"#.utf8)
        try bytes.write(to: Self.hooksURL(home))
        let codex = FakeCodex()

        #expect(throws: SettingsFile.Refused.self) { try run(home, codex) }

        #expect(codex.calls.isEmpty)
        #expect(try Data(contentsOf: Self.hooksURL(home)) == bytes)
    }

    @Test
    func theUninstallTakesOutOursAndKeepsAForeignGroup() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        let seeded = try CodexTools.canonical(#"{"hooks": {"PreToolUse": [{"matcher": "*", "hooks": [{"type": "command", "command": "/usr/bin/audit"}]}]}}"#)
        try seeded.write(to: Self.hooksURL(home))
        let codex = FakeCodex()
        _ = try run(home, codex)

        let outcome = try Self.install.uninstall(home: home, runner: codex)

        #expect(outcome.lines == [
            "hooks: removed SessionStart — '/opt/My Tools/gizmo' session-start",
            "hooks: removed PreToolUse — '/opt/My Tools/gizmo' pre-tool-use",
            "hooks: removed PostToolUse — '/opt/My Tools/gizmo' post-tool-use",
            "mcp: removed gizmo — /opt/My Tools/gizmo mcp",
        ])
        #expect(codex.server == nil)
        #expect(try Data(contentsOf: Self.hooksURL(home)) == seeded)
    }

    @Test
    func theUninstallNotesAForeignServerAndLooksIntoNoHomeThatIsAbsent() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let absent = FakeCodex()

        #expect(try Self.install.uninstall(home: home, runner: absent) == InstallOutcome())
        #expect(absent.calls.isEmpty)

        try FileManager.default.createDirectory(at: home.directory, withIntermediateDirectories: true)
        let foreign = FakeCodex(server: ("/bin/other", ["serve"]))
        let outcome = try Self.install.uninstall(home: home, runner: foreign)
        #expect(outcome.notes == ["mcp: not ours, left alone — a server named gizmo in \(home.directory.path) runs something else (/bin/other serve)"])
        #expect(outcome.lines.isEmpty)
        #expect(foreign.server?.command == "/bin/other")
    }

    @Test
    func unregisterRemovesOursAndNotesAMissingCodexOnlyWhenAsked() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)
        let ours = FakeCodex(server: (Self.binary, ["mcp"]))
        var outcome = InstallOutcome()

        try Self.install.unregister(found: .ours(Self.binary), home: home, runner: ours, noteWithoutCodex: false, into: &outcome)

        #expect(outcome.lines == ["mcp: removed gizmo — /opt/My Tools/gizmo mcp"])
        #expect(ours.server == nil)

        var noted = InstallOutcome()
        try Self.install.unregister(found: .noCodex, home: home, runner: FakeCodex(present: false), noteWithoutCodex: true, into: &noted)
        #expect(noted.notes == ["mcp: not checked — `codex` is not on PATH; if Codex runs this tool's server, run: CODEX_HOME=\(home.directory.path) codex mcp remove gizmo"])

        var silent = InstallOutcome()
        try Self.install.unregister(found: .noCodex, home: home, runner: FakeCodex(present: false), noteWithoutCodex: false, into: &silent)
        #expect(silent == InstallOutcome())
    }

    @Test
    func anAddThatFailsIsAFailureNamingTheCommandToRun() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let home = Self.home(root)

        let outcome = try run(home, FakeCodex(addError: "boom"))

        #expect(outcome.failures == ["mcp: not registered — `codex mcp add gizmo` failed: boom; run: CODEX_HOME=\(home.directory.path) codex mcp add gizmo -- '/opt/My Tools/gizmo' mcp"])
    }
}
