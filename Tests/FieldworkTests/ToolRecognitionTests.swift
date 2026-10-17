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
}
