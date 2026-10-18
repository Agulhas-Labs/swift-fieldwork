// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers two tools sharing one Claude Code `settings.json`: each install and uninstall touches only the entries whose command runs the tool's own binary.
struct TwoToolsClaudeTests {
    private static let widget = HookRegistration(
        tool: FieldworkTool(name: "widget", hookSubcommands: ["session-start", "pre-tool-use"]),
        events: [
            HookRegistration.Event(name: "SessionStart", subcommand: "session-start", matchers: ["startup", "resume"], timeout: 5),
            HookRegistration.Event(name: "PreToolUse", subcommand: "pre-tool-use", matchers: ["Bash|Read"], timeout: 5),
        ]
    )

    /// What an install does: merge every event, and rewrite the file with a backup of the original only when something changed.
    private static func install(_ registration: HookRegistration, binary: String, into settings: URL) throws {
        let original = try? Data(contentsOf: settings)
        var merged = original
        var changed = false
        for event in registration.events {
            let result = try registration.apply(to: merged, command: "\(binary) \(event.subcommand)", event: event)
            merged = result.data
            changed = changed || result.changed
        }
        guard changed, let merged else { return }
        _ = try SettingsFile.rewrite(settings, with: merged, original: original, tool: registration.tool)
    }

    private static func uninstall(_ registration: HookRegistration, from settings: URL) throws {
        let original = try Data(contentsOf: settings)
        var current = original
        for event in registration.events {
            current = try registration.remove(from: current, event: event).data
        }
        guard current != original else { return }
        _ = try SettingsFile.rewrite(settings, with: current, original: original, tool: registration.tool)
    }

    private static func commands(_ settings: URL) throws -> [String] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        return hooks.values
            .flatMap { $0 as? [[String: Any]] ?? [] }
            .flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
            .compactMap { $0["command"] as? String }
            .sorted()
    }

    private static func seededSettings(in directory: TemporaryDirectory) throws -> URL {
        let settings = directory.url.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)
        return settings
    }

    /// Re-running either install over a file both have installed into writes nothing, so the bytes are the same.
    @Test
    func reRunningEitherInstallLeavesTheFileByteIdentical() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = try Self.seededSettings(in: directory)
        try Self.install(GizmoHooks.registration, binary: "/bin/gizmo", into: settings)
        try Self.install(Self.widget, binary: "/bin/widget", into: settings)
        let installed = try Data(contentsOf: settings)

        try Self.install(GizmoHooks.registration, binary: "/bin/gizmo", into: settings)
        #expect(try Data(contentsOf: settings) == installed)
        try Self.install(Self.widget, binary: "/bin/widget", into: settings)
        #expect(try Data(contentsOf: settings) == installed)
    }

    /// Uninstalling one tool removes its entries, including the ones on a matcher both tools register, and none of the other's.
    @Test
    func uninstallingOneToolLeavesTheOthersEntries() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = try Self.seededSettings(in: directory)
        try Self.install(GizmoHooks.registration, binary: "/bin/gizmo", into: settings)
        try Self.install(Self.widget, binary: "/bin/widget", into: settings)

        try Self.uninstall(GizmoHooks.registration, from: settings)
        let afterGizmo = try Self.commands(settings)
        #expect(afterGizmo == ["/bin/widget pre-tool-use", "/bin/widget session-start", "/bin/widget session-start"])

        try Self.install(GizmoHooks.registration, binary: "/bin/gizmo", into: settings)
        try Self.uninstall(Self.widget, from: settings)
        let afterWidget = try Self.commands(settings)
        #expect(afterWidget.allSatisfy { $0.hasPrefix("/bin/gizmo ") })
        #expect(afterWidget.count == 9)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any])
        #expect(object["theme"] as? String == "dark")
    }

    /// Each tool keeps the file as it found it under its own name, so two installs leave two backups and neither overwrites the other's.
    @Test
    func eachInstallLeavesItsOwnBackup() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = try Self.seededSettings(in: directory)
        try Self.install(GizmoHooks.registration, binary: "/bin/gizmo", into: settings)
        let afterGizmo = try Data(contentsOf: settings)
        try Self.install(Self.widget, binary: "/bin/widget", into: settings)

        let gizmoBackup = directory.url.appendingPathComponent("settings.json.bak-gizmo")
        let widgetBackup = directory.url.appendingPathComponent("settings.json.bak-widget")
        #expect(try Data(contentsOf: gizmoBackup) == Data(#"{"theme":"dark"}"#.utf8))
        #expect(try Data(contentsOf: widgetBackup) == afterGizmo)
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.url.path).filter { $0.contains(".bak-") }
        #expect(backups.sorted() == ["settings.json.bak-gizmo", "settings.json.bak-widget"])
    }
}
