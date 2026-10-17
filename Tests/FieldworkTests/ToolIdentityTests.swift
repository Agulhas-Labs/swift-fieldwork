// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers the one place a consumer's identity enters: a name given to `FieldworkTool` reaches the text a file or a message carries.
struct ToolIdentityTests {
    /// The backup beside a settings file carries the tool's name, written here as a literal.
    @Test
    func theSettingsBackupIsNamedForTheTool() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = directory.url.appendingPathComponent("settings.json")
        let tool = FieldworkTool(name: "gizmo")

        #expect(SettingsBackupFile.url(beside: settings, tool: tool).lastPathComponent == "settings.json.bak-gizmo")
        #expect(SettingsBackupFile.write(Data("{}".utf8), beside: settings, tool: tool) == nil)
        #expect(try String(contentsOf: directory.url.appendingPathComponent("settings.json.bak-gizmo"), encoding: .utf8) == "{}")
    }

    /// A rewrite keeps the original under the tool's name too.
    @Test
    func aRewriteKeepsTheOriginalUnderTheToolsName() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = directory.url.appendingPathComponent("settings.json")
        try Data("old".utf8).write(to: settings)

        let note = try SettingsFile.rewrite(settings, with: Data("new".utf8), original: Data("old".utf8), tool: FieldworkTool(name: "gizmo"))

        #expect(note == nil)
        #expect(try String(contentsOf: settings, encoding: .utf8) == "new")
        #expect(try String(contentsOf: directory.url.appendingPathComponent("settings.json.bak-gizmo"), encoding: .utf8) == "old")
    }
}
