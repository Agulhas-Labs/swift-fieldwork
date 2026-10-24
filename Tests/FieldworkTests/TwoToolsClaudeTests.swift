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

    private static func commands(_ settings: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String] {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any], sourceLocation: sourceLocation)
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

    /// Every hook entry whose command passes `isMatch`, as canonical bytes in file order, each with its event and its group's matcher.
    private static func entries(_ object: [String: Any], where isMatch: (String) -> Bool) throws -> [Data] {
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        var result: [Data] = []
        for event in hooks.keys.sorted() {
            for group in hooks[event] as? [[String: Any]] ?? [] {
                for hook in group["hooks"] as? [[String: Any]] ?? [] {
                    guard let command = hook["command"] as? String, isMatch(command) else { continue }
                    let entry: [String: Any] = ["event": event, "matcher": group["matcher"] ?? NSNull(), "hook": hook]
                    try result.append(JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]))
                }
            }
        }
        return result
    }

    private static func parsed(_ settings: URL, sourceLocation: SourceLocation = #_sourceLocation) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as? [String: Any], sourceLocation: sourceLocation)
    }

    private static func withoutHooks(_ object: [String: Any]) throws -> Data {
        var rest = object
        rest["hooks"] = nil
        return try JSONSerialization.data(withJSONObject: rest, options: [.sortedKeys])
    }

    /// Uninstalling either tool, whichever installed first, leaves the other tool's entries, the user's own hooks and every other key exactly as they were.
    ///
    /// The user's hooks share a matcher group with each tool's entries, so a removal that touched a neighbour would change them.
    ///
    /// The surviving tool's install, run again, finds its registration intact and writes nothing.
    @Test(arguments: [false, true], [false, true])
    func uninstallingEitherLeavesEverythingElseByteIdentical(gizmoFirst: Bool, uninstallGizmo: Bool) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let settings = directory.url.appendingPathComponent("settings.json")
        let userHooks = #"""
        {"hooks":{"PreToolUse":[{"matcher":"Bash|Read","hooks":[{"type":"command","command":"/usr/local/bin/audit-log pre","timeout":10}]}],
        "Stop":[{"hooks":[{"type":"command","command":"/usr/local/bin/audit-log stop"}]}]},"theme":"dark"}
        """#
        try Data(userHooks.utf8).write(to: settings)

        let gizmo = (registration: GizmoHooks.registration, binary: "/bin/gizmo")
        let widget = (registration: Self.widget, binary: "/bin/widget")
        let order = gizmoFirst ? [gizmo, widget] : [widget, gizmo]
        for tool in order {
            try Self.install(tool.registration, binary: tool.binary, into: settings)
        }
        let removed = uninstallGizmo ? gizmo : widget
        let survivor = uninstallGizmo ? widget : gizmo
        let isRemoved: (String) -> Bool = { $0.hasPrefix("\(removed.binary) ") }
        let isSurvivor: (String) -> Bool = { $0.hasPrefix("\(survivor.binary) ") }
        let isUser: (String) -> Bool = { $0.hasPrefix("/usr/local/bin/audit-log ") }

        let both = try Self.parsed(settings)
        let survivorBefore = try Self.entries(both, where: isSurvivor)
        let userBefore = try Self.entries(both, where: isUser)
        let restBefore = try Self.withoutHooks(both)
        #expect(!survivorBefore.isEmpty)
        #expect(userBefore.count == 2)

        try Self.uninstall(removed.registration, from: settings)
        let after = try Self.parsed(settings)
        #expect(try Self.entries(after, where: isRemoved).isEmpty)
        #expect(try Self.entries(after, where: isSurvivor) == survivorBefore)
        #expect(try Self.entries(after, where: isUser) == userBefore)
        #expect(try Self.withoutHooks(after) == restBefore)

        let uninstalled = try Data(contentsOf: settings)
        try Self.install(survivor.registration, binary: survivor.binary, into: settings)
        #expect(try Data(contentsOf: settings) == uninstalled)
    }
}
