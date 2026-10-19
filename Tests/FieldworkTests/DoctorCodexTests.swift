// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The Codex checks of a tool's doctor, over a made-up tool, `gizmo`, in a scratch Codex home whose `hooks.json` and trust records name a `gizmo` that answers like the real thing, or a stand-in that breaks one thing.
struct DoctorCodexTests {
    private static let tools = ["look", "find"]
    private static let events = [
        HookRegistration.Event(name: "SessionStart", subcommand: "session-start"),
        HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["*"]),
        HookRegistration.Event(name: "PostToolUse", subcommand: "post-tool-use", matchers: ["*"]),
    ]
    private static let hooks = HookRegistration(tool: GizmoHooks.tool, events: events)
    private static let server = CodexMcpServer(server: ClaudeMcpServer(tool: GizmoHooks.tool))

    private static func checks(_ scratch: Scratch, runner: FakeCodex, source: String? = nil) throws -> [DoctorCheck] {
        let probe = try DoctorProbe(tool: GizmoHooks.tool, version: "gizmo 1.0", environment: ["PATH": "/usr/bin:/bin"])
        defer { probe.close() }
        return doctor(scratch, runner: runner, probe: probe, source: source).checks()
    }

    private static func doctor(_ scratch: Scratch, runner: any CodexMcpRunner, probe: DoctorProbe, source: String? = nil) -> DoctorCodex {
        let home = source.map { AgentPaths.CodexHome(directory: scratch.codexHome, source: $0) } ?? AgentPaths.codexHome(flag: nil, environment: scratch.environment)
        return DoctorCodex(home: home, runner: runner, probe: probe, hooks: hooks, server: server, expectedTools: tools)
    }

    private static func lines(_ checks: [DoctorCheck]) -> String {
        checks.map(\.line).joined(separator: "\n")
    }

    private static func registered(_ binary: String) -> FakeCodex {
        FakeCodex(server: (binary, ["mcp"]))
    }

    @Test
    func aWholeCodexInstallPassesWithOneLinePerCheck() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let checks = try Self.checks(scratch, runner: Self.registered(scratch.binary))
        let printed = Self.lines(checks)

        #expect(checks.allSatisfy { $0.status == .pass }, "\(printed)")
        let named = ["codex hook SessionStart", "codex hook PreToolUse", "codex hook PostToolUse", "codex hooks", "codex trust", "codex server", "codex binary", "codex version", "codex mcp server"]
        #expect(checks.map { "\($0.agent.rawValue) \($0.name)" }.sorted() == named.sorted(), "\(printed)")
        #expect(printed.contains("codex trust: pass — trust recorded for 3 of 3 in "), "\(printed)")
        #expect(printed.contains("codex server: pass — gizmo — \(scratch.binary) mcp"), "\(printed)")
        #expect(printed.contains("codex mcp server: pass — started; lists look, find"), "\(printed)")
    }

    @Test
    func aMissingBinaryFailsTheCodexBinaryCheck() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let printed = try Self.lines(Self.checks(scratch, runner: Self.registered("/no/such/place/gizmo")))

        #expect(printed.contains("codex binary: fail — /no/such/place/gizmo is not there, or is not executable"), "\(printed)")
    }

    @Test
    func aCodexHookThatExitsNonZeroFailsItsOwnLine() throws {
        let scratch = try Scratch(failing: "pre-tool-use", status: 3)
        defer { scratch.directory.remove() }
        let printed = try Self.lines(Self.checks(scratch, runner: Self.registered(scratch.binary)))

        #expect(printed.contains("codex hook PreToolUse: fail — exited 3"), "\(printed)")
        #expect(printed.contains("codex hook PostToolUse: pass"), "\(printed)")
    }

    @Test
    func aCodexServerThatDoesNotStartFailsTheMcpServerCheck() throws {
        let scratch = try Scratch(failing: "mcp", status: 1)
        defer { scratch.directory.remove() }
        let printed = try Self.lines(Self.checks(scratch, runner: Self.registered(scratch.binary)))

        #expect(printed.contains("codex mcp server: fail — answered nothing (exit 1)"), "\(printed)")
        #expect(printed.contains("codex binary: pass"), "\(printed)")
    }

    @Test
    func aCodexWithNoServerOfTheToolsNameFailsWithTheInstallHint() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let printed = try Self.lines(Self.checks(scratch, runner: FakeCodex()))

        #expect(printed.contains("codex server: fail — no MCP server named gizmo in "), "\(printed)")
        #expect(printed.contains("; run `gizmo install --agent codex`"), "\(printed)")
        #expect(!printed.contains("codex mcp server:"), "\(printed)")
    }

    @Test
    func aCodexHomeWithoutHooksFailsTheHooksCheck() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }
        let printed = try Self.lines(Self.checks(scratch, runner: Self.registered(scratch.binary)))

        #expect(printed.contains("codex hooks: fail — not registered for SessionStart, PreToolUse, PostToolUse in "), "\(printed)")
        #expect(!printed.contains("codex trust:"), "\(printed)")
    }

    @Test
    func trustIsLookedUpAtTheHandlersPositionPastForeignGroups() throws {
        let scratch = try Scratch(foreignFirst: true)
        defer { scratch.directory.remove() }
        let config = try String(contentsOf: scratch.codexHome.appendingPathComponent("config.toml"), encoding: .utf8)
        #expect(config.contains(":pre_tool_use:1:0\"]"), "\(config)")
        let printed = try Self.lines(Self.checks(scratch, runner: Self.registered(scratch.binary)))

        #expect(printed.contains("codex trust: pass — trust recorded for 3 of 3 in "), "\(printed)")
    }

    @Test
    func aPartialTrustRecordIsUnknownWithItsCount() throws {
        let scratch = try Scratch(trusted: 2)
        defer { scratch.directory.remove() }
        let checks = try Self.checks(scratch, runner: Self.registered(scratch.binary))
        let printed = Self.lines(checks)

        #expect(printed.contains("codex trust: unknown — trust recorded for 2 of 3 in "), "\(printed)")
        #expect(printed.contains("open Codex and approve the gizmo hooks (/hooks to review them)"), "\(printed)")
        #expect(!checks.contains { $0.status == .fail }, "\(printed)")
    }

    @Test
    func anAbsentConfigTomlLeavesTrustUnknownAndPassing() throws {
        let scratch = try Scratch(trusted: nil)
        defer { scratch.directory.remove() }
        let checks = try Self.checks(scratch, runner: Self.registered(scratch.binary))
        let printed = Self.lines(checks)

        #expect(printed.contains("codex trust: unknown — no "), "\(printed)")
        #expect(!checks.contains { $0.status == .fail }, "\(printed)")
    }

    @Test
    func aCodexNotOnPathLeavesTheServerUnknownAndRunsTheHooks() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let checks = try Self.checks(scratch, runner: FakeCodex(present: false))
        let printed = Self.lines(checks)

        #expect(printed.contains("codex server: unknown — `codex` is not on PATH"), "\(printed)")
        #expect(printed.contains("codex hook PreToolUse: pass"), "\(printed)")
        #expect(!printed.contains("codex binary:"), "\(printed)")
        #expect(!checks.contains { $0.status == .fail }, "\(printed)")
    }

    @Test
    func aCodexThatCannotReadItsServersLeavesTheServerUnknown() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let checks = try Self.checks(scratch, runner: FakeCodex(getError: "Error: failed to parse config.toml"))
        let printed = Self.lines(checks)

        #expect(printed.contains("codex server: unknown — `codex mcp get gizmo --json` did not answer: "), "\(printed)")
        #expect(printed.contains("failed to parse config.toml"), "\(printed)")
        #expect(!checks.contains { $0.status == .fail }, "\(printed)")
    }

    @Test
    func aHomeFromTheCodexDirFlagIsNamedAndShapesTheInstallHint() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let codex = FakeCodex()
        let printed = try Self.lines(Self.checks(scratch, runner: codex, source: "--codex-dir"))
        let hooksFile = scratch.codexHome.appendingPathComponent("hooks.json").path

        #expect(printed.contains("codex hooks: pass — registered for SessionStart, PreToolUse, PostToolUse in \(hooksFile) (Codex home from --codex-dir)"), "\(printed)")
        #expect(printed.contains("; run `gizmo install --agent codex --codex-dir \(ShellWord.quoted(scratch.codexHome.path))`"), "\(printed)")
        #expect(codex.calls.map(\.home) == [scratch.codexHome.path])
    }

    @Test
    func aToolWithItsOwnInstallCommandNamesItInTheHint() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let tool = FieldworkTool(name: "gizmo", hookSubcommands: ["session-start", "pre-tool-use", "post-tool-use"], installCommand: "gizmo setup")
        let probe = try DoctorProbe(tool: tool, version: "gizmo 1.0", environment: ["PATH": "/usr/bin:/bin"])
        defer { probe.close() }
        let doctor = DoctorCodex(
            home: AgentPaths.codexHome(flag: nil, environment: scratch.environment),
            runner: FakeCodex(),
            probe: probe,
            hooks: HookRegistration(tool: tool, events: Self.events),
            server: CodexMcpServer(server: ClaudeMcpServer(tool: tool)),
            expectedTools: Self.tools
        )

        #expect(Self.lines(doctor.checks()).contains("; run `gizmo setup --agent codex`"))
    }

    // MARK: Nothing installed

    @Test
    func aHomeThatDoesNotExistHasNothingWithoutAskingCodex() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let codex = FakeCodex()
        let probe = try DoctorProbe(tool: GizmoHooks.tool, version: "gizmo 1.0", environment: [:])
        defer { probe.close() }
        let missing = AgentPaths.CodexHome(directory: scratch.directory.url.appendingPathComponent("absent", isDirectory: true), source: "--codex-dir")
        let doctor = DoctorCodex(home: missing, runner: codex, probe: probe, hooks: Self.hooks, server: Self.server, expectedTools: Self.tools)

        #expect(doctor.hasNothingInstalled)
        #expect(codex.calls.isEmpty)
    }

    @Test
    func onlyAnotherToolsHooksAndNoServerHasNothing() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }
        let foreign: [String: Any] = ["hooks": ["PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/bin/true"]]]]]]
        try JSONSerialization.data(withJSONObject: foreign).write(to: scratch.codexHome.appendingPathComponent("hooks.json"))

        #expect(try Self.hasNothing(scratch, FakeCodex()))
    }

    @Test
    func aRegisteredHookOfTheToolHasSomething() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }

        #expect(try !Self.hasNothing(scratch, FakeCodex()))
    }

    @Test
    func aServerOfTheToolsHasSomething() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }

        #expect(try !Self.hasNothing(scratch, Self.registered(scratch.binary)))
    }

    @Test
    func anUnreadableHooksFileHasSomething() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }
        try FileManager.default.createDirectory(at: scratch.codexHome.appendingPathComponent("hooks.json"), withIntermediateDirectories: true)

        #expect(try !Self.hasNothing(scratch, FakeCodex()))
    }

    @Test
    func aCodexThatIsNotOnPathLeavesAHomeWithoutHooksWithSomething() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }

        #expect(try !Self.hasNothing(scratch, FakeCodex(present: false)))
    }

    @Test
    func aCodexThatRefusesToAnswerLeavesAHomeWithoutHooksWithSomething() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }

        #expect(try !Self.hasNothing(scratch, FakeCodex(getError: "Error: failed to parse config.toml")))
    }

    @Test
    func theHookTheRegistrationRecognisesIsSomethingEvenWhenTheToolListsNoSubcommands() throws {
        let scratch = try Scratch()
        defer { scratch.directory.remove() }
        let tool = FieldworkTool(name: "gizmo")
        let probe = try DoctorProbe(tool: tool, version: "gizmo 1.0", environment: [:])
        defer { probe.close() }
        let doctor = DoctorCodex(
            home: AgentPaths.codexHome(flag: nil, environment: scratch.environment),
            runner: FakeCodex(),
            probe: probe,
            hooks: HookRegistration(tool: tool, events: Self.events),
            server: CodexMcpServer(server: ClaudeMcpServer(tool: tool)),
            expectedTools: Self.tools
        )

        #expect(try doctor.registeredHooks(in: Data(contentsOf: scratch.codexHome.appendingPathComponent("hooks.json"))).count == 3)
        #expect(!doctor.hasNothingInstalled)
    }

    @Test
    func trustIsFoundInAHomeWhoseNameHoldsAColon() throws {
        let scratch = try Scratch(hooks: false)
        defer { scratch.directory.remove() }
        let home = scratch.directory.url.appendingPathComponent("a:b", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let file = home.appendingPathComponent("hooks.json")
        let table = Dictionary(uniqueKeysWithValues: Self.events.map { event in
            (event.name, [["matcher": "*", "hooks": [["type": "command", "command": "\(scratch.binary) \(event.subcommand)"]]]])
        })
        try JSONSerialization.data(withJSONObject: ["hooks": table]).write(to: file)
        let records = ["session_start", "pre_tool_use", "post_tool_use"].map { event in
            "[hooks.state.\"\(file.resolvingSymlinksInPath().path):\(event):0:0\"]\ntrusted_hash = \"sha256:0f\"\n"
        }
        try records.joined(separator: "\n").write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        let probe = try DoctorProbe(tool: GizmoHooks.tool, version: "gizmo 1.0", environment: ["PATH": "/usr/bin:/bin"])
        defer { probe.close() }
        let doctor = DoctorCodex(home: AgentPaths.CodexHome(directory: home, source: "--codex-dir"), runner: Self.registered(scratch.binary), probe: probe, hooks: Self.hooks, server: Self.server, expectedTools: Self.tools)
        let printed = Self.lines(doctor.checks())

        #expect(printed.contains("codex trust: pass — trust recorded for 3 of 3 in "), "\(printed)")
    }

    private static func hasNothing(_ scratch: Scratch, _ runner: FakeCodex) throws -> Bool {
        let probe = try DoctorProbe(tool: GizmoHooks.tool, version: "gizmo 1.0", environment: [:])
        defer { probe.close() }
        return doctor(scratch, runner: runner, probe: probe).hasNothingInstalled
    }
}

extension DoctorCodexTests {
    /// A scratch home holding a `gizmo` that answers like the real thing (or exits `status` for the `failing` subcommand), the Codex home's hooks registered for it behind a foreign `PreToolUse` group when asked, and that many of them recorded as trusted in `config.toml`, which `nil` leaves out.
    private struct Scratch {
        let directory: TemporaryDirectory
        let binary: String

        var environment: [String: String] {
            ["HOME": directory.url.path, "PATH": "/usr/bin:/bin"]
        }

        var codexHome: URL {
            AgentPaths.codexDirectory(environment: environment)
        }

        init(failing subcommand: String = "none", status: Int32 = 0, hooks: Bool = true, foreignFirst: Bool = false, trusted: Int? = 3) throws {
            directory = try TemporaryDirectory()
            let bin = directory.url.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            binary = bin.appendingPathComponent("gizmo").path
            let names = DoctorCodexTests.tools.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
            let script = """
            #!/bin/sh
            if [ "$1" = \(subcommand) ]; then exit \(status); fi
            case "$1" in
            --version) echo "gizmo 1.0" ;;
            mcp) cat > /dev/null
                 printf '%s\\n%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}' '{"jsonrpc":"2.0","id":2,"result":{"tools":[\(names)]}}' ;;
            *) cat > /dev/null ;;
            esac
            """
            try Data(script.utf8).write(to: URL(fileURLWithPath: binary))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary)
            let home = AgentPaths.codexDirectory(environment: ["HOME": directory.url.path])
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            let file = home.appendingPathComponent("hooks.json")
            guard hooks else { return }
            var table: [String: Any] = [:]
            for event in DoctorCodexTests.events {
                var groups: [[String: Any]] = []
                if foreignFirst, event.name == "PreToolUse" {
                    groups.append(["matcher": "Bash", "hooks": [["type": "command", "command": "/usr/bin/true"]]])
                }
                groups.append(["matcher": "*", "hooks": [["type": "command", "command": "\(binary) \(event.subcommand)"]]])
                table[event.name] = groups
            }
            try JSONSerialization.data(withJSONObject: ["hooks": table]).write(to: file)
            if let trusted {
                // The key is written with the path resolved, so the doctor's canonical comparison is what matches it.
                let positions = [("session_start", 0), ("pre_tool_use", foreignFirst ? 1 : 0), ("post_tool_use", 0)].prefix(trusted)
                let records = positions.map { event, group in
                    "[hooks.state.\"\(file.resolvingSymlinksInPath().path):\(event):\(group):0\"]\ntrusted_hash = \"sha256:0f\"\n"
                }
                try (["[mcp_servers.gizmo]\ncommand = \"\(binary)\"\n"] + records).joined(separator: "\n").write(to: home.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
            }
        }
    }
}
