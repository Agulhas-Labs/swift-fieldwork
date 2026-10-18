// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// A Claude Code config that is there and cannot be read as a JSON object is refused and named, never read as holding no server.
struct ClaudeMcpUnreadableConfigTests {
    private static let binary = "/opt/tools/bin/gizmo"
    private static let install = ClaudeMcpInstall(server: ClaudeMcpServer(tool: FieldworkTool(name: "gizmo")))

    @Test
    func anInstallIntoAnUnparseableConfigRunsNothingAndSaysWhy() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = directory.url.appendingPathComponent(".claude.json")
        try Data("not json {".utf8).write(to: config)
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.isEmpty)
        #expect(outcome.failures.first?.hasPrefix("mcp: not registered — \(config.path) could not be read as a JSON object; repair it, then run: claude mcp add") == true, "\(outcome.failures)")
        #expect(outcome.written.isEmpty)
        #expect(try Data(contentsOf: config) == Data("not json {".utf8))
    }

    /// A config holding nothing but whitespace holds nothing to lose: it reads as absent, and the server is registered.
    @Test(arguments: ["", "  \n\t\r\n"])
    func aConfigHoldingOnlyWhitespaceIsReadAsAbsent(contents: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = directory.url.appendingPathComponent(".claude.json")
        try Data(contents.utf8).write(to: config)
        let claude = FakeClaude(config: config)

        #expect(Self.install.plan(config: config, binary: Self.binary) == .absent)
        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls == [["mcp", "add", "--transport", "stdio", "--scope", "user", "gizmo", "--", Self.binary, "mcp"]])
        #expect(outcome.failures.isEmpty, "\(outcome.failures)")
        #expect(outcome.written == [config.path])
    }

    /// Everything else that is there and is not a JSON object is still refused: a JSON array, a link to nothing, a directory, a file that cannot be opened.
    @Test(arguments: ["array", "dangling symlink", "directory", "unreadable mode"])
    func aConfigThatIsNotAnObjectIsStillRefused(shape: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let config = directory.url.appendingPathComponent(".claude.json")
        switch shape {
        case "array":
            try Data("[]".utf8).write(to: config)
        case "dangling symlink":
            try FileManager.default.createSymbolicLink(at: config, withDestinationURL: directory.url.appendingPathComponent("gone.json"))
        case "directory":
            try FileManager.default.createDirectory(at: config, withIntermediateDirectories: false)
        default:
            try Data("{}".utf8).write(to: config)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: config.path)
        }
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.path) }
        let claude = FakeClaude(config: config)

        let outcome = try Self.install.install(config: config, binary: Self.binary, runner: claude)

        #expect(claude.calls.isEmpty)
        #expect(outcome.failures.first?.hasPrefix("mcp: not registered — \(config.path) could not be read") == true, "\(outcome.failures)")
        #expect(outcome.written.isEmpty)
    }
}
