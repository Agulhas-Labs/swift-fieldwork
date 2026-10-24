// Copyright 2026 Agulhas Labs
// SPDX-License-Identifier: Apache-2.0

@testable import Fieldwork
import Foundation
import Testing

/// Covers two tools sharing one Codex `hooks.json`: each apply and removal touches only the handlers that run the tool's own binary.
struct TwoToolsCodexTests {
    private static let gizmo = CodexTools.gizmo.file
    private static let widget = CodexTools.widget.file

    /// The user's own handler on an event both tools register for, a group of their own on another, and a key no tool writes.
    private static var seed: String {
        #"{"hooks":{"PreToolUse":[{"hooks":[{"command":"/usr/local/bin/audit-log pre","timeout":10,"type":"command"}],"matcher":"Bash"}],"Stop":[{"hooks":[{"command":"/usr/local/bin/notify.sh","type":"command"}]}]},"theme":"dark"}"#
    }

    /// Uninstalling either tool, whichever applied first, leaves the other tool's handlers, the user's own and every other key exactly as applying only the other tool to the same file would.
    ///
    /// Removing both leaves the file as it was seeded.
    @Test(arguments: [false, true], [false, true])
    func removingEitherLeavesEverythingElseByteIdentical(gizmoFirst: Bool, removeGizmo: Bool) throws {
        let original = try CodexTools.canonical(Self.seed)
        let gizmo = (file: Self.gizmo, binary: "/bin/gizmo")
        let widget = (file: Self.widget, binary: "/bin/widget")
        var both = original
        for tool in gizmoFirst ? [gizmo, widget] : [widget, gizmo] {
            both = try tool.file.apply(to: both, binaryWord: tool.binary).data
        }
        let removed = removeGizmo ? gizmo : widget
        let survivor = removeGizmo ? widget : gizmo

        let afterRemoval = try removed.file.remove(from: both)
        let survivorAlone = try survivor.file.apply(to: original, binaryWord: survivor.binary)
        let afterBoth = try survivor.file.remove(from: afterRemoval.data)

        #expect(afterRemoval.changed)
        #expect(afterRemoval.data == survivorAlone.data)
        #expect(afterBoth.data == original)
        #expect(try Self.gizmo.remove(from: survivorAlone.data).changed == !removeGizmo)
    }

    @Test func neitherToolClaimsTheOthersHandlers() throws {
        let widgetOnly = try Self.widget.apply(to: Data(Self.seed.utf8), binaryWord: "/bin/widget")
        let gizmoOnly = try Self.gizmo.apply(to: Data(Self.seed.utf8), binaryWord: "/bin/gizmo")

        #expect(try !Self.gizmo.remove(from: widgetOnly.data).changed)
        #expect(try !Self.widget.remove(from: gizmoOnly.data).changed)
        #expect(Self.gizmo.commands(in: widgetOnly.data, for: CodexTools.gizmo.file.hooks[1]).isEmpty)
        #expect(Self.widget.commands(in: widgetOnly.data, for: CodexTools.widget.file.hooks[0]) == ["/bin/widget pre-tool-use"])
    }
}
