// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Testing

/// Which entries in `.claude.json` a tool claims as its own server: its binary with exactly its arguments, or `npx` running its package with them, and nothing that merely resembles either.
struct ClaudeMcpRecognitionTests {
    private static let server = ClaudeMcpServer(tool: FieldworkTool(name: "gizmo"), npmPackage: "gizmo")
    private static let withoutPackage = ClaudeMcpServer(tool: FieldworkTool(name: "gizmo"))

    @Test(arguments: [
        ("npx", ["gizmo", "mcp"]),
        ("npx", ["gizmo@1.2", "mcp"]),
        ("npx", ["-y", "gizmo", "mcp"]),
        ("/usr/local/bin/npx", ["--yes", "gizmo", "mcp"]),
        ("/opt/bin/gizmo", ["mcp"]),
    ])
    func anEntryThatRunsTheToolIsClaimed(command: String, arguments: [String]) {
        #expect(Self.server.recognises(command: command, arguments: arguments))
    }

    @Test(arguments: [
        ("npx", ["gizmo-pro", "mcp"]),
        ("npx", ["gizmo-pro@1", "mcp"]),
        ("npx", ["gizmo", "mcp", "extra"]),
        ("npx", ["mcp"]),
        ("/opt/bin/gizmo", ["mcp", "extra"]),
        ("/opt/gizmo/bin/other", ["mcp"]),
    ])
    func anEntryThatMerelyResemblesItIsNot(command: String, arguments: [String]) {
        #expect(!Self.server.recognises(command: command, arguments: arguments))
    }

    @Test
    func withoutAnNpmPackageNoNpxEntryIsClaimed() {
        #expect(!Self.withoutPackage.recognises(command: "npx", arguments: ["gizmo", "mcp"]))
        #expect(!Self.withoutPackage.recognises(command: "npx", arguments: ["-y", "gizmo", "mcp"]))
        #expect(Self.withoutPackage.recognises(command: "/opt/bin/gizmo", arguments: ["mcp"]))
    }
}
