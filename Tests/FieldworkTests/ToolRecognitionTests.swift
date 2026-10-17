// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers how a tool recognises a registered shell command as its own.
struct ToolRecognitionTests {
    private let tool = FieldworkTool(name: "gizmo", hookSubcommands: ["pre-tool-use", "stop"])

    /// The tool's binary, by path or quoted path, running exactly the subcommand.
    @Test(arguments: [
        ("/opt/bin/gizmo pre-tool-use", "pre-tool-use"),
        ("'/My Tools/gizmo' stop", "stop"),
    ])
    func runsRecognisesTheBinaryRunningTheSubcommand(command: String, subcommand: String) {
        #expect(tool.runs(command, subcommand: subcommand))
    }

    /// An extra argument, another subcommand or another binary is not the tool running that subcommand.
    @Test(arguments: [
        "/opt/bin/gizmo stop --verbose",
        "/opt/bin/gizmo pre-tool-use",
        "/opt/bin/other stop",
        "python3 tools/gizmo stop",
        "/opt/gizmoworks/x stop",
    ])
    func runsRejectsWhatIsNotTheBinaryRunningExactlyThatSubcommand(command: String) {
        #expect(!tool.runs(command, subcommand: "stop"))
    }

    /// A wrapper, an assignment or a package runner in front of the tool still mentions it.
    @Test(arguments: [
        "env FOO=1 gizmo stop",
        "exec gizmo pre-tool-use",
        "npx -y gizmo@1.2 stop",
        "bunx gizmo stop",
    ])
    func isMentionedSeesThroughWrappers(command: String) {
        #expect(tool.isMentioned(in: command))
    }

    /// Another package, or an unknown subcommand, is not a mention.
    @Test(arguments: ["npx other stop", "gizmo unknown-sub", "cd ~/gizmo && make"])
    func isMentionedRejectsOtherCommands(command: String) {
        #expect(!tool.isMentioned(in: command))
    }

    /// An older install wrote an absolute path with a space in it unquoted, and a check for any trace counts that shape whether or not the binary is still there.
    @Test
    func isMentionedCountsTheUnquotedAbsolutePathShapeWithoutTheFile() {
        #expect(tool.isMentioned(in: "/Applications/My Tools/gizmo stop"))
    }

    /// The same words without a leading slash, or with a path that does not end in the tool's name, are not the shape.
    @Test(arguments: ["My Tools/gizmo stop", "/Applications/My Tools/other stop", "/Applications/My Tools/gizmo stop --verbose"])
    func isMentionedRejectsWhatDoesNotHaveTheUnquotedShape(command: String) {
        #expect(!tool.isMentioned(in: command))
    }

    /// An unquoted path with a space in it that names an existing executable called `gizmo` is the tool running the subcommand.
    @Test
    func runsClaimsAnUnquotedPathToAnInstalledBinary() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let binary = try installBinary(named: "gizmo", under: "My Tools", in: directory)

        #expect(tool.runs("\(binary.path) stop", subcommand: "stop"))
    }

    /// The same unquoted path is not claimed when no file is there, when a directory is, or when the file has another name.
    @Test
    func runsRejectsAnUnquotedPathThatNamesNoInstalledBinary() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let binary = try installBinary(named: "gizmo", under: "My Tools", in: directory)
        let other = try installBinary(named: "other", under: "My Tools", in: directory)
        let folder = directory.url.appendingPathComponent("Some Place/gizmo", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.removeItem(at: binary)

        #expect(!tool.runs("\(binary.path) stop", subcommand: "stop"))
        #expect(!tool.runs("\(folder.path) stop", subcommand: "stop"))
        #expect(!tool.runs("\(other.path) stop", subcommand: "stop"))
    }

    /// An executable file `name` inside `folder` of `directory`, a folder whose name has a space in it.
    private func installBinary(named name: String, under folder: String, in directory: TemporaryDirectory) throws -> URL {
        let parent = directory.url.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let file = parent.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }
}
