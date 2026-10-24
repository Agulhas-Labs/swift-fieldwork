// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers two tools sharing one Cursor `mcp.json` and `hooks.json`: each install and uninstall touches only the entries that run the tool's own binary, and each keeps its own backup.
struct TwoToolsCursorTests {
    private static let gizmo = CursorTools.gizmo
    private static let widget = CursorTools.widget

    private static func files(_ directory: URL) throws -> [Data] {
        try ["mcp.json", "hooks.json"].map { try Data(contentsOf: directory.appendingPathComponent($0)) }
    }

    private static func servers(_ directory: URL) throws -> [String] {
        let file = try CursorTools.object(Data(contentsOf: directory.appendingPathComponent("mcp.json")))
        return ((file["mcpServers"] as? [String: Any]) ?? [:]).keys.sorted()
    }

    private static func commands(_ directory: URL) throws -> [String] {
        let file = try CursorTools.object(Data(contentsOf: directory.appendingPathComponent("hooks.json")))
        let hooks = file["hooks"] as? [String: Any] ?? [:]
        return hooks.values
            .flatMap { $0 as? [[String: Any]] ?? [] }
            .compactMap { $0["command"] as? String }
            .sorted()
    }

    /// A Cursor directory holding someone else's server and hook, which neither tool may disturb.
    private static func seeded(in root: TemporaryDirectory) throws -> URL {
        let directory = root.url.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"notes":{"args":["serve"],"command":"/opt/notes/bin/notes"}}}"#.utf8).write(to: directory.appendingPathComponent("mcp.json"))
        try Data(#"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log.sh"}]},"version":1}"#.utf8).write(to: directory.appendingPathComponent("hooks.json"))
        return directory
    }

    @Test
    func reRunningEitherInstallLeavesBothFilesByteIdentical() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.seeded(in: root)
        try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        try Self.widget.installer.install(directory: cursor, binary: "/bin/widget")
        let installed = try Self.files(cursor)

        let again = try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        #expect(!again.outcome.changed)
        #expect(try Self.files(cursor) == installed)
        let widgetAgain = try Self.widget.installer.install(directory: cursor, binary: "/bin/widget")
        #expect(!widgetAgain.outcome.changed)
        #expect(try Self.files(cursor) == installed)
        #expect(try Self.servers(cursor) == ["gizmo", "notes", "widget"])
    }

    @Test
    func uninstallingOneToolRemovesExactlyItsOwnEntries() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.seeded(in: root)
        try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        try Self.widget.installer.install(directory: cursor, binary: "/bin/widget")

        try Self.gizmo.installer.uninstall(directory: cursor)
        #expect(try Self.servers(cursor) == ["notes", "widget"])
        let afterGizmo = try Self.commands(cursor)
        #expect(afterGizmo.filter { $0.hasPrefix("/bin/widget ") }.count == 4)
        #expect(afterGizmo.contains("/usr/local/bin/audit-log.sh"))
        #expect(afterGizmo.count == 5)

        try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        try Self.widget.installer.uninstall(directory: cursor)
        #expect(try Self.servers(cursor) == ["gizmo", "notes"])
        let afterWidget = try Self.commands(cursor)
        #expect(afterWidget.filter { $0.hasPrefix("/bin/gizmo ") }.count == 4)
        #expect(afterWidget.count == 5)
    }

    /// Uninstalling both tools leaves only the user's own server and hook.
    ///
    /// The files are rewritten, not restored, so their bytes can differ from the seeded text.
    @Test
    func uninstallingBothLeavesOnlyTheSeededEntries() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.seeded(in: root)
        try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        try Self.widget.installer.install(directory: cursor, binary: "/bin/widget")

        try Self.widget.installer.uninstall(directory: cursor)
        try Self.gizmo.installer.uninstall(directory: cursor)

        #expect(try Self.servers(cursor) == ["notes"])
        #expect(try Self.commands(cursor) == ["/usr/local/bin/audit-log.sh"])
    }

    /// Every hook entry whose command passes `isMatch`, as canonical bytes in file order, each with its event.
    private static func entries(_ object: [String: Any], where isMatch: (String) -> Bool) throws -> [Data] {
        let hooks = object["hooks"] as? [String: Any] ?? [:]
        var result: [Data] = []
        for event in hooks.keys.sorted() {
            for hook in hooks[event] as? [[String: Any]] ?? [] {
                guard let command = hook["command"] as? String, isMatch(command) else { continue }
                let entry: [String: Any] = ["event": event, "hook": hook]
                try result.append(JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]))
            }
        }
        return result
    }

    private static func canonicalBytes(_ value: Any?) throws -> Data {
        try JSONSerialization.data(withJSONObject: value ?? NSNull(), options: [.sortedKeys, .fragmentsAllowed])
    }

    private static func without(_ key: String, in directory: URL, file: String) throws -> Data {
        var rest = try CursorTools.object(Data(contentsOf: directory.appendingPathComponent(file)))
        rest[key] = nil
        return try canonicalBytes(rest)
    }

    private static func server(_ name: String, in directory: URL) throws -> Data {
        let file = try CursorTools.object(Data(contentsOf: directory.appendingPathComponent("mcp.json")))
        return try canonicalBytes((file["mcpServers"] as? [String: Any])?[name])
    }

    /// Uninstalling either tool, whichever installed first, leaves the other tool's server and hooks, the user's own server and hooks and every other key in both files exactly as they were.
    ///
    /// The user's hooks sit in two events that both tools also register for, so a removal that touched or reordered a neighbour would change them.
    ///
    /// The surviving tool's install, run again, finds its registration intact and writes nothing.
    @Test(arguments: [false, true], [false, true])
    func uninstallingEitherLeavesEverythingElseByteIdentical(gizmoFirst: Bool, uninstallGizmo: Bool) throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = root.url.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"notes":{"args":["serve"],"command":"/opt/notes/bin/notes","env":{"MODE":"quiet"}}},"theme":"dark"}"#.utf8).write(to: cursor.appendingPathComponent("mcp.json"))
        let userHooks = #"{"hooks":{"preToolUse":[{"command":"/usr/local/bin/audit-log pre","timeout":10}],"postToolUse":[{"command":"/usr/local/bin/audit-log post","matcher":"Shell"}]},"version":1}"#
        try Data(userHooks.utf8).write(to: cursor.appendingPathComponent("hooks.json"))

        let gizmo = (tools: Self.gizmo, binary: "/bin/gizmo", name: "gizmo")
        let widget = (tools: Self.widget, binary: "/bin/widget", name: "widget")
        for tool in gizmoFirst ? [gizmo, widget] : [widget, gizmo] {
            try tool.tools.installer.install(directory: cursor, binary: tool.binary)
        }
        let removed = uninstallGizmo ? gizmo : widget
        let survivor = uninstallGizmo ? widget : gizmo
        let isRemoved: (String) -> Bool = { $0.hasPrefix("\(removed.binary) ") }
        let isSurvivor: (String) -> Bool = { $0.hasPrefix("\(survivor.binary) ") }
        let isUser: (String) -> Bool = { $0.hasPrefix("/usr/local/bin/audit-log ") }

        let both = try CursorTools.object(Data(contentsOf: cursor.appendingPathComponent("hooks.json")))
        let survivorBefore = try Self.entries(both, where: isSurvivor)
        let userBefore = try Self.entries(both, where: isUser)
        let keptBefore = try Self.entries(both, where: { !isRemoved($0) })
        let hooksRestBefore = try Self.without("hooks", in: cursor, file: "hooks.json")
        let mcpRestBefore = try Self.without("mcpServers", in: cursor, file: "mcp.json")
        let survivorServerBefore = try Self.server(survivor.name, in: cursor)
        let notesBefore = try Self.server("notes", in: cursor)
        #expect(try !Self.entries(both, where: isRemoved).isEmpty)
        #expect(!survivorBefore.isEmpty)
        #expect(userBefore.count == 2)
        #expect(try Self.servers(cursor) == ["gizmo", "notes", "widget"])

        try removed.tools.installer.uninstall(directory: cursor)
        let after = try CursorTools.object(Data(contentsOf: cursor.appendingPathComponent("hooks.json")))
        #expect(try Self.entries(after, where: isRemoved).isEmpty)
        #expect(try Self.entries(after, where: isSurvivor) == survivorBefore)
        #expect(try Self.entries(after, where: isUser) == userBefore)
        #expect(try Self.entries(after, where: { _ in true }) == keptBefore)
        #expect(try Self.without("hooks", in: cursor, file: "hooks.json") == hooksRestBefore)
        #expect(try Self.servers(cursor) == [survivor.name, "notes"].sorted())
        #expect(try Self.server(survivor.name, in: cursor) == survivorServerBefore)
        #expect(try Self.server("notes", in: cursor) == notesBefore)
        #expect(try Self.without("mcpServers", in: cursor, file: "mcp.json") == mcpRestBefore)

        let uninstalled = try Self.files(cursor)
        let again = try survivor.tools.installer.install(directory: cursor, binary: survivor.binary)
        #expect(!again.outcome.changed)
        #expect(try Self.files(cursor) == uninstalled)
    }

    @Test
    func eachInstallLeavesItsOwnBackupOfEachFile() throws {
        let root = try TemporaryDirectory()
        defer { root.remove() }
        let cursor = try Self.seeded(in: root)
        let seeded = try Self.files(cursor)
        try Self.gizmo.installer.install(directory: cursor, binary: "/bin/gizmo")
        let afterGizmo = try Self.files(cursor)
        try Self.widget.installer.install(directory: cursor, binary: "/bin/widget")

        for (index, name) in ["mcp.json", "hooks.json"].enumerated() {
            #expect(try Data(contentsOf: cursor.appendingPathComponent("\(name).bak-gizmo")) == seeded[index], "\(name)")
            #expect(try Data(contentsOf: cursor.appendingPathComponent("\(name).bak-widget")) == afterGizmo[index], "\(name)")
        }
        let backups = try FileManager.default.contentsOfDirectory(atPath: cursor.path).filter { $0.contains(".bak-") }

        #expect(backups.sorted() == ["hooks.json.bak-gizmo", "hooks.json.bak-widget", "mcp.json.bak-gizmo", "mcp.json.bak-widget"])
    }
}
