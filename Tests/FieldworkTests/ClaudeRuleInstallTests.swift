// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// The agent rule a tool's install copies in: found beside the binary or in Homebrew's share directory, copied when absent, kept when identical or linked, and backed up before a differing one is replaced.
struct ClaudeRuleInstallTests {
    private static let tool = FieldworkTool(name: "gizmo")
    private static let install = ClaudeRuleInstall(tool: tool, shippedFileName: "Gizmo.md", loadsOn: "**/*.swift")

    private static func layout(in root: URL) throws -> (source: URL, destination: URL) {
        let source = root.appendingPathComponent("bundle/Gizmo.md")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "the rule".write(to: source, atomically: true, encoding: .utf8)
        return (source, root.appendingPathComponent("home/.claude/rules/gizmo.md"))
    }

    @Test
    func anAbsentRuleIsCopiedAndAnIdenticalOneLeft() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let (source, destination) = try Self.layout(in: directory.url)

        let first = try Self.install.install(source: source, destination: destination)
        #expect(first.lines == ["rule: installed \(destination.path) (loads on **/*.swift)"])
        #expect(first.written == [destination.path])
        #expect(try String(contentsOf: destination, encoding: .utf8) == "the rule")

        let second = try Self.install.install(source: source, destination: destination)
        #expect(second.lines == ["rule: already installed — \(destination.path)"])
        #expect(!second.changed)
        #expect(PathKind.of(SettingsBackupFile.url(beside: destination, tool: Self.tool)) == .absent)
    }

    @Test
    func aDifferingRuleIsKeptAsABackupThenReplaced() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let (source, destination) = try Self.layout(in: directory.url)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "my own edits".write(to: destination, atomically: true, encoding: .utf8)
        let backup = destination.deletingLastPathComponent().appendingPathComponent("gizmo.md.bak-gizmo")

        let outcome = try Self.install.install(source: source, destination: destination)

        #expect(try String(contentsOf: backup, encoding: .utf8) == "my own edits")
        #expect(try String(contentsOf: destination, encoding: .utf8) == "the rule")
        #expect(outcome.lines == ["rule: installed \(destination.path) (loads on **/*.swift) (the previous one kept as \(backup.path))"])
    }

    @Test
    func aSymlinkedRuleIsLeftAlone() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let (source, destination) = try Self.layout(in: directory.url)
        let checkout = source.deletingLastPathComponent().appendingPathComponent("checkout.md")
        try "checkout rule".write(to: checkout, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: checkout.path)

        let outcome = try Self.install.install(source: source, destination: destination)

        #expect(outcome.lines == ["rule: \(destination.path) is a symlink to \(checkout.path) — left as is"])
        #expect(try String(contentsOf: checkout, encoding: .utf8) == "checkout rule")
        #expect(!outcome.changed)
    }

    @Test
    func withoutAShippedRuleTheStepIsSkippedWithANote() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let (_, destination) = try Self.layout(in: directory.url)
        let binary = directory.url.appendingPathComponent("npm-bin/gizmo")
        try FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "binary".write(to: binary, atomically: true, encoding: .utf8)

        let source = Self.install.source(forBinary: binary.path)
        let outcome = try Self.install.install(source: source, destination: destination)

        #expect(source == nil)
        #expect(outcome.notes == ["rule: skipped — no Gizmo.md ships with this binary (install.sh writes it; `gizmo install` from Homebrew or npm copies the Gizmo.md they ship)"])
        #expect(PathKind.of(destination) == .absent)
    }

    @Test
    func theRuleIsFoundBesideTheBinaryOrInHomebrewsShareThroughALink() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let root = directory.url
        let manager = FileManager.default
        let bundle = root.appendingPathComponent("bundle")
        try manager.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "binary".write(to: bundle.appendingPathComponent("gizmo"), atomically: true, encoding: .utf8)
        try "rule".write(to: bundle.appendingPathComponent("Gizmo.md"), atomically: true, encoding: .utf8)
        #expect(Self.install.source(forBinary: bundle.appendingPathComponent("gizmo").path)?.lastPathComponent == "Gizmo.md")

        let cellar = root.appendingPathComponent("Cellar/gizmo/1.0")
        try manager.createDirectory(at: cellar.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try manager.createDirectory(at: cellar.appendingPathComponent("share/gizmo"), withIntermediateDirectories: true)
        try "binary".write(to: cellar.appendingPathComponent("bin/gizmo"), atomically: true, encoding: .utf8)
        try "rule".write(to: cellar.appendingPathComponent("share/gizmo/Gizmo.md"), atomically: true, encoding: .utf8)
        let linkDirectory = root.appendingPathComponent("bin")
        try manager.createDirectory(at: linkDirectory, withIntermediateDirectories: true)
        try manager.createSymbolicLink(atPath: linkDirectory.appendingPathComponent("gizmo").path, withDestinationPath: "../Cellar/gizmo/1.0/bin/gizmo")

        let found = try #require(Self.install.source(forBinary: linkDirectory.appendingPathComponent("gizmo").path))
        #expect(found.path.hasSuffix("Cellar/gizmo/1.0/share/gizmo/Gizmo.md"))
    }
}
