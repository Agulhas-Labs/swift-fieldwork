// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The Cursor checks of a tool's doctor, over a made-up tool, `gizmo`, installed into a scratch Cursor directory by the real Cursor install, or a `gizmo` that breaks one thing.
struct DoctorCursorTests {
    private static let gizmo = CursorTools.gizmo
    private static let tools = ["look", "find"]

    private static func checks(_ directory: URL) throws -> [DoctorCheck] {
        let probe = try DoctorProbe(tool: gizmo.tool, version: "gizmo 1.0", environment: ["PATH": "/usr/bin:/bin"])
        defer { probe.close() }
        return DoctorCursor(directory: directory, probe: probe, install: gizmo.install, expectedTools: tools).checks()
    }

    private static func line(_ name: String, in checks: [DoctorCheck]) -> String? {
        checks.first { $0.name == name }?.line
    }

    @Test
    func aWholeInstallPassesWithOneLinePerCheck() throws {
        let install = try Install()
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)

        #expect(checks.filter { $0.status != .pass }.isEmpty, "\(checks.map(\.line))")
        #expect(checks.map(\.name) == ["hooks", "server", "binary", "version", "hook sessionStart", "hook preToolUse", "hook postToolUse", "hook postToolUseFailure", "mcp server"])
        #expect(checks.allSatisfy { $0.agent == .cursor })
        #expect(Self.line("server", in: checks) == "cursor server: pass — gizmo — \(install.binary) mcp")
    }

    @Test
    func aMissingBinaryFailsTheBinaryCheck() throws {
        let install = try Install(registering: "/no/such/place/gizmo")
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)

        #expect(Self.line("binary", in: checks)?.hasPrefix("cursor binary: fail — /no/such/place/gizmo is not there, or is not executable") == true, "\(checks.map(\.line))")
    }

    @Test
    func aHookThatExitsNonZeroFailsItsOwnLine() throws {
        let install = try Install(failing: "pre-tool-use", with: "exit 3")
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)

        #expect(Self.line("hook preToolUse", in: checks)?.hasPrefix("cursor hook preToolUse: fail — exited 3") == true, "\(checks.map(\.line))")
        #expect(Self.line("hook postToolUse", in: checks)?.hasPrefix("cursor hook postToolUse: pass") == true)
    }

    @Test
    func aServerThatDoesNotStartFailsTheServerCheck() throws {
        let install = try Install(failing: "mcp", with: "exit 1")
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)

        #expect(Self.line("mcp server", in: checks)?.hasPrefix("cursor mcp server: fail — answered nothing (exit 1)") == true, "\(checks.map(\.line))")
        #expect(Self.line("binary", in: checks)?.hasPrefix("cursor binary: pass") == true)
    }

    @Test
    func aHookThatPrintsTextFailsSinceCursorReadsOnlyJSON() throws {
        let install = try Install(failing: "session-start", with: "echo primer; exit 0")
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)

        #expect(Self.line("hook sessionStart", in: checks)?.hasPrefix("cursor hook sessionStart: fail — exit 0, but printed something other than a JSON object") == true, "\(checks.map(\.line))")
    }

    @Test
    func aCursorDirectoryWithNothingRegisteredSaysToInstall() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        let checks = try Self.checks(directory.url)

        #expect(checks.count == 2)
        #expect(Self.line("hooks", in: checks)?.hasPrefix("cursor hooks: fail — not registered for sessionStart, preToolUse, postToolUse, postToolUseFailure in ") == true)
        #expect(Self.line("hooks", in: checks)?.hasSuffix("run `gizmo install --agent cursor`") == true)
        #expect(Self.line("server", in: checks)?.hasPrefix("cursor server: fail — no MCP server named gizmo of this tool's in ") == true)
        #expect(Self.line("server", in: checks)?.hasSuffix("run `gizmo install --agent cursor`") == true)
    }

    @Test
    func aDirectoryThatIsNotUnderAnyHomeIsCheckedAsGiven() throws {
        let install = try Install()
        defer { install.directory.remove() }
        let elsewhere = try TemporaryDirectory()
        defer { elsewhere.remove() }
        _ = try Self.gizmo.install.install(directory: elsewhere.url, binary: install.binary, binaryWord: ShellWord.quoted(install.binary))

        let checks = try Self.checks(elsewhere.url)

        #expect(checks.count == 9)
        #expect(checks.filter { $0.status != .pass }.isEmpty, "\(checks.map(\.line))")
    }

    @Test
    func eachPayloadIsInTheShapeCursorSends() throws {
        let url = try #require(Bundle.module.url(forResource: "cursor-hook-payloads", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let common = try #require(fixture["common"] as? [String: Any])
        let events = try #require(fixture["events"] as? [String: [String: Any]])
        let probe = try DoctorProbe(tool: Self.gizmo.tool, version: "gizmo 1.0", environment: [:])
        defer { probe.close() }
        let doctor = DoctorCursor(directory: probe.workspace, probe: probe, install: Self.gizmo.install, expectedTools: Self.tools)

        for hook in Self.gizmo.hooks.hooks {
            let payload = doctor.payload(for: hook.event)
            let recorded = try #require(events[hook.event], "no recorded \(hook.event)")
            let unknown = Set(payload.keys).subtracting(common.keys).subtracting(recorded.keys)
            #expect(unknown.isEmpty, "\(hook.event) carries \(unknown.sorted()), which Cursor was never seen to send")
            #expect(payload["hook_event_name"] as? String == recorded["hook_event_name"] as? String)
            #expect(payload["workspace_roots"] as? [String] == [probe.workspace.path])
            #expect(payload["conversation_id"] as? String == "gizmo-doctor")
        }
    }

    @Test
    func theJSONFormCarriesEveryPrintedLine() throws {
        let install = try Install(failing: "post-tool-use", with: "exit 2")
        defer { install.directory.remove() }

        let checks = try Self.checks(install.cursor)
        let carried = checks.compactMap { $0.json["line"] as? String }

        #expect(carried == checks.map(\.line))
        #expect(checks.count == 9)
        #expect(checks.allSatisfy { $0.json["agent"] as? String == "cursor" })
        #expect(carried.contains { $0.hasPrefix("cursor hook postToolUse: fail — exited 2") }, "\(carried)")
        #expect(DoctorReport(tool: Self.gizmo.tool, checks: checks).failsTheRun)
    }
}

extension DoctorCursorTests {
    /// A scratch home holding a `gizmo` that answers like the real thing except where one subcommand runs a body of its own, and the Cursor install for it.
    private struct Install {
        let directory: TemporaryDirectory
        let binary: String

        var cursor: URL {
            directory.url.appendingPathComponent(".cursor", isDirectory: true)
        }

        /// Registers `registered`, else the `gizmo` it writes, in the Cursor directory.
        init(registering registered: String? = nil, failing subcommand: String = "none", with body: String = "exit 0") throws {
            directory = try TemporaryDirectory()
            let bin = directory.url.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let written = bin.appendingPathComponent("gizmo").path
            let names = DoctorCursorTests.tools.map { "{\"name\":\"\($0)\"}" }.joined(separator: ",")
            let script = """
            #!/bin/sh
            if [ "$1" = \(subcommand) ]; then \(body); fi
            case "$1" in
            --version) echo "gizmo 1.0" ;;
            mcp) cat > /dev/null
                 printf '%s\\n%s\\n' '{"jsonrpc":"2.0","id":1,"result":{}}' '{"jsonrpc":"2.0","id":2,"result":{"tools":[\(names)]}}' ;;
            *) cat > /dev/null ;;
            esac
            """
            try Data(script.utf8).write(to: URL(fileURLWithPath: written))
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: written)
            binary = registered ?? written
            try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
            _ = try DoctorCursorTests.gizmo.install.install(directory: cursor, binary: binary, binaryWord: ShellWord.quoted(binary))
        }
    }
}
