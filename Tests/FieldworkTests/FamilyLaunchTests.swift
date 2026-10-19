// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

import Darwin
@testable import Fieldwork
import Foundation
import Testing

@Suite("Family launch")
struct FamilyLaunchTests {
    /// The environment every member script here runs with: a plain PATH and nothing else.
    private let environment = ["PATH": "/bin:/usr/bin"]

    private func script(_ body: String, named name: String, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent(name)
        try "#!/bin/sh\n\(body)\n".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        return path.path
    }

    @Test("the member runs in the caller's process group, the terminal's foreground one")
    func sharesProcessGroup() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let output = directory.url.appendingPathComponent("pgid")
        let member = try script("ps -o pgid= -p $$ > '\(output.path)'", named: "widget", in: directory.url)
        let status = try Family.launchInheritingTerminal(member, [], environment)
        #expect(status == 0)
        let recorded = try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(Int32(recorded) == getpgrp())
    }

    @Test("a member ended by SIGINT reports 130, and starts with SIGINT's default handling")
    func signalDeathIsShellStatus() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let member = try script("kill -INT $$\nexit 0", named: "widget", in: directory.url)
        #expect(try Family.launchInheritingTerminal(member, [], environment) == 130)
    }

    @Test("a member's exit code is returned as it is")
    func exitCode() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let member = try script("exit 7", named: "widget", in: directory.url)
        #expect(try Family.launchInheritingTerminal(member, [], environment) == 7)
    }

    @Test("a member that cannot be spawned is a returned failure with status 127")
    func spawnFailure() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.url.appendingPathComponent("widget")
        try "#!/nonexistent/interpreter\n".write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
        let members = [Family.Member(tool: FieldworkTool(name: "gizmo")), Family.Member(tool: FieldworkTool(name: "widget"))]
        let results = Family.install(members: members, caller: FieldworkTool(name: "gizmo"), flags: AgentSelection.Flags(), environment: ["PATH": directory.url.path])
        #expect(results.count == 1)
        #expect(results.first?.exitStatus == 127)
        #expect(results.first?.launchFailure?.hasPrefix("posix_spawn failed for ") == true)
    }
}
