// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The install and uninstall for Cursor over a real directory: both files written, the output a consumer prints, backups, symlinks and refusals.
struct CursorHookInstallerTests {
    private static let tool = CursorTools.gizmo
    private static var foreignServers: String {
        #"{"mcpServers":{"notes":{"args":["serve"],"command":"/opt/notes/bin/notes"}}}"#
    }

    private static var foreignHooks: String {
        #"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh"}]},"version":1}"#
    }

    private static func directory(in root: TemporaryDirectory, named name: String = ".cursor", servers: String?, hooks: String?) throws -> URL {
        let directory = root.url.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (text, file) in [(servers, "mcp.json"), (hooks, "hooks.json")] {
            guard let text else { continue }
            try CursorTools.canonical(text).write(to: directory.appendingPathComponent(file))
        }
        return directory
    }

    private static func bytes(_ directory: URL) throws -> [Data] {
        try ["mcp.json", "hooks.json"].map { try Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    private static func printed(_ result: CursorHookInstallResult) -> String {
        result.printed.joined(separator: "\n")
    }

    @Test
    func theInstallWritesBothFilesAndSaysWhatCursorDoesNotGet() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = root.url.appendingPathComponent(".cursor")
        let binary = "/opt/My Tools/gizmo"

        let result = try Self.tool.installer.install(directory: cursor, binary: binary)

        let servers = try #require(CursorTools.object(Data(contentsOf: cursor.appendingPathComponent("mcp.json")))["mcpServers"] as? [String: Any])
        #expect(servers["gizmo"] as? NSDictionary == ["command": binary, "args": ["mcp"]] as NSDictionary)
        let hooks = try #require(CursorTools.object(Data(contentsOf: cursor.appendingPathComponent("hooks.json")))["hooks"] as? [String: Any])
        #expect((hooks["preToolUse"] as? [[String: String]])?.first == ["command": "'\(binary)' pre-tool-use --agent cursor"])
        let lines = result.printed
        #expect(lines.contains("mcp: registered gizmo — \(binary) mcp"), "\(lines)")
        #expect(lines.contains("hooks: registered sessionStart — '\(binary)' session-start --agent cursor"), "\(lines)")
        #expect(lines.contains(CursorHookInstaller.restart), "\(lines)")
        #expect(lines.suffix(2) == ["unsupported on Cursor: gizmo audit — no documented transcript format", "experimental: not verified in a live Cursor"])
        #expect(result.outcome.written == [cursor.appendingPathComponent("mcp.json").path, cursor.appendingPathComponent("hooks.json").path])
        #expect(lines.contains("      \(cursor.appendingPathComponent("mcp.json").path)"), "\(lines)")
    }

    @Test
    func aSecondInstallWritesNothingAndTheUninstallRestoresTheForeignFiles() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.directory(in: root, servers: Self.foreignServers, hooks: Self.foreignHooks)
        let (mcp, hooksFile) = (cursor.appendingPathComponent("mcp.json"), cursor.appendingPathComponent("hooks.json"))
        let foreign = try Self.bytes(cursor)
        let binary = "/opt/tools/bin/gizmo"

        try Self.tool.installer.install(directory: cursor, binary: binary)
        #expect(try Data(contentsOf: mcp.appendingPathExtension("bak-gizmo")) == foreign[0])
        #expect(try Data(contentsOf: hooksFile.appendingPathExtension("bak-gizmo")) == foreign[1])
        #expect(try ((CursorTools.object(Data(contentsOf: hooksFile))["hooks"] as? [String: Any])?["preToolUse"] as? [Any])?.count == 2)
        let installed = try Self.bytes(cursor)
        for file in [mcp, hooksFile] {
            try FileManager.default.removeItem(at: file.appendingPathExtension("bak-gizmo"))
        }

        let again = try Self.tool.installer.install(directory: cursor, binary: binary)

        #expect(try Self.bytes(cursor) == installed)
        #expect(!FileManager.default.fileExists(atPath: mcp.appendingPathExtension("bak-gizmo").path))
        #expect(!again.outcome.changed)
        #expect(again.printed.contains("mcp: already registered — \(binary) mcp"), "\(again.printed)")
        #expect(Self.printed(again).contains("hooks: already registered"), "\(again.printed)")
        #expect(!again.printed.contains(CursorHookInstaller.restart), "\(again.printed)")

        let removed = try Self.tool.installer.uninstall(directory: cursor)

        #expect(removed.printed.contains("hooks: removed preToolUse — \(binary) pre-tool-use --agent cursor"), "\(removed.printed)")
        #expect(removed.printed.contains(CursorHookInstaller.restartAfterRemoval), "\(removed.printed)")
        #expect(try Self.bytes(cursor) == foreign)
        let removedAgain = try Self.tool.installer.uninstall(directory: cursor)
        #expect(removedAgain.printed == ["cursor: nothing registered in \(cursor.path)"])
        #expect(try Self.bytes(cursor) == foreign)
    }

    @Test
    func aServerOfTheSameNameAndAnotherShapeIsReportedAndLeftAloneWhileTheHooksGoIn() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let servers = #"{"mcpServers":{"gizmo":{"args":["-y","gizmo","mcp"],"command":"npx"}}}"#
        let cursor = try Self.directory(in: root, servers: servers, hooks: nil)
        let mcp = cursor.appendingPathComponent("mcp.json")
        let before = try Data(contentsOf: mcp)

        let result = try Self.tool.installer.install(directory: cursor, binary: "/opt/tools/bin/gizmo")

        #expect(result.printed.contains("mcp: left alone — a server named gizmo runs something else (npx -y gizmo mcp)"), "\(result.printed)")
        #expect(try Data(contentsOf: mcp) == before)
        #expect(FileManager.default.fileExists(atPath: cursor.appendingPathComponent("hooks.json").path))
        let removed = try Self.tool.installer.uninstall(directory: cursor)
        #expect(removed.printed.contains { $0.hasPrefix("mcp: not ours, left alone") }, "\(removed.printed)")
        #expect(try Data(contentsOf: mcp) == before)
    }

    @Test
    func symlinkedFilesAreWrittenThroughAndStayLinks() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let dotfiles = try Self.directory(in: root, named: "dotfiles", servers: Self.foreignServers, hooks: Self.foreignHooks)
        let cursor = root.url.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        for name in ["mcp.json", "hooks.json"] {
            try FileManager.default.createSymbolicLink(atPath: cursor.appendingPathComponent(name).path, withDestinationPath: "../dotfiles/\(name)")
        }

        let result = try Self.tool.installer.install(directory: cursor, binary: "/opt/tools/bin/gizmo")

        for name in ["mcp.json", "hooks.json"] {
            #expect(PathKind.of(cursor.appendingPathComponent(name)) == .symlink("../dotfiles/\(name)"))
            #expect(FileManager.default.fileExists(atPath: dotfiles.appendingPathComponent("\(name).bak-gizmo").path), "\(name)")
            #expect(!FileManager.default.fileExists(atPath: cursor.appendingPathComponent("\(name).bak-gizmo").path), "\(name)")
        }

        #expect(try (CursorTools.object(Data(contentsOf: dotfiles.appendingPathComponent("mcp.json")))["mcpServers"] as? [String: Any])?["gizmo"] != nil)
        #expect(result.outcome.written.first?.hasPrefix("\(cursor.path)/mcp.json → ") == true, "\(result.outcome.written)")
    }

    @Test
    func anUnreadableFileIsRefusedAndNeitherFileIsWritten() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.directory(in: root, servers: Self.foreignServers, hooks: Self.foreignHooks)
        let mcp = cursor.appendingPathComponent("mcp.json")
        let before = try Self.bytes(cursor)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: mcp.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: mcp.path) }

        #expect(throws: SettingsFile.Refused.self) { try Self.tool.installer.install(directory: cursor, binary: "/opt/tools/bin/gizmo") }
        #expect(throws: SettingsFile.Refused.self) { try Self.tool.installer.uninstall(directory: cursor) }

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: mcp.path)
        #expect(try Self.bytes(cursor) == before)
        #expect(!FileManager.default.fileExists(atPath: mcp.appendingPathExtension("bak-gizmo").path))
    }

    @Test
    func aLinkThatLeadsNowhereIsRefusedNamingTheDirectoryFlag() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = root.url.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: cursor.appendingPathComponent("hooks.json").path, withDestinationPath: "../nowhere/hooks.json")

        let error = try #require(throws: SettingsFile.Refused.self) { try Self.tool.installer.install(directory: cursor, binary: "/opt/tools/bin/gizmo") }

        #expect(error.description.contains("--cursor-dir"), "\(error)")
        #expect(!FileManager.default.fileExists(atPath: cursor.appendingPathComponent("mcp.json").path))
    }

    @Test
    func theStepReportsTheLinesTheFilesAndNoFailures() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let step = CursorInstallStep(installer: Self.tool.installer)

        let report = try step.run(binary: "/opt/tools/bin/gizmo", environment: ["CFFIXED_USER_HOME": root.url.path])

        #expect(report.agent == .cursor)
        #expect(report.written.count == 2)
        #expect(report.failures.isEmpty)
        #expect(report.lines.contains("mcp: registered gizmo — /opt/tools/bin/gizmo mcp"), "\(report.lines)")
        #expect(FileManager.default.fileExists(atPath: root.url.appendingPathComponent(".cursor/mcp.json").path))
    }
}
