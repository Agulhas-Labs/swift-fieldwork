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

    @Test
    func uninstallingBothRestoresTheSeededFilesByteForByte() throws {
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
