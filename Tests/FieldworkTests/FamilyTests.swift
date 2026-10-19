// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

@Suite("Family")
struct FamilyTests {
    private let gizmo = FieldworkTool(name: "gizmo")
    private let widget = FieldworkTool(name: "widget")
    private var members: [Family.Member] {
        [Family.Member(tool: gizmo), Family.Member(tool: widget)]
    }

    private let flags = AgentSelection.Flags(agents: [.cursor], yes: true)

    /// A directory holding an executable `widget` that logs its argv and the family variable to `log`.
    private func fakeWidget(in directory: URL, log: URL) throws {
        let script = "#!/bin/sh\necho \"$*|$FIELDWORK_FAMILY_INSTALL\" >> '\(log.path)'\nexit 3\n"
        let path = directory.appendingPathComponent("widget")
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }

    @Test("argv is the prefix, each agent in order, then --all, --yes, --dry-run")
    func argv() {
        let member = Family.Member(tool: widget)
        let all = AgentSelection.Flags(agents: [.codex, .claude], all: true, yes: true, dryRun: true)
        #expect(member.installArguments(for: all) == ["install", "--agent", "codex", "--agent", "claude", "--all", "--yes", "--dry-run"])
        #expect(member.installArguments(for: AgentSelection.Flags()) == ["install"])
    }

    @Test("runs a member found on PATH once, as the caller, and skips the caller")
    func runsOnce() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let log = directory.url.appendingPathComponent("log")
        try fakeWidget(in: directory.url, log: log)
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: ["PATH": directory.url.path])
        #expect(results.count == 1)
        #expect(results.first?.member == "widget")
        #expect(results.first?.exitStatus == 3)
        #expect(results.first?.arguments == ["install", "--agent", "cursor", "--yes"])
        #expect(try String(contentsOf: log, encoding: .utf8) == "install --agent cursor --yes|gizmo\n")
    }

    @Test("runs nothing where FIELDWORK_FAMILY_INSTALL is already set")
    func oneHop() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let log = directory.url.appendingPathComponent("log")
        try fakeWidget(in: directory.url, log: log)
        let environment = ["PATH": directory.url.path, "FIELDWORK_FAMILY_INSTALL": "widget"]
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: environment)
        #expect(results.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: log.path))
    }

    @Test("a member on neither PATH nor beside the binary is silent")
    func absentIsSilent() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let calls = Counter()
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: ["PATH": directory.url.path], besideDirectory: directory.url.path) { _, _, _ in
            calls.bump()
            return 0
        }
        #expect(results.isEmpty)
        #expect(calls.value == 0)
    }

    @Test("a member beside the caller's binary runs when PATH lacks it")
    func besideTheBinary() throws {
        let beside = try TemporaryDirectory()
        let empty = try TemporaryDirectory()
        defer { beside.remove()
            empty.remove()
        }
        let log = beside.url.appendingPathComponent("log")
        try fakeWidget(in: beside.url, log: log)
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: ["PATH": empty.url.path], besideDirectory: beside.url.path)
        #expect(results.map(\.member) == ["widget"])
        #expect(try String(contentsOf: log, encoding: .utf8) == "install --agent cursor --yes|gizmo\n")
    }

    @Test("found members run in the order given")
    func order() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        for name in ["widget", "gadget"] {
            let path = directory.url.appendingPathComponent(name)
            try "#!/bin/sh\nexit 0\n".write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        }
        let gadget = Family.Member(tool: FieldworkTool(name: "gadget"))
        let environment = ["PATH": directory.url.path]
        let forward = Family.install(members: [Family.Member(tool: gizmo), Family.Member(tool: widget), gadget], caller: gizmo, flags: flags, environment: environment) { _, _, _ in 0 }
        #expect(forward.map(\.member) == ["widget", "gadget"])
        let backward = Family.install(members: [gadget, Family.Member(tool: gizmo), Family.Member(tool: widget)], caller: gizmo, flags: flags, environment: environment) { _, _, _ in 0 }
        #expect(backward.map(\.member) == ["gadget", "widget"])
    }

    @Test("a member on PATH and beside the binary runs from PATH")
    func pathWins() throws {
        let onPath = try TemporaryDirectory()
        let beside = try TemporaryDirectory()
        defer { onPath.remove()
            beside.remove()
        }
        try fakeWidget(in: onPath.url, log: onPath.url.appendingPathComponent("log"))
        try fakeWidget(in: beside.url, log: beside.url.appendingPathComponent("log"))
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: ["PATH": onPath.url.path], besideDirectory: beside.url.path) { _, _, _ in 0 }
        #expect(results.map(\.executable) == [onPath.url.appendingPathComponent("widget").standardizedFileURL.path])
    }

    @Test("a member that cannot launch is a returned failure")
    func launchFailure() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try fakeWidget(in: directory.url, log: directory.url.appendingPathComponent("log"))
        struct Refused: Error {}
        let results = Family.install(members: members, caller: gizmo, flags: flags, environment: ["PATH": directory.url.path]) { _, _, _ in throw Refused() }
        #expect(results.count == 1)
        #expect(results.first?.succeeded == false)
        #expect(results.first?.launchFailure != nil)
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
